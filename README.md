# pitchIN AI Workspace

This folder (`ai/`) holds the three pitchIN codebases plus a **graphify code-intelligence setup** that lets AI agents *and* humans navigate and understand the code cheaply, and a CTO-facing architecture review.

**This README is the human guide** — what's here, how to use it, how it stays current, and the machine-specific learnings worth not rediscovering. The agent-facing instructions live in `CLAUDE.md` / `GRAPHIFY.md`.

---

## The projects

| Folder | Stack | Role |
|---|---|---|
| `pitchINAPI/` | .NET (ASP.NET Core, EF Core + PostgreSQL) | Backend API — all business logic |
| `PitchinAdminWeb/` | Angular 16 (SPA) | Back-office admin app |
| `PitchinCustomerWeb/` | Angular 16 + SSR | Public customer app |

They're **independent git repos** that integrate only through the API. (Also here: `skills-and-tools/` = tooling incl. the graphify source; `codebase-architecture-review/` = the shareable CTO package, also on GitHub.)

---

## Quick start

**Ask the codebase a question** (run from this `ai/` folder, PowerShell):
```powershell
$py = Get-Content graphify-out\.graphify_python
& $py -m graphify query "where are campaign refunds handled?" --graph graphify-out\graph.json --budget 1200
```
Output is `NODE <name> [src=<file> loc=L<n>]` lines — open the cited files.

**See the visual map:** open `graphify-out/graph.html` in a browser.
**Read the architecture:** `ARCHITECTURE.md` (or the slide deck `CTO_CHECKIN.html`).

---

## What's where

| File / folder | For | What it is |
|---|---|---|
| **`README.md`** (this) | humans | The setup + usage + learnings guide |
| **`CLAUDE.md`** | agents | Auto-loaded by Claude Code; tells agents to use graphify and when |
| **`GRAPHIFY.md`** | agents | Full how-to: commands, **per-skill playbook**, weak spots, refresh |
| **`ARCHITECTURE.md`** | humans/CTO | Overview of the 3 systems + AI-readiness assessment |
| **`IMPROVEMENTS.md`** | humans/agents | Ranked, file-level improvement opportunities (the "why" behind the weak spots) |
| **`AI_QUERY_GUIDE.md`** | agents | Short guide for an AI on querying the graph cheaply |
| **`CTO_CHECKIN.html`** | humans/CTO | Slide deck walkthrough (open in browser) |
| **`refresh-graph.ps1`** | humans | Rebuild the graph (`-NoViz` skips the HTML map) |
| **`install-graph-hooks.ps1`** | humans | Install/remove the auto-refresh git hooks (`-Uninstall`) |
| **`graphify-out/`** | both | `graph.json` (the queryable graph), `GRAPH_REPORT.md` (audit), `graph.html` (map), helper/refresh scripts |
| **`codebase-architecture-review/`** | humans | The light, shareable review package (pushed to `pitchplatforms/codebase-architecture-review`) |

---

## Using graphify

graphify turns the code into a queryable graph so you find the right files without reading everything. Four commands (all take `--graph graphify-out\graph.json`):

| Command | Use it to… |
|---|---|
| `query "<question>"` | Find the files/symbols relevant to a question. **Start here.** `--budget N` caps the answer size. |
| `explain "<Symbol>"` | See one class/file + what it connects to. |
| `affected "<Symbol>"` | Reverse impact — what breaks if it changes. |
| `path "<A>" "<B>"` | Shortest connection between two symbols. |

**The CLI is not on PATH** — always run it through the recorded interpreter (`graphify-out\.graphify_python`), as in the Quick start. Full command reference, output format, and caveats: **`GRAPHIFY.md`**.

The graph is **structural (AST) only** (~30.5k nodes across the 3 projects): files, classes, references — *not* runtime behaviour. Treat results as strong pointers and confirm in the cited source. Vendored libraries, build output, tests, and JSON/config are excluded on purpose; node IDs are namespaced by repo (`pitchINAPI::…` etc.).

---

## Keeping the graph current (auto-refresh)

A commit or merge in any of the three repos refreshes `graph.json` **automatically, in the background**:

- `post-commit` + `post-merge` git hooks (installed by `install-graph-hooks.ps1`) call `graphify-out/_refresh-hook.ps1`, which runs `refresh-graph.ps1 -NoViz`.
- It's **non-blocking** (launched detached) and **debounced + locked**, so rapid or multi-repo commits don't collide — they converge to one correct rebuild.
- Off a warm cache it's seconds (only changed files re-parse); a cold cache is a few minutes.

