# Working notes for AI agents

## Response language

Always respond to the user in English, regardless of the language used in the
user's message, unless the user explicitly requests another language.

## Screenshots must reflect HEAD, never the disk

**Never critique, review, or reason about the UI from screenshots you find
lying on disk.** `build/screens/`, `bin/.screens/`, and any `*.xcresult`
bundle are gitignored local scratch — they can be weeks older than the
source and there is nothing tying them to the current code. Pixels that
predate the `.swift` files they depict are worse than no pixels: they look
authoritative and quietly mislead.

Before looking at any rendered screen:

1. Run `bin/screens-latest`. It prints the freshest run dir, or exits
   non-zero if no run exists (2) or the newest frames are older than any
   `Preferans/**.swift` (3).
2. If it exits non-zero, run `bin/screens` to re-render from current source,
   *then* read the PNGs it writes.

One-liner for scripts/agents:
`dir="$(bin/screens-latest)" || { bin/screens && dir="$(bin/screens-latest)"; }`

## Tight feedback loops during testing

**A 10-minute test timeout is a smell, not a workaround.** If a UI test or
sim run looks like it will take more than ~60–90 seconds, stop and
restructure before re-running:

- Don't pile on `usleep`s or 5-second `waitForExistence` defaults to "make
  it pass" — every wasted second multiplies across iterations and hides
  bugs (a deal-end hang looks identical to "still pacing bots" from the
  outside).
- Surface progress: emit a stdout line per phase / per deal so the loop
  reports what it's actually doing instead of going silent for minutes.
- When a test hangs, first instinct: shrink the case (one deal, fewer
  bots, smaller pool target) until it runs in <30 s, *then* fix the bug.
  Don't bump the test timeout.
- Snapshot/screenshot dumps must dedupe — don't write 200 identical PNGs
  while waiting for a bot animation; key off (phase, viewer, deal#)
  transitions only.
- Bot pacing constants live in `BotPacing` (Sources/PreferansEngine/BotPacing.swift):
  `BotPacing.interactive` (500ms, the production default), `BotPacing.testFast`
  (10ms, gated by the `-uiTestFastBotDelay` launch flag — UI tests only,
  never manual sim), and `BotPacing.instant` (0, the lobby's "Watch bots"
  demo path). Don't inline raw durations elsewhere; reference the constants.
  `testFast` is non-zero on purpose — SwiftUI needs a render cycle between
  consecutive bot moves so transient UI (auction trail, action banner)
  doesn't get re-keyed before it animates.
- If you find yourself reaching for `timeout: 600000` (10 min) on a Bash
  call, that's a sign the underlying loop has no bound. Add the bound
  to the loop, not the wrapper.

Concretely: a full 4-player match to pool=6 with bots in every seat
should complete in well under a minute when animations and bot delay are
disabled. If it doesn't, there's a bug — investigate, don't wait it out.
