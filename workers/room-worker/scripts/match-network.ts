import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { ROOM_SCHEMA_VERSION } from "../src/room-state.ts";

// Uses independent authenticated sockets and only each acting seat's legal
// projection. The first deal plays every card; later uncontested contracts
// close a small table-total pool so the run stays bounded and reproducible.
const baseURL = new URL(process.env.PREFERANS_ROOM_WORKER_URL ?? "http://127.0.0.1:8787");
const fixture = JSON.parse(await readFile(new URL("../fixtures/create-game.json", import.meta.url), "utf8"));
const id = (value: any): string => typeof value === "string" ? value : value.rawValue;
const projectionOf = (frame: any): any => frame.message?.projection?._0?.projection;

async function post(path: string, body: unknown, token?: string): Promise<any> {
  const response = await fetch(new URL(path, baseURL), {
    method: "POST", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body), signal: AbortSignal.timeout(5_000)
  });
  assert.ok(response.ok, `${path.split("/").at(-1)}: HTTP ${response.status}`);
  return response.json();
}

function connect(url: string) {
  const socket = new WebSocket(url);
  const frames: any[] = [];
  const listeners = new Set<() => void>();
  socket.addEventListener("message", event => {
    frames.push(JSON.parse(String(event.data)));
    listeners.forEach(listener => listener());
  });
  function wait(predicate: (frame: any) => boolean, after = 0): Promise<any> {
    return new Promise((resolve, reject) => {
      const finish = () => { clearTimeout(timer); listeners.delete(check); };
      const check = () => {
        const value = frames.slice(after).find(predicate);
        if (value) { finish(); resolve(value); }
      };
      const timer = setTimeout(() => { finish(); reject(new Error("No network progress within 3 seconds")); }, 3_000);
      listeners.add(check); check();
    });
  }
  return { socket, frames, wait };
}
type Connection = ReturnType<typeof connect>;

function assertPrivacy(frame: any, viewer: string, sequence: number) {
  const envelope = frame.message.projection._0;
  const projection = projectionOf(frame);
  assert.equal(frame.authority, "server");
  assert.equal(id(envelope.viewer), viewer);
  assert.equal(id(projection.viewer), viewer);
  assert.equal(envelope.sequence, sequence);
  assert.equal(projection.sequence, sequence);
  assert.equal(envelope.state, undefined);
  assert.equal(projection.deck, undefined);
  assert.equal(projection.dealSeed, undefined);
  const terminal = projection.phase.dealFinished || projection.phase.gameOver;
  if (!terminal) {
    for (const seat of projection.seats) {
      for (const card of seat.hand) {
        assert.equal(card.known !== undefined, id(seat.player) === viewer,
          "A closed hand must be visible only to its authenticated owner");
      }
    }
    const declarer = projection.phase.awaitingContract?.declarer
      ?? projection.phase.awaitingWhist?.declarer
      ?? projection.phase.playing?.kind?.game?.declarer;
    for (const card of projection.discard) {
      assert.equal(card.known !== undefined, declarer && id(declarer) === viewer,
        "A discard must remain private until the deal finishes");
    }
    for (const event of envelope.events ?? []) {
      if (event.talonExchanged && id(event.talonExchanged.declarer) !== viewer) {
        assert.deepEqual(event.talonExchanged.discard, []);
        assert.deepEqual(event.talonExchanged.talon, []);
      }
    }
  }
}

