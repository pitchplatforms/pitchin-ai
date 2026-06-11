# Agent operational rules — pitchIN workspace

The single rulebook for agents working in this workspace. Read before making changes. Domain vocabulary: [CONTEXT.md](CONTEXT.md). Code navigation: [GRAPHIFY.md](GRAPHIFY.md).

## Workspace map

Issue/PRD hub: **`pitchplatforms/pitchin-issues`** (GitHub — use `gh -R pitchplatforms/pitchin-issues`). Code lands in the three repos below; they integrate only via the API.

| Repo | Path | Base branch | Code gate | Local serve | Port |
|---|---|---|---|---|---|
| API (.NET) | `pitchINAPI/` | `staging_v8` | `dotnet test` (unit projects only — see §Testing gates) | `dotnet run --project Presentation/PitchIn.DigitalRegistry.Api --urls https://localhost:44311` | 44311 |
| Admin (Angular) | `PitchinAdminWeb/` | `staging` | `ng build` | `npm start` | 4201 |
| Customer (Angular) | `PitchinCustomerWeb/` | `staging` | `ng build` | `npm start` (ssl) | 4200 |
| e2e (Playwright) | `pitchinWebTestScripts/` | — | `npm run smoke` / `npm run regression` | — | — |

Both Angular apps' local `environment.ts` expect the API at `https://localhost:44311` — always boot it with `--urls`. (The main API host lives in `Presentation/PitchIn.DigitalRegistry.Api` despite the name.)

## Hard rules

1. **Money/settlement flows** — payments (FPX/DuitNow), invest→confirm→refund→allotment, wallet settlement: **never edit autonomously**. Route the issue `ready-for-human`.
2. **Never close an issue.** Finish by handing off to `needs-human-verify` with what was done and what a human must check.
3. **FE has no unit tests** (`"test": ""` in both Angular apps). `ng build` proves compilation only; the Playwright e2e suite is the only meaningful FE behaviour gate.
4. **Duplicated Angular artifacts** — shared models/enums, `access-token.interceptor.ts`, `ErrorService`/`BlockUiService`/`PopupService` exist in BOTH apps. Fix one ⇒ fix the mirror, or they drift.
5. **God files** — `CampaignService.cs`, `InvestmentService.cs`, Admin `campaign.service.ts`/`digital-registry.service.ts`, Customer `account.service.ts`/`app.component.ts`: smallest possible change; run graphify `affected` first; confirm with the user before structural edits.
6. **Loose FE typing** — many services return `Observable<any>`. Confirm the real DTO shape in the API source before relying on a field.
7. **Never report an AC as covered by a tier that did not run in this run's gates.** Per-PR/periodic tiers (e2e, regression) and human-only tiers don't count toward "green" on an iteration that didn't run them. Device & stochastic ACs (eKYC OCR, Gemini output, real payments) always route to human UAT. For testing/verification/gate-change tasks, consult [docs/testing/qa-plan.md](docs/testing/qa-plan.md) — it is read at triage, not on every iteration.
8. **Never edit `pitchinWebTestScripts/`.** It is the human-authored independent evaluator tier (the oracle). An agent that can rewrite the oracle has no gate. Failing e2e ⇒ fix the app code or hand off `ready-for-human`.

## Testing gates

Exact commands per tier (strategy and blind-spot map live in [docs/testing/qa-plan.md](docs/testing/qa-plan.md), not here):

| Tier | Run | Notes |
|---|---|---|
| API unit | `dotnet test Tests/PitchIn.DigitalRegistry.Api.Test --nologo` then `dotnet test Tests/PitchIn.FileUploadService.Test --nologo` (from `pitchINAPI/`) | **Never bare `dotnet test` at repo root** — `PitchIn.sln` includes the dormant `PitchIn.IntegrationTest.Test` (needs a live Postgres + seeded login + missing `appsettings.Testing.json`); it will fail or hang. Requires the **.NET 10 SDK** (runtime alone is not enough). |
| FE build | `ng build` in `PitchinAdminWeb/` and in `PitchinCustomerWeb/` | Compilation only — both apps have `"test": ""`; there is no FE unit tier. |
| e2e smoke | `npm run smoke` in `pitchinWebTestScripts/` | Targets **UAT** (`utils/urls.ts`), `headless: false` → attended desktop session required. Run conditional on the issue's `needs:e2e` label. |
| e2e full | `npm run regression` in `pitchinWebTestScripts/` | Periodic / pre-release, vs UAT, attended. |

## Tooling

- **Locate/understand code with graphify** — see [GRAPHIFY.md](GRAPHIFY.md) for the per-skill playbook and commands. Read stdout even on non-zero exit (truncation).
- **Refresh the graph only via `.\refresh-graph.ps1`** — never `graphify update`/`extract` directly (parallel extractor crashes on this machine).

## Known gate limitations

- The Playwright suite (`pitchinWebTestScripts/utils/urls.ts`) currently targets **UAT** (`https://uat.pitchin.dev`), not a locally booted stack. Parameterising it for local slice stacks is scheduled in the ralph-loop adaptation.
