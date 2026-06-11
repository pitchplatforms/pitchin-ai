# Domain Docs

How the engineering skills should consume this workspace's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the workspace root (`ai/`) — the shared domain glossary across all three pitchIN repos.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.
- **`AGENTS.md`** at the workspace root — operational hard rules (money flows, god files, gates).

If `docs/adr/` doesn't exist yet, **proceed silently**. Don't flag its absence. The producer skill (`/grill-with-docs`) creates ADRs lazily when decisions actually get resolved.

## File structure

This is a single-context workspace: one `CONTEXT.md` at the `ai/` root covers all three repos (they share one domain — the apps are just different audiences of it).

```
ai/
├── CONTEXT.md            ← shared glossary
├── AGENTS.md             ← operational rules
├── docs/adr/             ← decisions (created lazily)
├── pitchINAPI/           ← code repo (own git)
├── PitchinAdminWeb/      ← code repo (own git)
└── PitchinCustomerWeb/   ← code repo (own git)
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids (e.g. say **MySec**, not PSTX; **Issuer**, not founder).

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (…) — but worth reopening because…_
