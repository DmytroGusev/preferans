// Local development only. Production wrangler.toml never imports this module.
import { PreferansTable } from "./index";
import type { AuthoritativeEngineBinding } from "./authoritative-engine";
export { default, PlayerAccountV2 } from "./index";

export class LocalPreferansTable extends PreferansTable {
  protected engine(): AuthoritativeEngineBinding {
    return { fetch: (path, body) => fetch(`http://127.0.0.1:18081${path}`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout(8_000)
    }) };
  }
}