function nextAction(projection: any, deal: number): any | undefined {
  const player = projection.viewer;
  const legal = projection.legal;
  if (legal.bidCalls.length) {
    const opening = legal.bidCalls.find((call: any) => call.bid?._0?.game?._0?.tricks === 6);
    const call = projection.phase.bidding.highestBid ? legal.bidCalls.find((call: any) => call.pass) : opening;
    assert.ok(call, "Expected a legal opening six or pass");
    return { bid: { player, call } };
  }
  if (legal.canDiscard) {
    const own = projection.seats.find((seat: any) => id(seat.player) === id(player));
    const cards = own.hand.slice(0, 2).map((card: any) => card.known._0);
    return { discard: { player, cards } };
  }
  if (legal.contractOptions.length) return { declareContract: { player, contract: legal.contractOptions[0] } };
  if (legal.whistCalls.length) {
    const call = legal.whistCalls.find((call: any) => deal === 1 ? call.whist : call.pass);
    assert.ok(call, "Expected the requested legal defense call");
    return { whist: { player, call } };
  }
  if (legal.defenderModes.length) return { chooseDefenderMode: { player, mode: { closed: {} } } };
  if (legal.playableCards.length) return { playCard: { player: legal.playableCardsOwner ?? player, card: legal.playableCards[0] } };
  return undefined;
}

