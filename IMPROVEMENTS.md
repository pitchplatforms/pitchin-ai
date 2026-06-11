# pitchIN — Architecture Deepening Opportunities

> Specific, file-level places to improve the codebase, ranked by impact. Each was found by exploring for **shallow** modules (interface nearly as complex as the implementation) and confirmed with the **deletion test**: *if you deleted this module, would complexity vanish (pass-through) or reappear scattered across callers (it was earning its keep but tangled)?*
>
> Vocabulary: **module** = interface + implementation · **deep** = lots of behaviour behind a small interface · **seam** = where an interface lives · **locality** = change/bugs/knowledge concentrated in one place · **leverage** = what callers gain. The interface is the test surface.
>
> Companion to `ARCHITECTURE.md`. Source: structural code graph + read-only review of all three repos (June 2026).

---

## Priority 1 — `CampaignService` god module (Backend) · CRITICAL
**Files:** `pitchINAPI/Modules/PitchIn.Campaign/Services/CampaignService.cs` (~8,800 lines), `ICampaignService.cs` (~233 lines), ~24 injected dependencies.

**Problem.** Shallow: a 233-line interface barely constrains an 8,800-line implementation tangling six concerns — campaign lifecycle, shareholder management, financial reporting (NPOI/Excel), document/attachment coordination, notification orchestration, and external integrations (Slack, ClickUp, PostHog). No seam between them.

**Blocks AI.** An AI must load the entire ~8,800-line file into context to change anything — high token cost, and every edit has a large, unverifiable blast radius.

**Deletion test.** Fails — flattening it scatters ~50 methods across 8+ call sites with duplication. It earns its keep but is tangled.

**Fix (deepen).** Split into deep sub-modules behind a thin coordinator: `CampaignLifecycle` (state transitions/cooling/finalization), `CampaignShareholderManagement`, `CampaignFinancialReporting`, `CampaignExternalNotifications`. `CampaignService` becomes a thin orchestrator.

**Payoff.** Locality: each workflow lives in one place. Leverage: callers delegate instead of re-assembling. Testability: lifecycle tested without mocking 20 dependencies; test surface shrinks ~70%. Touches 40+ endpoints.

---

## Priority 2 — "Make an investment" flow has no owner (Backend) · HIGH
**Files:** `Modules/PitchIn.Investment/Services/InvestmentService.cs` (~7,400 lines), `Modules/PitchIn.RaiseFund/Services/RaiseFundService.cs`, `Modules/PitchIn.Campaign/Services/CampaignService.cs`.

**Problem.** The investment intake workflow (fund application → campaign → investment → share allotment) is smeared across three large services that call into each other. Callers (controllers, schedulers) re-sequence the steps and duplicate validation. There is no deep module that *owns* the flow — sequencing/state bugs hide in the gaps.

**Blocks AI.** No single place encodes the workflow, so an AI must infer the step order across three large files — it readily introduces ordering bugs it cannot detect.

**Deletion test.** Can't delete any one service, but extracting the shared workflow removes ~15% of each service's surface.

**Fix (deepen).** Introduce an `InvestmentIntakeOrchestrator` with one entry point (`InitiateInvestmentFlow(...)`) that owns the sequence and transactional safety; reduce the cross-service links to read-only queries.

**Payoff.** Locality: the flow lives in one place. Leverage: controllers drop from multi-step logic to one call. Testability: the whole flow is testable in isolation. Affects payment, confirmation, and share-allotment correctness.

---

## Priority 3 — Admin god services (Admin Web) · HIGH
**Files:** `PitchinAdminWeb/src/app/core/services/api/campaign.service.ts` (~1,084 lines), `digital-registry.service.ts` (~627 lines), `market.service.ts`.

**Problem.** Same shallow-module pattern on the frontend. `campaign.service.ts` bundles ~9 responsibilities (lifecycle, shareholders, investment/eligibility, events/news, fees, share allotment, whitelist, registry sync, reporting) — including ~180 lines of report-transformation logic inside one method. `digital-registry.service.ts` tangles registry structure, shareholder CRUD, and the bulk-import state machine.

**Blocks AI.** Any small feature edit forces an AI to ingest a 600–1,000-line file; it cannot isolate the change or reason about it cheaply.

**Deletion test.** Fails — deleting forces the tangled concerns to inline across 8+ feature components.

**Fix (deepen).** Split by domain concept (e.g. `CampaignCore`, `CampaignEvent`, `CampaignShareAllotment`, `CampaignWhitelist`, `CampaignReporting`; and `DigitalRegistryStructure`, `DigitalRegistryShareholder`, `DigitalRegistryImport`). Optionally a thin facade for backward-compatibility.

**Payoff.** Locality: ~150-line focused modules. Leverage: reusable across features. Testability: 1–2 mocks per spec instead of 9.

---

## Priority 4 — Customer god/orchestration modules (Customer Web) · HIGH
**Files:** `PitchinCustomerWeb/src/app/core/services/api/account.service.ts` (~752 lines), `src/app/app.component.ts` (~590 lines, ~20 injected dependencies).

