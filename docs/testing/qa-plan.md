# QA Plan — pitchIN workspace

> Single source of truth for what we test, where, and why. Read this **at triage** (once per issue) before declaring any gate "green" — not on every implementer iteration.
> Maintained by the `plan-qa-test` skill. Executable commands + hard rules: [AGENTS.md](../../AGENTS.md) §Testing gates.

- **Risk band:** B3 — autonomous ralph loop (in build-out) + money flows (ECF/TCF invest→confirm→refund→allotment, wallet) + Postgres/EF migrations + external APIs (FPX/DuitNow, CTOS eKYC OCR, Gemini) + Playwright is the *only* FE behaviour tier.
- **Stack:** .NET 10 API (xUnit + Moq; dormant TestServer integration tier) · Angular ×2 (no unit tests — `"test": ""` — build only) · Playwright e2e in a separate repo (`pitchinWebTestScripts/`) · PostgreSQL via EF Core.
- **Test shape:** inverted trophy (by reality, not choice) — the only behaviour-bearing tiers are thin mocked API units and the UAT-targeting e2e suite. Complexity lives at the seams (API services ↔ Postgres ↔ two FE consumers), so growth goes to integration/contract tiers, **not** more mocked units (mocks co-authored with code share the author's blind spots).
- **AI-loop / evaluator-isolation:** **required.** Implemented as: `pitchinWebTestScripts/` is human-authored and a protected path — agents never edit it (AGENTS.md hard rule 8). It is the independent oracle tier.
- **date_modified:** 2026-06-12

## Tier ladder

| Tier | Command | Catches | Blind to |
|---|---|---|---|
| API unit (xUnit + Moq) | `dotnet test Tests/PitchIn.FileUploadService.Test` ✅ (5/5) · `Tests/PitchIn.DigitalRegistry.Api.Test` ⛔ **QUARANTINED — baseline-red 632/1196** (verified 2026-06-12; see Open gaps #1) | controller wiring/regressions against mocked services; JWT handler smoke | everything real: DB, schema, auth pipeline, serialization, all service-layer logic (services are mocked) |
| API integration (TestServer) | **DORMANT** — in `.sln` but needs a live Postgres, a seeded investor login, and a missing `appsettings.Testing.json`; teardown is commented out | (when revived: schema contracts, authed request path) | not a tier until revived — do **not** count it as coverage |
| FE build ×2 | `ng build` in `PitchinAdminWeb/` and `PitchinCustomerWeb/` | compile/type/template errors | **all** runtime behaviour — there is no FE unit tier |
| e2e (Playwright, 8 journeys) | `npm run smoke` / `npm run regression` in `pitchinWebTestScripts/` | renders-but-broken on real journeys: login, ECF/TCF application + investment, wallet, PSTX trade, admin-login-as-user | **local changes** — `utils/urls.ts` hardcodes `https://uat.pitchin.dev`; also `headless: false` → needs an attended desktop session |
| stochastic external (CTOS eKYC OCR · Gemini image gen) | none | — | everything; routed to human UAT via `needs:ocr` |
| post-deploy smoke | none | — | deploy-only and prod-state failures have no automated home |

## Environment Matrix

Cell values: `RUNS` = executes **and** is enforced as a gate · `LOCAL-ONLY` = runs on demand but gates nothing (a blind spot, not coverage) · `BLOCKED` = structurally cannot gate here · `—` = n/a.
**There is no CI pipeline in any of the four repos** (only a version-bump workflow in CustomerWeb). Until the ralph loop gates land (Bucket 5), the "loop gate" column is the *intended* enforcement point; everything is LOCAL-ONLY today.

| Tier ↓ / Env → | local machine | loop gate (per-iteration) | UAT | prod |
|---|---|---|---|---|
| API unit (FileUploadService) | RUNS (verified green 2026-06-12) | intended RUNS | — | — |
| API unit (Api.Test) | BLOCKED — baseline-red, quarantined until repaired | BLOCKED | — | — |
| API integration | BLOCKED (dormant) | BLOCKED | — | — |
| FE build ×2 | RUNS (on demand) | intended RUNS | — | — |
| e2e Playwright | BLOCKED for local changes (targets UAT only) | BLOCKED until `urls.ts` is parameterised + headless (Bucket 5) | LOCAL-ONLY (manual, attended) | BLOCKED |
| stochastic (OCR / Gemini) | — | — | human UAT only | OBSERVED at best (no monitoring named yet) |
| migrations vs accumulated prod data | BLOCKED (clean/local state ≠ prod state) | BLOCKED | BLOCKED | deploy checklist + post-migration probe |

## Execution boundaries

| Tier | Boundary | Notes |
|---|---|---|
| API unit + FE build ×2 | **per-iteration** (ralph in-loop gate) | cheap + deterministic; the only tiers fast enough |
| matching e2e spec | **per-slice**, conditional on `needs:e2e` label | today: manual run vs UAT; becomes a real gate when `urls.ts` is parameterised against a locally booted stack (Bucket 5) |
| full `npm run regression` | **periodic** (pre-release / weekly) vs UAT | attended (headed browser); retry-passes must be logged, not ignored |
| eKYC OCR · Gemini · real payments | **human UAT only** (`needs:ocr` / `ready-for-human`) | stochastic and/or money — never sign off from any local tier |
| migrations on accumulated prod data | **deploy checklist** | PRODUCTION-ONLY by construction |

> **Triage is the choke-point:** triage reads this plan once per issue, classifies each AC's environment, writes a terse verification note into the issue, and sets `needs:*` labels (`needs:e2e`, `needs:ocr`, `ready-for-human`). The implementer reads only its issue + AGENTS.md hard rule 7.

## AC classification index (by area)

| Area | env-class | deterministic? | tier(s) today | PROD-ONLY signal |
|---|---|---|---|---|
| Campaign browse / content (read paths, both FEs) | DB | yes | API unit + e2e smoke | — |
| Auth & session (login, JWT, token interceptor ×2 apps) | DB | yes | API unit (JWT smoke) + `login.spec` | — |
| Invest→confirm→refund→allotment · wallet (money) | DB + EXTERNAL-API | yes | **agent-blocked** (AGENTS.md hard rule 1); `ecfInvestment`/`tcfInvestment`/`pitchINWallet` specs vs UAT | settlement reconciliation vs payment provider; human sign-off per release |
| eKYC (CTOS, OCR) | EXTERNAL-API | **no** | none → human UAT (`needs:ocr`) | eKYC completion-rate drop after deploy |
| Gemini poster generation (`ImageGenerationController`) | EXTERNAL-API | **no** | none | if ever gated: invariants only (HTTP 200 + image bytes present) — never content match |
| Admin back-office ops | DB | yes | FE build + `adminLoginToUserAcc.spec` | — |
| EF migrations vs accumulated prod data | PRODUCTION-ONLY | yes | none | post-migration probe (e.g. row-count / NULL-count check) + rollback threshold; release checklist item |

## Non-Determinism Log

| Behavior | Tier | Handling | Added |
|---|---|---|---|
| CTOS eKYC OCR extraction varies per document/run | none | human UAT; if ever automated, gate presence/format invariants only, accuracy = N-sample signal | 2026-06-12 |
| Gemini image output varies per call | none | invariants-only if ever gated; output content is never asserted | 2026-06-12 |
| Playwright `retries: 2` masks flake — a retry-pass currently looks identical to a clean pass | e2e | when the suite becomes a loop gate, log retry-passes separately; retry-pass rate >5% on a spec → quarantine candidate | 2026-06-12 |

## Closed-Gaps trail

*(Entries are earned by closing a proven hole — none yet. Bootstrap date: 2026-06-12.)*

## Open gaps (ranked — bootstrap findings, 2026-06-12)

1. **`PitchIn.DigitalRegistry.Api.Test` is baseline-red: 632/1196 fail** (verified 2026-06-12, .NET 10 SDK 10.0.301). Two failure classes: (a) `UsersControllerTests` mocks the **concrete** `ClickUpService` (no parameterless ctor → every test in the class throws in its constructor — fix: extract/mock an interface); (b) `ECFControllerTests` + Admin/SuperAdmin classes hit `NullReferenceException` **inside the controllers** (e.g. `ECFController.cs:1254`) — controllers evolved, mock setups were never maintained, no CI noticed. **Quarantined: must not be a loop gate until repaired** — a baseline-red gate trains the loop to ignore red. Interim API gate = build + `FileUploadService.Test`. *Close: repair both classes; re-baseline green; un-quarantine here and in AGENTS.md.*
2. **`dotnet test` at repo root would run the dormant integration suite** (it's in `PitchIn.sln`) and fail/hang without a DB. *Close: loop gate targets unit projects explicitly (now in AGENTS.md).*
   *(Resolved 2026-06-12: this machine previously had no .NET SDK at all — .NET 10 SDK 10.0.301 now installed; `setup-pitchin` (Bucket 6) must install it for new machines.)*
3. **e2e cannot see local changes** — `urls.ts` hardcodes UAT; `headless: false` blocks unattended runs. A slice can pass every loop gate with a broken UI. *Close: Bucket 5 parameterises `urls.ts` (env var) + headless profile.*
4. **No CI pipeline anywhere** — every tier is LOCAL-ONLY until ralph's in-loop gates exist (Bucket 5) or a pipeline is added. *Close: Bucket 5; longer-term, a per-PR pipeline on the three code repos.*
5. **FE has zero behaviour tier below e2e** — an Angular service logic bug is invisible until a UAT e2e run. *Earn it: first FE logic bug that escapes `ng build` justifies reviving Karma/Jest for the affected service (start with the duplicated services in hard rule 4).*
6. **API integration tier dormant** — revive only when a schema/auth bug escapes the unit tier (earn it; don't re-scaffold speculatively). If revived: real Postgres pinned to the prod engine version, never in-memory substitutes.
7. **No post-deploy smoke** — deploys are verified by humans clicking. *Earn it: first deploy-only failure justifies a synthetic probe per app.*

## Production-outcome tracking

- **Gate-pass rate:** from ralph run logs (`ralph/reviews/`, Bucket 5c) once the loop is live.
- **Production-survival:** count issues in `pitchplatforms/pitchin-issues` whose origin is UAT/prod escape vs agent-shipped slices.
- **Last review:** 2026-06-12 — bootstrap; no loop runs yet. Review after the Bucket 5 dry-run.
