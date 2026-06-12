# Ralph loop — improvement backlog

This file is the **undecided / needs-your-judgement** backlog for the Ralph loop,
maintained by the `ralph-retro` skill. Durable learnings that have a clear home are
routed elsewhere (`AGENTS.md`, `CONTEXT.md`, `ralph/PROMPT.md`, `.claude/agents/*.md`,
or a `docs/adr/`); only items that need a human decision land here.

`digest.sh` appends a dated batch block under **Open** each time a batch is digested.
During a retro, keep **Open** items at the top; move applied / rejected items to the
archive sections below with a one-line status. Keep entries terse.

## Open

<!-- digest.sh appends "### Batch <date>" blocks here. -->

- [ ] **(user action) Grant `anthony-ai-agent` Write on the 3 code repos** — push 403s
  (`Write access to repository not granted`) on `pitchINAPI`/`PitchinAdminWeb`/`PitchinCustomerWeb`
  block every run; token has `repo` scope but the account isn't a collaborator. Add via UI,
  `gh api -X PUT /repos/pitchplatforms/<repo>/collaborators/anthony-ai-agent -f permission=push`,
  or a team. Blocks all shipping until done. (Batch 2026-06-13)

## Applied

- 2026-06-13 — Push skipped when worker rate-limited (`loop-parallel.sh`). Was: push ran
  unconditionally after the rate-limit guard, emitting noisy 403s.
- 2026-06-13 — Coordinator releases orphaned `in-progress` claim on rate-limited workers
  (re-add `ready-for-agent`) (`loop-parallel.sh`). Stale label on #2 also stripped manually.
- 2026-06-13 — Success count excludes rate-limited workers: `SUCCESSES = LAUNCHED - FAILURES
  - RATE_LIMITED` (`loop-parallel.sh`). Was over-reporting "Succeeded".
- 2026-06-13 — Push-auth gotcha documented (`AGENTS.md`): `repo` token scope ≠ write access.

## Rejected / won't-do

<!-- Move items here with a one-line reason. -->

### Batch 2026-06-13 — 2 run(s), $0.00 — REVIEWED
- Recurring signals: `rate_limited` × 2, `push_failed` × 1 — both run-fault, root-caused.
- Worker rate-limited on turn 1 (no work shipped); push 403s = bot lacks repo write access.
- Fixes: 3 loop-script edits + 1 AGENTS.md note applied; 1 user action open (repo access).
- Full write-up: `archive/review-2026-06-13-issue-2.md`.
