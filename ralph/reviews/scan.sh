#!/usr/bin/env bash
# Ralph retro — SCAN: list the run logs that have NOT yet been reviewed.
#
# Consumed by the `ralph-retro` skill (Step 1). It prints, one per line, the
# `ralph/logs/*.log` files whose basename is not yet recorded in the ledger
# `ralph/reviews/index.json`. `digest.sh` reads exactly this list.
#
# A "run log" is any worker or coordinator log the parallel coordinator writes:
#   coordinator-<ts>.log
#   worker-<N>-issue-<M>-<ts>.log
# (The single-repo variant's iter-<n>-<ts>.log is also matched.)
#
# Path model mirrors loop-parallel.sh: the repo root is the dir ABOVE ralph/.
# We resolve it from $0 (invocation path) so this works whether the script is
# symlinked into <repo>/ralph/ or copied. Portable bash (Git Bash on Windows).
#
# Output: log paths relative to repo root, newline-separated, sorted oldest-first
#         (by filename timestamp). Nothing printed = nothing to review.
# Flags:  --json   emit a JSON array of the unreviewed paths instead of lines.

set -uo pipefail

# ── Resolve repo root: the dir ABOVE ralph/ (same model as loop-parallel.sh) ──
# This script may be invoked as ralph/scan.sh, ralph/reviews/scan.sh, or
# ralph/scripts/scan.sh depending on how the skill scaffolds it. Rather than
# hard-code a number of `..`, walk up from the script dir to the first ancestor
# that contains a `ralph/` subdir, and treat that as the repo root.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ] && [ -n "$d" ]; do
  if [ -d "$d/ralph" ]; then REPO_ROOT="$d"; break; fi
  d="$(dirname "$d")"
done
# Fallback: if no ralph/ ancestor (script run standalone), assume parent-of-parent.
[ -z "$REPO_ROOT" ] && REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LOGDIR="ralph/logs"
INDEX="ralph/reviews/index.json"

EMIT_JSON=0
[ "${1:-}" = "--json" ] && EMIT_JSON=1

# Soft jq check: jq is the repo convention, but this script has a grep fallback,
# so warn (don't hard-exit) when it's absent.
command -v jq >/dev/null 2>&1 \
  || echo "scan: WARNING — jq not found; using a crude grep fallback (install jq: winget install jqlang.jq)." >&2

if [ ! -d "$LOGDIR" ]; then
  echo "scan: no $LOGDIR directory — nothing to review." >&2
  [ "$EMIT_JSON" = 1 ] && echo "[]"
  exit 0
fi

# ── Collect the set of already-reviewed log basenames from the ledger ─────────
# Prefer jq (the repo convention). Fall back to a grep of the "log" fields so
# the script still works where jq is unavailable (e.g. a bare Git Bash).
reviewed_file="$(mktemp)"
trap 'rm -f "$reviewed_file"' EXIT

if [ -f "$INDEX" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -r '.runs[]?.log // empty' "$INDEX" 2>/dev/null > "$reviewed_file" || true
  else
    # crude but adequate: pull the value of each "log":"..." pair.
    grep -o '"log"[[:space:]]*:[[:space:]]*"[^"]*"' "$INDEX" 2>/dev/null \
      | sed 's/.*"log"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' > "$reviewed_file" || true
  fi
fi

is_reviewed() {
  # match on basename so a relative/absolute path difference doesn't matter
  local base; base="$(basename "$1")"
  grep -qxF "$base" "$reviewed_file" 2>/dev/null
}

# ── Walk logs (sorted), print the unreviewed ones ─────────────────────────────
unreviewed=()
# `ls` sort is lexicographic; the YYYYMMDD-HHMMSS timestamp makes that chronological.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  is_reviewed "$base" || unreviewed+=("ralph/logs/$base")
done < <(find "$LOGDIR" -maxdepth 1 -type f -name '*.log' 2>/dev/null | sort)

if [ "$EMIT_JSON" = 1 ]; then
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "${unreviewed[@]:-}" | jq -R . | jq -s 'map(select(length>0))'
  else
    # hand-roll a JSON array
    printf '['
    sep=''
    for p in "${unreviewed[@]:-}"; do
      [ -z "$p" ] && continue
      printf '%s"%s"' "$sep" "$p"; sep=','
    done
    printf ']\n'
  fi
  exit 0
fi

if [ "${#unreviewed[@]}" -eq 0 ]; then
  echo "scan: all logs in $LOGDIR are already in the ledger — nothing new to review." >&2
  exit 0
fi

printf '%s\n' "${unreviewed[@]}"
