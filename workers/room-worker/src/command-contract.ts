import { type EngineCommandEnvelope } from "./authoritative-engine.ts";
import { RoomStateError } from "./room-state.ts";

export interface CommandReceipt {
  tableID: string;
  clientNonce: string;
  sequence: number;
  status: "accepted" | "rejected";
  code?: string;
  message?: string;
}

export interface StoredCommand {
  command?: EngineCommandEnvelope;
  fingerprint: string;
  receipt: CommandReceipt;
}

// Structural canonicalization makes retries independent of JSON key ordering.
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map(key => `${JSON.stringify(key)}:${canonical(record[key])}`).join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

export async function commandIdentity(sender: string, command: EngineCommandEnvelope): Promise<{
  key: string; fingerprint: string; nonce: string;
}> {
  const nonce = String(command.clientNonce ?? "").toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(nonce)) {
    throw new RoomStateError("invalid_command", "A UUID command ID is required.");
  }
  const bytes = new TextEncoder().encode(canonical({
    sender, tableID: command.tableID, schemaVersion: command.schemaVersion,
    actor: command.actor, action: command.action, baseSequence: command.baseHostSequence
  }));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return {
    key: `command:${sender}:${nonce}`,
    nonce,
    fingerprint: Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("")
  };
}

/** All durable callbacks use this gate, including connection lifecycle and alarms.
 * A failed operation must release the gate without poisoning subsequent work.
 */
export class MutationQueue {
  private tail: Promise<unknown> = Promise.resolve();
  private pending = 0;

  run<T>(operation: () => Promise<T>): Promise<T> {
    if (this.pending >= 64) {
      return Promise.reject(new RoomStateError("room_busy", "The table is busy. Retry shortly.", 503));
    }
    this.pending++;
    const result = this.tail.then(operation);
    this.tail = result.catch(() => undefined).finally(() => { this.pending--; });
    return result;
  }
}
