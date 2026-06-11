# How to use graphify in this workspace

This folder (`ai/`) contains three pitchIN codebases — `pitchINAPI` (.NET), `PitchinAdminWeb` and `PitchinCustomerWeb` (Angular). A **graphify knowledge graph** of all three already exists. **Query it to locate and understand code instead of grepping or reading files broadly** — it's cheaper (token-bounded) and every result cites `source_file:line`.

## The one rule

When you need to find where something lives, what calls/depends on something, or how a feature is wired across these projects — **ask the graph first**, then open only the files it cites.

## The graph

- Location: `graphify-out/graph.json` (relative to this `ai/` folder — run commands from here).
- Covers all 3 projects; node IDs are namespaced by repo (`pitchINAPI::…`, `PitchinAdminWeb::…`, `PitchinCustomerWeb::…`). The three apps share no code, so there are no cross-repo edges.
- **Structural only** (AST): files, classes, references, inheritance, containment. It does **not** capture runtime behaviour. Treat results as strong pointers, then confirm in the cited source.
- Excluded on purpose: third-party libraries, build output, tests, and JSON/config.

## Running it (Windows — the CLI is NOT on PATH)

graphify must be run through the recorded Python 3.12 interpreter. Use whichever shell you're in:

**PowerShell:**
```powershell
$py = Get-Content graphify-out\.graphify_python
& $py -m graphify query "How is an investment confirmed?" --graph graphify-out\graph.json --budget 1200
```

**Bash:** same command, forward slashes — `"$(cat graphify-out/.graphify_python)" -m graphify query "..." --graph graphify-out/graph.json --budget 1200`

(Interpreter path: `C:\Users\pitchIN-TP-09\AppData\Local\Programs\Python\Python312\python.exe`. Always pass `--graph graphify-out/graph.json`.)

## Commands

| Command | Use it to… | Example |
|---|---|---|
| `query "<question>"` | Find the files/symbols relevant to a question (breadth-first). **Start here.** | `query "where are campaign refunds handled?" --budget 1200` |
| `query "<q>" --dfs` | Trace one specific chain rather than breadth. | `query "what does InvestmentService depend on?" --dfs` |
| `explain "<Symbol>"` | Get one class/function/file + the methods and things it connects to. | `explain "InvestmentService"` |
| `affected "<Symbol>"` | Reverse impact — what breaks if this changes. | `affected "Attachment" --depth 2` |
| `path "<A>" "<B>"` | Shortest connection between two symbols (same repo only). | `path "CampaignComponent" "CampaignService"` |

