# Issue tracker: GitHub (hub repo)

Issues and PRDs for this workspace live in the central hub repo **`pitchplatforms/pitchin-issues`** — NOT in the code repos. Always pass `-R pitchplatforms/pitchin-issues` to `gh issue` commands (this workspace root and the code repos have different remotes, so `gh` cannot infer the hub).

## Conventions

- **Create an issue**: `gh -R pitchplatforms/pitchin-issues issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh -R pitchplatforms/pitchin-issues issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh -R pitchplatforms/pitchin-issues issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh -R pitchplatforms/pitchin-issues issue comment <number> --body "..."`
- **Apply / remove labels**: `gh -R pitchplatforms/pitchin-issues issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: agents do NOT close issues (see AGENTS.md hard rule 2) — hand off with the `needs-human-verify` label instead.

## Routing labels

Tag each issue with the repos its slice touches: `repo:api`, `repo:admin`, `repo:customer`. Conditional gates: `needs:e2e`, `needs:ocr`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `pitchplatforms/pitchin-issues`.

## When a skill says "fetch the relevant ticket"

Run `gh -R pitchplatforms/pitchin-issues issue view <number> --comments`.
