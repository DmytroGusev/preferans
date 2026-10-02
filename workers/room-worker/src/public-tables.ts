import profiles from "../fixtures/public-rules.json" with { type: "json" };
import { PENDING_ACCOUNT_PREFIX, RoomStateError, isHumanAccount, peerID, type RoomState } from "./room-state.ts";

export const PUBLIC_TABLE_LEASE_MS = 90_000;
export const PUBLIC_VARIANTS = ["odesa", "wien", "thessaloniki"] as const;
export type PublicVariant = typeof PUBLIC_VARIANTS[number];

// Only this deliberately small projection is stored in the public directory.
export interface PublicTableEntry {
  roomCode: string;
  variant: PublicVariant;
  poolTarget: number;
  poolClosure: "individualWithAmericanAid" | "tableTotal";
  maxPlayers: number;
  players: { displayName: string; ready: boolean; connected: boolean }[];
  openSeats: number;
  status: "lobby" | "playing";
  dealNumber?: number;
  createdAt: string;
}

export function publicConfiguration(variant: unknown, poolTarget: unknown, playerCount: number) {
  if (!PUBLIC_VARIANTS.includes(variant as PublicVariant)) {
    throw new RoomStateError("invalid_public_variant", "Choose Vienna, Prague, or Berlin.");
  }
  const selected = variant as PublicVariant;
  if (!Number.isSafeInteger(poolTarget) || Number(poolTarget) < 1 || Number(poolTarget) > playerCount * 999) {
    throw new RoomStateError("invalid_pool_target", "Choose a bounded pool target.");
  }
  if (selected !== "wien" && Number(poolTarget) % playerCount !== 0) {
    throw new RoomStateError("invalid_pool_target", "The pool target must divide evenly across players.");
  }
  return {
    variant: selected,
    rules: profiles[selected],
    match: {
      poolTarget: Number(poolTarget),
      poolClosure: selected === "wien" ? "tableTotal" : "individualWithAmericanAid",
      raspasy: { progressive: {
        penalties: selected === "thessaloniki" ? "flat" : "arithmetic",
        exit: selected === "thessaloniki" ? "simple" : "strict"
      } },
      totus: { asTenTrickGame: { requireWhist: false } }
    }
  };
}

export function publicTableEntry(room: RoomState, connected: ReadonlySet<string>): PublicTableEntry | undefined {
  if (room.visibility !== "public" || (room.status !== "lobby" && room.status !== "playing")) return;
  const humans = room.peers.filter(peer => isHumanAccount(peer.accountID));
  // Empty/disconnected waiting rooms must not advertise seats that nobody hosts.
  if (!humans.some(peer => connected.has(peerID(peer)))) return;
  const match = room.engineConfiguration?.match as { poolTarget: number; poolClosure: PublicTableEntry["poolClosure"] };
  const variant = room.engineConfiguration?.variant as PublicVariant;
  if (!match || !PUBLIC_VARIANTS.includes(variant)) return;
  return {
    roomCode: room.roomCode, variant, poolTarget: match.poolTarget, poolClosure: match.poolClosure,
    maxPlayers: room.maxPlayers,
    players: humans.map(peer => ({ displayName: peer.displayName,
      ready: (room.readyPlayerIDs ?? []).includes(peerID(peer)), connected: connected.has(peerID(peer)) })),
    openSeats: room.status === "lobby" ? room.peers.filter(peer => peer.accountID.startsWith(PENDING_ACCOUNT_PREFIX)).length : 0,
    status: room.status, dealNumber: room.summary?.dealNumber, createdAt: room.createdAt
  };
}

export function setPlayerReady(room: RoomState, playerID: string, ready: boolean): RoomState {
  if (room.visibility !== "public" || room.status !== "lobby") {
    throw new RoomStateError("readiness_unavailable", "Readiness can only change at a waiting public table.", 409);
  }
  const players = new Set(room.readyPlayerIDs ?? []);
  if (ready) players.add(playerID); else players.delete(playerID);
  return { ...room, readyPlayerIDs: [...players], updatedAt: new Date().toISOString() };
}