All accept `--graph graphify-out/graph.json`. `query` accepts `--budget N` (cap the answer's token size; start 800–1500, raise if too thin).

## Reading the output

`query` returns lines like:
```
NODE InvestmentService [src=pitchINAPI/Modules/PitchIn.Investment/Services/InvestmentService.cs loc=L74 community=10]
```
→ open `pitchINAPI/Modules/PitchIn.Investment/Services/InvestmentService.cs` around line 74. The `src=` path tells you which of the three projects it's in.

## Per-skill playbook — when a skill says "explore the codebase," do this instead

Each workflow skill has a generic "explore the repo" step — replace broad grep/read with the query below, then open only the cited files. (Graph is structural only: confirm specifics in source. Your own un-committed edits are NOT in the graph yet.)

| Skill / stage | Why query — what to learn | Commands | How to use the result |
|---|---|---|---|
| **grill-with-docs** | Go **broad first** — understand the area as fully as possible *before* you ask questions, so you grill from real context, not assumptions. | Skim `GRAPH_REPORT.md` (god nodes + module/community list); `query "<feature area>"` with a wider `--budget`; `explain "<hub service>"` on the central pieces | Enter the grilling already knowing the real modules, names, boundaries & weak spots in play — let that drive sharper questions. Cite `src=file:line`; correct wrong terms to the real symbol name. |
| **to-prd** | Ground module boundaries in real structure; surface risk. | `query "<area>"`; `affected "<core symbol>"` | Draw boundaries from cited files; seed the PRD's Risks section from any weak spot you touch. |
| **to-issues** | Make each slice a **vertical, end-to-end path** (entry → service → data) so it's independently verifiable — NOT a horizontal layer. | `path "<entry/UI>" "<data/service>"` to trace the vertical; `query` for the full set of files one behaviour touches | Each issue's "Relevant files" block should span the vertical (entry→service→data) so the slice can be verified end-to-end. If a slice sits in one layer only, it's horizontal — re-slice. Flag slices hitting a weak spot. |
| **triage** | Risk-tag & route. | `affected "<symbol>"`; `query` | Fill the Agent Brief's "Key interfaces" from cited symbols; add a "Risk flags" line (god file / money flow / FE-no-tests → needs:human). |
| **plan-qa-test** — codebase mode (setup + periodic) | Map the whole codebase's risk surface — money flows, god files, untested layers — to author or holistically review `docs/testing/qa-plan.md`. | Skim `GRAPH_REPORT.md` for the module map; `query "payment/settlement flows"`; `query "investment/allotment"`; `affected "<god file>"` for blast radius of each weak spot | Fill the Environment Matrix rows from cited file layers (money path → human UAT; FE-only → Playwright; DB-touching → HERMETIC/DB tier). Write hard rules into `AGENTS.md`. Re-run when a bug escapes a tier it shouldn't have. |
| **plan-qa-test** — triage mode (per-board run, triggered by triage) | Check the existing qa-plan against the current issues on the board — surface anything new the scope of work introduces that isn't yet covered in the plan. | `query "<issue area>"` per issue in scope; `affected "<symbol>"` for each key change | Compare what the issues touch against the Environment Matrix tiers. Flag any new patterns or risk paths not yet in the plan. Feed the tier classification + risk flags directly into triage's Agent Brief (`needs:e2e` / `needs:ocr` labels + Key interfaces). |
| **tdd / ralph-loop** | Locate → understand → blast-radius around an edit. | `query` to locate; `explain` before editing; `affected` after | Refresh the graph at issue *start* (`.\refresh-graph.ps1`). Obey weak-spot warnings. Re-check `affected` once you know the symbol you're changing. |
| **check-human-verify** (`needs-human-verify` handoff) | Confirm each AC was actually exercised, and catch unintended ripple, before a human closes. | `affected "<changed symbol>"`; `explain` to confirm the change sits where the AC requires | Build the human checklist from the cited dependents (what to verify manually: device / prod / real-data). Cross-reference `docs/testing/qa-plan.md` Execution Boundaries to classify each AC — don't reinvent the tiers. Flag any affected area **outside** the issue's scope. Graph shows code reach, not behaviour — still run gates / UAT. |
| **QA / code-review / verify** | Derive the regression surface — *where* to test. | `affected "<changed symbol>"` | Test along the cited dependents. Graphify shows WHERE behaviour can break, not WHETHER it passes — still run/verify. |

## Known weak spots — confirm with the user before editing these

High blast radius, tangled, or untestable. If a task would change any of these, pause, name what you're touching and why it's risky, and prefer the smallest change. **Why + fixes: [IMPROVEMENTS.md](IMPROVEMENTS.md).**

- **No FE tests** — both Angular apps have `"test": ""`; you can't self-verify a frontend change. (`pitchINAPI` has integration tests — use them.)
- **Money / settlement flows** — payments (DuitNow/FPX), invest→confirm→refund→allotment: always confirm first.
- **God files** — `CampaignService.cs` (~8.8k loc, 40+ endpoints); `InvestmentService.cs` (~7.4k loc; invest→allotment flow also spans `RaiseFundService.cs` + `CampaignService.cs`); Admin `campaign.service.ts` / `digital-registry.service.ts`; Customer `account.service.ts` / `app.component.ts`.
- **Duplicated across both Angular apps** — shared models/enums, `access-token.interceptor.ts`, `ErrorService`/`BlockUiService`/`PopupService`: fix one → fix the other or they drift.
- **Loosely-typed API layer** — ~118 `Observable<any>` in Customer (~15 in Admin); confirm the real response shape in source/DTO first.
- **MySec integration** — split across ~14 `PitchIn.MySec.*` modules; run `affected` first.

## Gotchas

- **Ambiguous names.** Some names exist in all three apps (e.g. `CampaignService`, `Campaign`, `Attachment`). `explain`/`path` may resolve to just one — check the `src=` repo prefix, or narrow your `query` wording (e.g. "Admin campaign service").
- **Noisy answers** on highly-connected hubs (god files) — lower `--budget` or use `explain` on a specific symbol instead of a broad `query`.
- **One graph, three apps.** This graph is the merged view. If you only care about one project, just filter results by the `src=` prefix.
- **Non-zero exit on truncation.** When a `query` answer is trimmed to fit `--budget`, the CLI may exit with a non-zero status even though the printed output is valid. **Read stdout regardless of the exit code** — don't treat a truncated query as an error.

## Keeping the graph fresh

The graph reflects the code **as of its last build**; after code changes it drifts. Refresh with the helper script in this folder — it handles the Windows quirk for you:

```powershell
.\refresh-graph.ps1          # re-extract (cached, fast) → rebuild → regenerate the HTML map
.\refresh-graph.ps1 -NoViz   # skip the HTML map (a bit faster)
```

> **Do NOT use `graphify update` / `graphify extract` directly on this machine** — the parallel extractor crashes here. The script runs the sequential (`parallel=False`) path, which is why it's the supported way to refresh.

**When to refresh (specific conditions — not every run):**
- **After you edit code** in any of the 3 projects — run it at the **end of the task** so the next session's queries reflect your changes. (Query-only sessions don't need it.)
- **When a result looks stale** — if a `query`/`explain` answer contradicts what's actually in the cited file, the graph is behind: refresh, then re-query.
- **Don't** refresh mid-task or on every launch. With a warm cache it's seconds; if the cache was cleared it's a full rebuild (minutes), so don't trigger it speculatively — and if you do refresh, tell the user (it may take a while).

**Auto-refresh is installed**: each project's `post-commit` + `post-merge` git hooks run `refresh-graph.ps1 -NoViz` in the background (debounced) — so after a commit/merge the graph self-updates. Re-run `install-graph-hooks.ps1` after a fresh clone. (Don't use graphify's built-in `hook install`; it calls the crashing CLI extractor.)

> **Note on community names:** the plain-language module names in `GRAPH_REPORT.md` / `graph.html` were a one-time manual pass and **revert to "Community N" after a refresh** (community IDs can shift on rebuild). This is cosmetic and does **not** affect `query`/`explain`/`affected`/`path` results, which is all the agent uses.