**Problem.** `AccountService` mixes auth (login/logout/OAuth/refresh), session state (`currentUser`, `notifications` BehaviorSubjects), signup/profile mutations, user-data queries, and direct storage side-effects — a shallow module with many hidden seams. `AppComponent` smears page-specific logic (campaign tracking, chatbot polling, analytics/GTM, push notifications) into the root component.

**Blocks AI.** This is global identity/bootstrap state; an AI editing it risks breaking the whole app, and with the frontend test runner disabled it has no way to self-verify the change.

**Deletion test.** Fails — removing the `currentUser` subject breaks lazy login checks across the app; page logic in `AppComponent` is entangled with bootstrap.

**Fix (deepen).** Split `AccountService` into `SessionManager` (token lifecycle), `CurrentUserService` (identity state behind a small interface), `UserProfileService` (data). Move `AppComponent`'s page logic into an `AppBootstrap` module + feature resolvers; target ~4 dependencies.

**Payoff.** Locality: one module each for "am I logged in / who am I / my data." Testability: mock interfaces instead of HTTP + BehaviorSubjects. AI-navigability: root component becomes readable.

---

## Priority 5 — Duplication across the two web apps → shared library · HIGH
**Files (duplicated in BOTH apps):** `core/models/account/login-profile.ts`, `core/enum/role*.enum.ts`, `shared/http-interceptors/access-token.interceptor.ts`, domain models (`Campaign`, `Attachment`, `PagedResult`), and shared services (`ErrorService`, `BlockUiService`, `PopupService`) — ~500 lines of near-identical code.

**Problem.** Two independent implementations of the same auth/domain/UI layer. A change (e.g. JWT/`{role}` substitution) must be made twice and can drift. This is a missing deep module shared across two callers — and **two adapters = a real seam**, not a hypothetical one.

**Blocks AI.** An AI must apply each change twice and keep both apps in sync — it will routinely fix one app and silently miss the other, causing drift.

**Deletion test.** Deleting either app's copies breaks compilation — proof the concepts are real and shared, just not abstracted.

**Fix (deepen).** Extract a shared `@pitchin/core` library: `auth/` (login profile, interceptor, auth interface), `domain/` (shared models + enums), `ui/` (the shared services). Each app consumes it as an adapter.

**Payoff.** Locality: one source of truth. Leverage: fix once, both apps inherit it. Testability: shared test doubles; ~40% less duplicated code. **Directly enabled by Priority 6 / Step 1.**

---

## Priority 6 — Untyped API calls (Customer Web) · MEDIUM (high AI-navigability win)
**Files:** ~118 `Observable<any>` instances across Customer API services (e.g. `investment.service.ts`, `payment.service.ts`); ~15+ in Admin.

**Problem.** A shallow interface: the service doesn't express the shape it returns, so callers guess or cast. Changing a backend response compiles cleanly but breaks at runtime.

**Blocks AI.** With no response type to follow, an AI guesses payload shapes and cannot be type-checked — the leading cause of plausible-but-wrong AI edits in this codebase.

**Deletion test.** Tightening a return type produces zero compile errors today (callers accept `any`) — proof the contract is missing, not enforced.

**Fix (deepen).** Replace with typed response models + typed service interfaces. **Best delivered by generating typed clients from the backend's OpenAPI/Swagger spec** — this is exactly the proposed Step 1, and it also unlocks Priority 5.

**Payoff.** Testability: fully typed mocks. AI-navigability: IDE/AI can follow types to definitions. Refactoring safety: TypeScript catches all affected call sites.

---

## Priority 7 — MySec module sprawl (Backend) · MEDIUM-HIGH
**Files:** ~14 `PitchIn.MySec.*` modules (Order, Wallet, OrderWallet, OrderQueue, OrderSettings, ShareMarket, MarketAnnouncement, MarketSurveillance, Company, Document, DirectShareOrder, DR, …). `MySecOrderService` injects ~10+ of them.

**Problem.** One external integration (Securities Commission registry) fragmented into many thin modules (2–5 methods each). Most are pass-throughs only `MySecOrderService` consumes.

**Blocks AI.** An AI must read and stitch together 14 modules to make one integration change — high navigation cost, and easy to miss a piece.

**Deletion test.** Delete a thin module → its logic reappears in `MySecOrderService`. They don't earn their keep as separate modules.

**Fix (deepen).** Merge behind a single deep `MySecIntegrationGateway` facade (`EnqueueOrder`, `GetMarketData`, `SyncCompanyRegistry`, `QueryWalletBalance`, `PublishAnnouncement`); keep internals private. Controllers inject one gateway.

**Payoff.** Locality: contract changes touch one gateway. Leverage: `MySecOrderService` constructor drops from ~14 dependencies to 1. Testability: mock one interface.

---

## Sequencing note
Priorities **6 → 5** are unlocked by the proposed **Step 1 (shared API contract from the backend OpenAPI spec)**. The backend god-module splits (**1, 2, 7**) and frontend splits (**3, 4**) are independent refactors that each need a test safety net first (frontend test runners are currently disabled) — so restoring tests is a prerequisite for safely doing 1–4.
