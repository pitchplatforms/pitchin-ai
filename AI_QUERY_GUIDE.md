# AI Query Guide — pitchIN code graph

How a downstream AI should **navigate this codebase cheaply** instead of reading it whole. Pair with `ARCHITECTURE.md` (the orientation doc).

## The idea

A structural knowledge graph of all three repos lives in `graphify-out/`. Rather than loading source files into context, **ask the graph** for the exact slice you need. Each answer is token-bounded and cites `source_file:line`, so you read only the files that matter.

## Artifacts in `graphify-out/`

| File | Use |
|---|---|
| `graph.json` | The graph (30,549 nodes / 62,242 edges). Query target. Do **not** load it raw — it's ~30 MB. |
| `GRAPH_REPORT.md` | God nodes, surprising connections, per-module community listing, suggested questions. Skim, don't ingest whole. |
| `graph.html` | Interactive visual module map (open in a browser; humans). |
| `.graphify_labels.json` | Community → plain-language module name. |

## Running queries (Windows)

graphify's CLI is not on PATH; invoke through the interpreter recorded in `graphify-out/.graphify_python` (Python 3.12):

```powershell
$py = Get-Content graphify-out\.graphify_python
& $py -m graphify <command>
```

### Commands

```powershell
# Broad context for a question (BFS). --budget caps the token cost.
& $py -m graphify query "How does an investor invest in a campaign?" --budget 1200

# Trace one specific path (DFS) instead of breadth.
& $py -m graphify query "What does CampaignService depend on?" --dfs --budget 1000

# Shortest path between two concepts (how are they connected?).
& $py -m graphify path "InvestmentService" "PostgreSQL"

# Plain-language explanation of one node + its neighbours.
& $py -m graphify explain "DigitalRegistryService"

# Reverse impact analysis — what breaks if I change X?
& $py -m graphify affected "Attachment" --depth 2
```

`query` returns `NODE <label> [src=<repo>/<path> loc=L<n> community=<id>]` lines plus edges. Start with a small `--budget` (800–1500); widen only if the slice is too thin. Narrow noisy results with `--context call` (or another edge relation).

## Recommended workflow for an AI planning work here

1. **Orient** — read `ARCHITECTURE.md` §1, §6, §7 (systems, health, AI-native barriers). Cheap, high-signal.
2. **Locate** — `graphify query "<your task in plain English>" --budget 1000` to find the relevant files/classes and which of the three repos they live in.
3. **Trace** — use `path` / `affected` to map dependencies and blast radius before proposing a change.
4. **Read selectively** — open only the `source_file:line` the graph cited.
5. **Plan against the contract** — for anything spanning frontend↔backend, prefer the backend's **Swagger/OpenAPI** spec as the source of truth (the two Angular apps are independent and integrate only via `/api/v1`).

## Limits — read before trusting

- **Structural only.** The graph is AST-derived: classes, files, references, inheritance, containment. It does **not** encode runtime behavior, business rules, or intent. Confirm specifics in the cited source.
- **Excluded from the graph:** vendored libraries (CKEditor, Cokeeps SDK), `assets/`, build output, tests, and JSON/config. Don't expect to find them here.
- **Three separate graphs in one.** Node IDs are namespaced by repo (`pitchINAPI::`, `PitchinAdminWeb::`, `PitchinCustomerWeb::`). There are no real cross-repo code edges; the systems meet only at the HTTP API.

## Rebuilding / refreshing the graph

Helper scripts are in `graphify-out/` (`_run_extract.py`, `_run_build.py`, `_run_label.py`). On this Windows machine, extraction **must** run with `parallel=False` (the multiprocessing pool crashes otherwise), and large JSON writes are fsync-verified to avoid null-byte corruption. To refresh after code changes, re-run extract → build → label, or use `& $py -m graphify update <path>` for incremental updates.