**You need to know:**
- **Hooks aren't version-controlled** — after a fresh clone or on a new machine, re-run `.\install-graph-hooks.ps1`. (`-Uninstall` removes them.)
- The hooks use `-NoViz`, so the **HTML map and community names don't auto-update** — run `.\refresh-graph.ps1` manually when you want the visual refreshed.
- Logs: `graphify-out/_refresh-hook.log` and `_refresh.log`.

**Manual refresh:** `.\refresh-graph.ps1` (full, incl. HTML) or `.\refresh-graph.ps1 -NoViz`.

---

## How agents use it (the workflow)

`CLAUDE.md` (auto-loaded) tells any agent running here to satisfy a skill's "explore the codebase" step with graphify, and `GRAPHIFY.md` has a **per-skill Playbook** mapping each workflow stage to *why/which command/how to use it*:

`grill-with-docs` → `to-prd` → `to-issues` → `triage` → `plan-qa-test` → `tdd`/`ralph-loop` → `check-human-verify` → `QA`.

For an agent built outside Claude Code (or a ralph loop in a separate worktree), point it at `GRAPHIFY.md` directly — the playbook is self-contained.

---

## Known weaknesses (where to be careful)

Summarised in `GRAPHIFY.md` and detailed in `IMPROVEMENTS.md`. The headlines:
- **No automated tests on the two Angular apps** (`"test": ""`) — frontend changes can't self-verify.
- **God files** — `CampaignService.cs` (~8.8k loc), `InvestmentService.cs` (~7.4k loc), Admin `campaign.service.ts`/`digital-registry.service.ts`, Customer `account.service.ts`/`app.component.ts`.
- **Duplication across the two Angular apps** (models/enums/interceptor/services) — fix one, fix the other.
- **~118 untyped (`Observable<any>`) API calls** on the customer app.
- **MySec** integration spread across ~14 modules. **Money/settlement flows** are sensitive — confirm before changing.

---

## Machine-specific learnings (don't rediscover these)

This was set up on a Windows machine that started with no Python. Captured so future-you/teammates don't relearn them:

1. **Python + graphify install.** Python 3.12 lives at `C:\Users\pitchIN-TP-09\AppData\Local\Programs\Python\Python312\python.exe` (installed via `winget`). The package is **`graphifyy`** (pip). The CLI isn't on PATH — run as `& $py -m graphify …` via the recorded interpreter in `graphify-out\.graphify_python`.
2. **The parallel extractor crashes here.** `graphify extract` / `graphify update` use a process pool that dies on this machine (0 nodes). The build/refresh **must run sequentially** (`parallel=False`) — that's what `refresh-graph.ps1` and the `graphify-out/_run_*.py` helpers do. **Don't call `graphify update`/`extract` directly.**
3. **Large JSON writes can null-byte-corrupt.** `graph.json` once came back as 45 MB of nulls (delayed-write loss). The build/refresh scripts now **fsync and verify** every write, and `refresh-graph.ps1` integrity-checks `graph.json` at the end.
4. **`graph.json` is ~45 MB** — deliberately excluded from the shareable `codebase-architecture-review/` repo (kept light); it's regenerable, so it's not the artifact you share.
5. **Community names are cosmetic.** The plain-language module names in `GRAPH_REPORT.md`/`graph.html` were a one-time manual pass and **revert to "Community N" after a refresh** (cluster IDs shift). This does **not** affect query results.
6. **Ambiguous names.** Some names exist in all three apps (`CampaignService`, `Campaign`, `Attachment`) — `explain`/`path` may resolve to one; check the `src=` repo prefix or narrow the query.
7. **The installed `/graphify` skill is a broken Mac symlink.** The real source is in `skills-and-tools/graphify-repo/graphify/` (use `skill-windows.md` there).

---

## Regenerating from scratch

If `graphify-out/` is lost, the pipeline (all in `graphify-out/`, Windows `parallel=False`):
`_run_extract.py` (extract code, exclude vendor/tests/JSON) → `_run_build.py` (merge repo-namespaced, cluster, write + verify `graph.json` + `GRAPH_REPORT.md`) → `_run_label.py` (optional community names) → `graphify export html`. `refresh-graph.ps1` orchestrates the first three.

---

## Related docs

- **`ARCHITECTURE.md`** — system overview + AI-readiness.
- **`IMPROVEMENTS.md`** — the deepening/refactor opportunities, ranked.
- **`GRAPHIFY.md`** — the agent how-to + per-skill playbook.
- **`codebase-architecture-review/`** — the CTO package (deck + docs), also at `github.com/pitchplatforms/codebase-architecture-review`.
