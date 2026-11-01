# Preferans 1.0.3 localized keywords

Applied and verified on 1 November 2026 (Europe/Lisbon).

- App: `6763581975`; draft version: `708305c7-7af1-42fb-9614-df78e0743cb5`.
- English US was read live as the owner's reference, including `pref` and `tick`.
  It was preserved exactly, including its trailing comma: 99 characters.
- All other 23 existing locales now use exactly 100 Unicode characters each.
  Terms remain complete; commas have no surrounding spaces or empty entries.
- Both owner-selected source terms are retained. Other terms describe the actual
  game: multiplayer, tricks, whisting, misere, no trump, bidding, talon, pool,
  offline play and named scoring profiles, localized as appropriate.
- Candidate filtering avoids literal title/subtitle word duplication, including
  accent-insensitive comparisons. No competitors, prices or unsupported features
  were added. This is editorial localization, not search-volume research or a
  guarantee of rankings/conversion.
- Apple accepted every value; `after.json` and `verification.json` record readback.
- No descriptions, names, subtitles, screenshots, URLs, promotional text or
  What's New fields were changed. Verification found no unrelated field changes.
- Build 29 remains selected, and the draft remains `PREPARE_FOR_SUBMISSION`.
  No build was uploaded and no review was submitted in this operation.

## Files

`before.json` and `app-info-before.json` preserve the live inputs. `candidates.json`
is the reviewed terminology pool. `generate.mjs` selects whole terms within the
100-character budget, prioritizing earlier candidates among equal-length plans.
`plan.json` contains the exact per-locale old/new strings, IDs, character counts
and UTF-8 byte counts. `after.json` and `verification.json` are the final evidence.

## Reproduce Or Restore

Run from the repository root:

```sh
node AppStore/Keywords-1.0.3/generate.mjs
node AppStore/Keywords-1.0.3/sync.mjs
# With ASC_KEY_PATH pointing to the private key outside the repository:
node AppStore/Keywords-1.0.3/sync.mjs --apply
# Restore only these keyword fields, provided they have not been edited since:
node AppStore/Keywords-1.0.3/sync.mjs --rollback
```

The sync script never patches English US or non-keyword attributes. It checks
the draft state, build selection and concurrent keyword edits before applying;
backs up progress; verifies readback; and does not attempt to undo other changes.
Credentials and signing material must remain outside the repository.

Apple's [search guidance](https://developer.apple.com/app-store/search/) describes
the 100-character keyword budget, comma formatting and relevant-term guidelines.
