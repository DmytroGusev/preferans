import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [cloudflareTest({
    main: "./src/index.ts",
    miniflare: {
      compatibilityDate: "2026-04-07",
      compatibilityFlags: ["nodejs_compat"],
      durableObjects: {
        ROOMS: { className: "PreferansRoomV3", useSQLite: true },
        ACCOUNTS: { className: "PlayerAccountV2", useSQLite: true }
      }
    }
  })],
  test: { include: ["runtime-test/**/*.test.ts"], testTimeout: 10_000 }
});
