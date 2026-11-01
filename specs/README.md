# Preferans — Specifications

This folder describes **how the Preferans app actually works**: its rules, scoring, bots, online backend, iOS app, tests and release process. It follows the [GitHub spec-kit](https://github.com/github/spec-kit) layout. Every document was reverse-engineered on 2026-11-01 from the code at `store/1.0.3-localized-keywords` @ `cd78828` and is marked **Implemented (as-built)**. Where code, tests and older docs disagree, the specs describe the **code** and record the disagreement under *Known Gaps & Open Questions*.

## Start here

1. [`000-system-overview/spec.md`](000-system-overview/spec.md): what the product does, who uses it, and a map of all capabilities.
2. [`000-system-overview/plan.md`](000-system-overview/plan.md): architecture, components, technology stack and end-to-end flows.
3. [`000-system-overview/quickstart.md`](000-system-overview/quickstart.md): from `git clone` to green tests and a running app.
4. [`../.specify/memory/constitution.md`](../.specify/memory/constitution.md): the engineering principles every change must respect.

## Feature specs

| # | Area | Read it when you need to… | Files |
|---|---|---|---|
| 000 | [System overview](000-system-overview/) | get the big picture | spec · plan · quickstart · glossary |
| 001 | [Game rules engine](001-game-rules/) | know exactly how a deal flows: dealing, auction, talon, whist, trick play, all-pass, claims, invariants | spec · data-model · research |
| 002 | [Scoring & rule variants](002-scoring-and-variants/) | compute a score sheet: pool, mountain, whists, Sochi/Leningrad/Rostov/Stalingrad, pool closing, final balances | spec · data-model · research |
| 003 | [Bots](003-bots/) | understand or tune the computer players | spec · plan |
| 004 | [Online multiplayer](004-online-multiplayer/) | work on rooms, accounts, the Cloudflare worker, the Swift engine server, the wire protocol or projections | spec · plan · data-model · research · quickstart · [contracts/](004-online-multiplayer/contracts/) |
| 005 | [iOS app](005-ios-app/) | change screens, view models, the table layout, themes, localization or settings | spec · plan · data-model · quickstart |
| 006 | [Testing & release](006-testing-and-release/) | run or write tests, use `bin/` tooling, understand CI, ship a build | spec · plan · research · quickstart |

## How the files are organised (spec-kit roles)

| File | Answers | Notes |
|---|---|---|
| `spec.md` | **What** the system does and **why** | User stories with Given/When/Then acceptance scenarios, numbered functional requirements (`FR-xxx`) with source and test references, success criteria (`SC-xxx`), known gaps |
| `plan.md` | **How** it is built | Technical context, annotated source tree, architecture diagrams (mermaid), key flows |
| `data-model.md` | **What the data looks like** | Types, fields, invariants, state machines, serialized formats |
| `contracts/` | **External interfaces** | HTTP endpoints, realtime messages, wire formats, persistence schemas |
| `research.md` | **Why it was built this way** | Decision / Rationale / Alternatives, reconstructed from code and git history (inferred rationale is labelled) |
| `quickstart.md` | **How to run and verify it** | Exact commands from the repository |

`tasks.md` is deliberately absent. In spec-kit it plans *future* work, while these documents describe what already exists. When you start a new feature, add a new folder `specs/007-<name>/` with `spec.md`, then `plan.md` and `tasks.md`, in the usual spec-kit flow.

## Conventions

- **References** are repo-relative paths plus a type or function name (for example `Sources/PreferansEngine/ScoringEngine.swift` · `ScoringEngine.settle`). Line numbers are avoided because they drift.
- **`[NEEDS CLARIFICATION: …]`** marks behaviour whose intent could not be determined from the code. These are questions for the maintainers, not facts.
- **Names**: the app shows rule variants under display names that differ from their stored IDs and the classical names. See the [glossary](000-system-overview/glossary.md#rule-variants).
- **Keeping specs current**: a change to rules, scoring, wire protocol, projections or user-visible flows updates the matching spec in the same PR (constitution, Development Workflow §3).
