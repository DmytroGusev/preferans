import assert from 'node:assert/strict';
import profiles from '../fixtures/public-rules.json' with { type: 'json' };

const base = process.env.PREFERANS_ROOM_WORKER_URL ?? 'http://127.0.0.1:8787';
assert(['http://127.0.0.1:8787', 'https://preferans-room-worker.dmytro-gusev.workers.dev'].includes(base));
const timeout = base.startsWith('https:') ? 10_000 : 3_000;
const tokens: string[] = [];
const connections: ReturnType<typeof connect>[] = [];
const id = (value: any) => typeof value === 'string' ? value : value.rawValue;
const projection = (frame: any) => frame.message?.projection?._0?.projection;
async function request(method: string, path: string, token?: string, body?: unknown, expected = 200): Promise<any> {
  const response = await fetch(base + path, { method, signal: AbortSignal.timeout(timeout),
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) });
  assert.equal(response.status, expected, `${method} ${path.split('/').at(-1)}: HTTP ${response.status}`);
  return response.status === 204 ? {} : response.json();
}
async function guest(name: string) {
  const account = await request('POST', '/v2/accounts/guest', undefined, { displayName: name }, 201);
  tokens.push(account.sessionToken);
  return account.sessionToken as string;
}
function connect(room: any) {
  const socket = new WebSocket(room.websocketURL);
  const frames: any[] = [];
  const listeners = new Set<() => void>();
  socket.addEventListener('message', event => { frames.push(JSON.parse(String(event.data))); listeners.forEach(fn => fn()); });
  function wait(predicate: (frame: any) => boolean, after = 0): Promise<any> {
    return new Promise((resolve, reject) => {
      const finish = () => { clearTimeout(timer); listeners.delete(check); };
      const check = () => { const result = frames.slice(after).find(predicate); if (result) { finish(); resolve(result); } };
      const timer = setTimeout(() => { finish(); reject(new Error('No bot QA socket progress')); }, timeout);
      listeners.add(check); check();
    });
  }
  const connection = { socket, frames, wait };
  connections.push(connection);
  return connection;
}
const results: any[] = [];
try {
  for (const visibility of ['public', 'private']) for (const count of [3, 4]) {
    console.log(`[bot-network] ${visibility}, ${count} seats: two humans ready, add ${count - 2} bot(s), ready again, start`);
    const startedAt = Date.now();
    const players = ['north', 'east', 'south', 'west'].slice(0, count);
    const host = await guest('Bot seats QA host');
    const friend = await guest('Bot seats QA friend');
    const room = await request('POST', '/v2/rooms', host, {
      visibility, variant: 'odesa', localPlayerID: { rawValue: 'north' }, maxPlayers: count,
      seats: players.map((rawValue, index) => ({ playerID: { rawValue }, kind: index ? 'open' : 'you' })),
      rules: profiles.odesa, match: { poolTarget: count * 11 }
    });
    const hostSocket = connect(room);
    await hostSocket.wait(frame => frame.type === 'room');
    const joined = await request('POST', `/v2/rooms/${room.roomCode}/join`, friend, { requestedPlayerID: { rawValue: 'east' } });
    const friendSocket = connect(joined);
    await friendSocket.wait(frame => frame.type === 'room');
    const ready = async () => {
      if (visibility !== 'public') return;
      for (const [token, seat, seatRoom] of [[host, 'north', room], [friend, 'east', joined]] as const) {
        await request('POST', `/v2/rooms/${room.roomCode}/ready`, token, { playerID: seat, seatToken: seatRoom.seatToken, ready: true });
      }
    };
    await ready();
    const edit = (targetPlayerID: string, difficulty: string, token = host, actor = 'north', seatToken = room.seatToken, expected = 200) =>
      request('POST', `/v2/rooms/${room.roomCode}/seats/bot`, token, { playerID: actor, seatToken, targetPlayerID, difficulty }, expected);
    await edit('south', 'expert', friend, 'east', joined.seatToken, 403);
    await edit('east', 'expert', host, 'north', room.seatToken, 409);
    for (const [index, seat] of players.slice(2).entries()) {
      const difficulty = index === 0 ? 'casual' : 'expert';
      const edited = await edit(seat, difficulty);
      const peer = edited.peers.find((peer: any) => id(peer.playerID) === seat);
      assert.equal(peer.botDifficulty, difficulty);
      assert.equal(peer.accountID, `bot:${seat}`);
      if (visibility === 'public') assert.deepEqual(edited.readyPlayerIDs, []);
    }
    await ready();
    const nonce = crypto.randomUUID();
    const after = hostSocket.frames.length;
    hostSocket.socket.send(JSON.stringify({ type: 'wire', message: { clientAction: { _0: {
      schemaVersion: 4, tableID: room.authoritativeTableID, actor: { rawValue: 'north' }, clientNonce: nonce,
      baseHostSequence: 0, action: { startDeal: {} }
    } } } }));
    const receipt = await hostSocket.wait(frame => frame.type === 'receipt' && frame.receipt.clientNonce === nonce, after);
    assert.equal(receipt.receipt.status, 'accepted');
    for (const [socket, viewer] of [[hostSocket, 'north'], [friendSocket, 'east']] as const) {
      const frame = await socket.wait(frame => projection(frame)?.sequence >= 1);
      const view = projection(frame);
      assert.equal(id(view.viewer), viewer);
      for (const seat of view.seats) {
        assert(seat.hand.every((card: any) => (card.known !== undefined) === (id(seat.player) === viewer)), 'Private hand leaked');
      }
    }
    await edit('south', 'seasoned', host, 'north', room.seatToken, 409);
    results.push({ visibility, seats: count, humans: 2, bots: count - 2, readyBeforeAndAfterBot: visibility === 'public', protectedHumanSeat: true, privateProjections: true, firstDealAccepted: true, elapsedMs: Date.now() - startedAt });
    console.log(`[bot-network] passed ${visibility}/${count}`);
  }
} finally {
  connections.forEach(connection => connection.socket.close());
  const cleanup = await Promise.allSettled(tokens.map(token => request('DELETE', '/v2/account', token, undefined, 204)));
  assert(cleanup.every(item => item.status === 'fulfilled'), 'QA account cleanup failed');
}
console.log(JSON.stringify({ base, cases: results, temporaryAccountsDeleted: tokens.length, realPlayerDataModified: false }, null, 2));
