import { MutationQueue } from "./command-contract";
import { PUBLIC_TABLE_LEASE_MS, type PublicTableEntry } from "./public-tables";

interface Listing { revision: number; expiresAt: number; table?: PublicTableEntry }

// Directory writes are internal DO calls; clients can only read through the
// authenticated Worker route. A failed publish never undoes a seated move.
export class PublicTableDirectory {
  private mutations = new MutationQueue();
  constructor(private ctx: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    return this.mutations.run(async () => {
      const url = new URL(request.url);
      if (request.method === "POST" && url.pathname === "/publish") {
        const body = await request.json() as { roomCode: string; revision: number; table?: PublicTableEntry };
        const key = `table:${body.roomCode}`;
        const previous = await this.ctx.storage.get<Listing>(key);
        if (!previous || body.revision >= previous.revision) {
          await this.ctx.storage.setAlarm(Date.now() + PUBLIC_TABLE_LEASE_MS);
          await this.ctx.storage.put(key, { revision: body.revision,
            table: body.table, expiresAt: Date.now() + PUBLIC_TABLE_LEASE_MS } satisfies Listing);
        }
        return Response.json({ ok: true });
      }
      if (request.method === "GET" && url.pathname === "/list") {
        const variant = url.searchParams.get("variant");
        const players = url.searchParams.get("players");
        const poolTarget = url.searchParams.get("poolTarget");
        const status = url.searchParams.get("status");
        const rows = await this.ctx.storage.list<Listing>({ prefix: "table:" });
        const eligible = [...rows.values()].filter(row => row.expiresAt > Date.now() && row.table)
          .map(row => row.table!)
          .filter(table => (!variant || table.variant === variant)
            && (!players || table.maxPlayers === Number(players))
            && (!poolTarget || table.poolTarget === Number(poolTarget))
            && (!status || table.status === status));
        eligible.sort((a, b) => (a.status === "lobby" ? 0 : 1) - (b.status === "lobby" ? 0 : 1)
          || a.createdAt.localeCompare(b.createdAt) || a.roomCode.localeCompare(b.roomCode));
        const offset = Math.max(0, Math.min(10_000, Number(url.searchParams.get("offset")) || 0));
        return Response.json({ tables: eligible.slice(offset, offset + 50),
          nextOffset: offset + 50 < eligible.length ? offset + 50 : null });
      }
      return new Response("Not found", { status: 404 });
    });
  }

  async alarm(): Promise<void> {
    await this.mutations.run(async () => {
      const rows = await this.ctx.storage.list<Listing>({ prefix: "table:" });
      const expired = [...rows].filter(([, row]) => row.expiresAt <= Date.now()).map(([key]) => key);
      if (expired.length) await this.ctx.storage.delete(expired);
      if (rows.size > expired.length) await this.ctx.storage.setAlarm(Date.now() + PUBLIC_TABLE_LEASE_MS);
    });
  }
}