for (const count of [3, 4]) {
  const seats = ["north", "east", "south", "west"].slice(0, count).map(rawValue => ({ rawValue }));
  const accounts: any[] = [], rooms: any[] = [], sockets: Connection[] = [], retired: Connection[] = [];
  const started = performance.now();
  let sequence = 0, deals = 0, cards = 0, manager = 0;
  let completed = false, retried = false, managerRecovered = false;
  try {
    for (const seat of seats) accounts.push(await post("/v2/accounts/guest", { displayName: `Network QA ${seat.rawValue}` }));
    rooms.push(await post("/v2/rooms", {
      localPlayerID: seats[0], maxPlayers: count,
      seats: seats.map((playerID, index) => ({ playerID, kind: index ? "open" : "you" })),
      rules: fixture.rules, match: fixture.match
    }, accounts[0].sessionToken));
    for (let index = 1; index < count; index++) rooms.push(await post(`/v2/rooms/${rooms[0].roomCode}/join`, {
      requestedPlayerID: seats[index]
    }, accounts[index].sessionToken));
    rooms.forEach(room => sockets.push(connect(room.websocketURL)));
    await sockets[0].wait(frame => frame.connectedPlayerIDs?.length === count);

    const packet = (actor: any, action: any, nonce = crypto.randomUUID()) => ({ type: "wire", message: { clientAction: { _0: {
      schemaVersion: ROOM_SCHEMA_VERSION, tableID: rooms[0].authoritativeTableID,
      actor, action, clientNonce: nonce, baseHostSequence: sequence, sentAt: new Date().toISOString()
    } } } });
    const send = async (index: number, command: any, expected: "accepted" | "rejected", after = sockets[index].frames.length) => {
      sockets[index].socket.send(JSON.stringify(command));
      const response = await sockets[index].wait(frame => frame.type === "receipt"
        && frame.receipt.clientNonce === command.message.clientAction._0.clientNonce, after);
      assert.equal(response.receipt.status, expected);
      return response.receipt;
    };
    const rejoin = async (index: number) => {
      retired.push(sockets[index]);
      sockets[index].socket.close();
      rooms[index] = await post(`/v2/rooms/${rooms[0].roomCode}/join`, { requestedPlayerID: seats[index] }, accounts[index].sessionToken);
      sockets[index] = connect(rooms[index].websocketURL);
      const frame = await sockets[index].wait(frame => projectionOf(frame)?.sequence === sequence);
      await sockets[index].wait(frame => frame.connectedPlayerIDs?.length === count);
      return projectionOf(frame);
    };

    for (let step = 0; step < 128; step++) {
      assert.ok(performance.now() - started < 30_000, "Network match exceeded its 30-second bound");
      const frames = await Promise.all(sockets.map(socket => socket.wait(frame => projectionOf(frame)?.sequence === sequence)));
      frames.forEach((frame, index) => assertPrivacy(frame, id(seats[index]), sequence));
      const projections = frames.map(projectionOf);
      if (projections[0].phase.gameOver) {
        const summary = projections[0].phase.gameOver.summary;
        assert.ok(summary.dealsPlayed >= 3 && summary.dealsPlayed <= 4);
        assert.ok(Math.abs(summary.standings.reduce((sum: number, row: any) => sum + row.balance, 0)) < 1e-8);
        for (const projection of projections) assert.deepEqual(projection.phase.gameOver.summary, summary);
        completed = true; break;
      }
      if (projections[0].legal.canStartDeal) {
        deals++;
        const receipt = await send(manager, packet(seats[manager], { startDeal: {} }), "accepted");
        assert.equal(receipt.sequence, ++sequence);
        console.log(`NETWORK seats=${count} deal=${deals} phase=dealt revision=${sequence}`);
        continue;
      }
      const actions = projections.map(projection => nextAction(projection, deals));
      const acting = actions.findIndex(Boolean);
      assert.ok(acting >= 0, `No legal action at revision ${sequence}`);
      const action = actions[acting];
      if (action.playCard && cards >= 3 && !managerRecovered) {
        sockets[0].socket.close();
        const observer = seats.findIndex((_, index) => index !== 0 && index !== acting);
        const presence = await sockets[observer].wait(frame => frame.type === "presence"
          && !frame.connectedPlayerIDs.some((player: any) => id(player) === "north"));
        manager = seats.findIndex(seat => id(seat) === id(presence.room.hostPlayerID));
        assert.notEqual(manager, 0, "Lobby management must migrate after disconnect");
        const rejected = await send(observer, packet(seats[acting], action), "rejected");
        assert.equal(rejected.sequence, sequence, "A different account cannot play another seat's hand");
        const resumed = await rejoin(0);
        assert.deepEqual(resumed.seats[0].hand, projections[0].seats[0].hand);
        managerRecovered = true;
        console.log(`NETWORK seats=${count} phase=manager-recovered revision=${sequence}`);
      }
      const command = packet(seats[acting], action);
      if (action.playCard && !retried) {
        // Observe acceptance from another seat while the sending client drops
        // its receipt. A new connection resubmits the exact pending command.
        sockets[acting].socket.send(JSON.stringify(command));
        await sockets[(acting + 1) % count].wait(frame => projectionOf(frame)?.sequence === sequence + 1);
        sequence++;
        await rejoin(acting);
        const receipt = await send(acting, command, "accepted");
        assert.equal(receipt.sequence, sequence, "A recovered pending command must not apply twice");
        retried = true;
        console.log(`NETWORK seats=${count} phase=pending-replayed revision=${sequence}`);
      } else {
        const receipt = await send(acting, command, "accepted");
        assert.equal(receipt.sequence, ++sequence);
      }
      if (action.playCard) cards++;
    }
    assert.ok(completed, "Match did not finish within 128 commands");
    assert.equal(cards, 30, "The first deal must play all thirty cards through independent clients");
    assert.ok(retried && managerRecovered, "Recovery paths must occur during actual trick play");
    console.log(`NETWORK seats=${count} phase=finished deals=${deals} cards=${cards} revision=${sequence} elapsedMs=${Math.round(performance.now() - started)}`);
  } finally {
    try {
      if (rooms[0] && !completed) await post(`/v2/rooms/${rooms[0].roomCode}/abandon`, {
        playerID: seats[manager], seatToken: rooms[manager].seatToken
      }, accounts[manager].sessionToken);
    } finally {
      [...sockets, ...retired].forEach(({ socket }) => socket.close());
      const cleanup = await Promise.allSettled(accounts.map(async account => {
        const response = await fetch(new URL("/v2/account", baseURL), {
          method: "DELETE", headers: { authorization: `Bearer ${account.sessionToken}` }, signal: AbortSignal.timeout(5_000)
        });
        assert.ok(response.ok, "Temporary QA account cleanup failed");
      }));
      assert.ok(cleanup.every(result => result.status === "fulfilled"), "All temporary accounts must be removed");
    }
  }
}
