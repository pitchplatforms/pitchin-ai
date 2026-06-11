# Workspace guide

This folder holds three pitchIN codebases: `pitchINAPI` (.NET API), `PitchinAdminWeb` and `PitchinCustomerWeb` (Angular). They integrate only through the API.

## Use graphify to navigate the code

A graphify knowledge graph of all three projects lives at `graphify-out/graph.json`.

**When you need to locate code, find what depends on something, or understand how a feature is wired across these projects, query the graph first** — it's token-cheap and cites `source_file:line` — instead of grepping or reading files broadly. Then open only the files it points to.

Quick start (run from this `ai/` folder):
```powershell
$py = Get-Content graphify-out\.graphify_python
& $py -m graphify query "<your question>" --graph graphify-out\graph.json --budget 1200
```

**Read [GRAPHIFY.md](GRAPHIFY.md) for the full command set (`query`, `explain`, `affected`, `path`), the exact Windows invocation, how to read the output, and caveats.** Consult it whenever you're about to use graphify.

Note: the graph is structural (AST) only — treat its results as strong pointers and confirm specifics in the cited source.

## When a skill says "explore the codebase"

Skills you run here — grill-with-docs, to-prd, to-issues, triage, tdd, code-review/verify, and the ralph loop — include a generic "explore the repo / explore the codebase" step. **Satisfy it with graphify, not broad grep/read.** GRAPHIFY.md has a per-skill **Playbook** — read your stage's row for the exact query and how to use its output. Default to graphify for any "explore" / "locate" / "what-depends-on" step.
