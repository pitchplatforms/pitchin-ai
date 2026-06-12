#!/usr/bin/env bash
# Ralph retro — DIGEST: triage a batch of run logs so the retro deep-reads less.
#
# Consumed by the `ralph-retro` skill (Step 2). For each unreviewed log it prints
# a one-line rubric + an `ok` / `>> FLAG` verdict, then a BATCH AGGREGATE:
# recurring failure signals counted by how many logs hit them, guardrail hits,
# the runs flagged for deep-read, and the summed batch cost. It is deterministic
# triage — it does NOT decide; the human still judges the flagged logs.
#
# INPUT
#   No args  -> digests exactly the logs `scan.sh` reports as unreviewed.
#   Args     -> digests those explicit log paths (re-digest a specific set).
#
# SIDE EFFECTS (skip with --dry-run; the skill applies memory only on approval)
#   * appends one ledger row per digested run to ralph/reviews/index.json
#       {"log","commit","issue","cost_usd","verdict","uat_result","reviewed_at",...}
#   * appends a dated batch block to ralph/reviews/IMPROVEMENTS.md (under "Open")
#   * moves each digested log into ralph/reviews/archive/ so it is never re-ingested
#
# The verdict here is a coarse, mechanical first pass (`good` unless a guardrail
# or rubric miss fires -> `mixed`); the retro overrides it after deep-reading.
# uat_result always seeds `untested` (only a later retro knows prod outcomes).
#
# Path model mirrors loop-parallel.sh / scan.sh: repo root = dir ABOVE ralph/.
# Prefers jq for JSON (repo convention); degrades to a hand-rolled writer when
# jq is absent so it still runs on a bare Git Bash. Portable bash.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Repo root = first ancestor containing a ralph/ subdir (see scan.sh for why).
REPO_ROOT=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ] && [ -n "$d" ]; do
  if [ -d "$d/ralph" ]; then REPO_ROOT="$d"; break; fi
  d="$(dirname "$d")"
done
[ -z "$REPO_ROOT" ] && REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LOGDIR="ralph/logs"
REVIEWS="ralph/reviews"
INDEX="$REVIEWS/index.json"
IMPROVEMENTS="$REVIEWS/IMPROVEMENTS.md"
ARCHIVE="$REVIEWS/archive"

HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
# Soft jq check: jq is the repo convention, but this script degrades to a
# hand-rolled JSON writer, so warn (don't hard-exit) when it's absent. Note the
# fallback can only initialise a fresh ledger — it cannot safely merge into an
# existing one (see append_ledger), so jq is strongly recommended.
[ "$HAVE_JQ" -eq 0 ] \
  && echo "digest: WARNING — jq not found; using a hand-rolled JSON fallback that cannot merge into an existing ledger (install jq: winget install jqlang.jq)." >&2

DRY_RUN=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    *)         ARGS+=("$a") ;;
  esac
done

# ── FAILURE_PATTERNS ──────────────────────────────────────────────────────────
# Each entry: "LABEL|<grep -E regex>". These key off the REAL markers the
# coordinator (loop-parallel.sh) and worker prompt (PROMPT.template.md) emit.
# Add a new line here when a fresh class of waste shows up — cheapest place to
# make the next retro sharper (see ralph-retro SKILL.md, Step 2 note).
FAILURE_PATTERNS=(
  "rate_limited|RATE_LIMITED|hit your session limit|usage limit"
  "no_work|<promise>NO_WORK</promise>"
  "partial|<promise>PARTIAL #|PARTIAL$"
  "blocked|<promise>BLOCKED #"
  "gate_change|WARNING: GATE CHANGE"
  "worker_failed|FAILED — exit code|worker .* FAILED"
  "worktree_partial|could not create worktree|worktree setup .* was partial|slice may be incomplete"
  "push_failed|push origin .* failed|CI will not run"
  "mis_triaged|no repo:<key> label|mis-triaged, skipping"
  "no_matches|no matches found|no matches for"
  "gate_red|gate error|Build FAILED|Tests failed|tests? failed|dotnet test.*fail"
  "env_read|cat .*\\.env|reading \\.env|open .*\\.env"
)

# Guardrail signals are the subset whose presence is a hard flag.
GUARDRAIL_LABELS="gate_change env_read"

# ── Gather the target log list ────────────────────────────────────────────────
LOGS=()
if [ "${#ARGS[@]}" -gt 0 ]; then
  LOGS=("${ARGS[@]}")
else
  # consume scan.sh's plain-line output (sibling script)
  while IFS= read -r line; do
    [ -n "$line" ] && LOGS+=("$line")
  done < <(bash "$SCRIPT_DIR/scan.sh" 2>/dev/null)
fi

if [ "${#LOGS[@]}" -eq 0 ]; then
  echo "digest: no logs to process (scan.sh reported none, or no paths given)."
  exit 0
fi

# ── Per-run accounting, plus batch aggregates ─────────────────────────────────
declare -A AGG_COUNT=()        # label -> number of logs that hit it (=() so set -u is happy when empty)
FLAGGED=()                    # logs tagged >> FLAG
BATCH_COST="0"
NEW_ROWS_FILE="$(mktemp)"     # collects JSON-ish rows to merge into the ledger
trap 'rm -f "$NEW_ROWS_FILE"' EXIT
REVIEWED_AT="$(date +%Y-%m-%d)"

echo "=== Ralph retro digest — ${#LOGS[@]} run(s) — $REVIEWED_AT ==="
echo

# helper: does $1 (file) match the regex $2 ?
matches() { grep -Eiq "$2" "$1" 2>/dev/null; }

# helper: extract a cost figure if the log carries one (cost: $1.23 / "total_cost_usd": 1.23)
extract_cost() {
  grep -Eio '("?(total_)?cost(_usd)?"?[[:space:]]*[:=][[:space:]]*\$?|\$)[0-9]+\.[0-9]+' "$1" 2>/dev/null \
    | grep -Eo '[0-9]+\.[0-9]+' | head -1
}

# helper: derive the issue number from the worker filename (worker-N-issue-M-ts.log)
extract_issue() {
  echo "$1" | sed -n 's/.*issue-\([0-9][0-9]*\).*/#\1/p' | head -1
}

# helper: the dominant promise sigil, if any
extract_promise() {
  if   grep -q '<promise>NEEDS_VERIFY' "$1" 2>/dev/null; then echo "NEEDS_VERIFY"
  elif grep -q '<promise>PARTIAL'      "$1" 2>/dev/null; then echo "PARTIAL"
  elif grep -q '<promise>BLOCKED'      "$1" 2>/dev/null; then echo "BLOCKED"
  elif grep -q '<promise>NO_WORK'      "$1" 2>/dev/null; then echo "NO_WORK"
  else echo "-"; fi
}

for log in "${LOGS[@]}"; do
  if [ ! -f "$log" ]; then
    echo "  WARN: $log not found — skipping."
    continue
  fi

  base="$(basename "$log")"
  issue="$(extract_issue "$base")"; [ -z "$issue" ] && issue="-"
  promise="$(extract_promise "$log")"
  cost="$(extract_cost "$log")"; [ -z "$cost" ] && cost="0"

  # match each failure pattern; collect the labels that hit
  hits=()
  guardrail_hit=0
  for entry in "${FAILURE_PATTERNS[@]}"; do
    label="${entry%%|*}"
    regex="${entry#*|}"
    if matches "$log" "$regex"; then
      hits+=("$label")
      AGG_COUNT["$label"]=$(( ${AGG_COUNT["$label"]:-0} + 1 ))
      case " $GUARDRAIL_LABELS " in *" $label "*) guardrail_hit=1 ;; esac
    fi
  done

  # failed-call heuristic: count obvious error/failure lines (cheap proxy)
  # grep -c exits 1 on zero matches; capture the count and normalise to one int.
  failed_calls=$(grep -Eic 'error|failed|exception' "$log" 2>/dev/null) || true
  failed_calls=${failed_calls//[^0-9]/}; failed_calls=${failed_calls:-0}

  # verdict: flag on any guardrail hit, a not-clean promise, or lots of errors
  verdict="good"
  flag="ok"
  reason=""
  if [ "$guardrail_hit" -eq 1 ]; then
    verdict="mixed"; flag=">> FLAG"; reason="guardrail"
  elif [ "$promise" = "PARTIAL" ] || [ "$promise" = "BLOCKED" ]; then
    verdict="mixed"; flag=">> FLAG"; reason="$promise"
  elif printf '%s\n' "${hits[@]:-}" | grep -qxE 'rate_limited|worker_failed|gate_red'; then
    verdict="mixed"; flag=">> FLAG"; reason="run-fault"
  elif [ "$failed_calls" -gt 25 ]; then
    flag=">> FLAG"; reason="noisy(${failed_calls})"
  fi
  [ "$flag" = ">> FLAG" ] && FLAGGED+=("$base ($reason)")

  # batch cost sum (awk for float add; falls back gracefully)
  BATCH_COST="$(awk -v a="$BATCH_COST" -v b="$cost" 'BEGIN{printf "%.2f", a+b}')"

  hitlist="$(printf '%s ' "${hits[@]:-}" | sed 's/ *$//')"; [ -z "$hitlist" ] && hitlist="none"

  printf '  %-7s %-4s promise=%-12s cost=$%-6s failed=%-4s signals=[%s]  %s\n' \
    "$flag" "$issue" "$promise" "$cost" "$failed_calls" "$hitlist" "$base"

  # stage a ledger row (newline-delimited fields; merged below)
  printf '%s\t%s\t%s\t%s\t%s\n' "$base" "$issue" "$cost" "$verdict" "$REVIEWED_AT" >> "$NEW_ROWS_FILE"
done

# ── Batch aggregate ───────────────────────────────────────────────────────────
echo
echo "--- Batch aggregate ---"
echo "Logs digested : ${#LOGS[@]}"
echo "Batch cost    : \$$BATCH_COST"
if [ "${#AGG_COUNT[@]}" -eq 0 ]; then
  echo "Failure signals: none matched."
else
  echo "Recurring failure signals (label: #logs hit):"
  for label in "${!AGG_COUNT[@]}"; do
    printf '    %-16s %s\n' "$label" "${AGG_COUNT[$label]}"
  done | sort -k2 -rn
fi
if [ "${#FLAGGED[@]}" -eq 0 ]; then
  echo "Flagged for deep-read: none"
else
  echo "Flagged for deep-read (${#FLAGGED[@]}):"
  for f in "${FLAGGED[@]}"; do echo "    $f"; done
fi
echo

if [ "$DRY_RUN" = 1 ]; then
  echo "digest: --dry-run set; ledger/IMPROVEMENTS/archive NOT modified."
  exit 0
fi

# ── Persist: ledger, IMPROVEMENTS backlog, archive ────────────────────────────
mkdir -p "$REVIEWS" "$ARCHIVE"

# 1) Ledger (index.json) — append one compact row per digested run.
append_ledger() {
  # build a temp JSON array of the new rows
  local newjson; newjson="$(mktemp)"
  if [ "$HAVE_JQ" -eq 1 ]; then
    # turn the TSV staging file into JSON objects
    jq -R -s 'split("\n") | map(select(length>0)) | map(split("\t")) |
      map({log:.[0], issue:.[1], cost_usd:(.[2]|tonumber? // 0),
           verdict:.[3], uat_result:"untested", reviewed_at:.[4]})' \
      "$NEW_ROWS_FILE" > "$newjson"
    if [ -f "$INDEX" ]; then
      jq --slurpfile add "$newjson" '.runs = ((.runs // []) + $add[0])' "$INDEX" > "$INDEX.tmp" \
        && mv "$INDEX.tmp" "$INDEX"
    else
      jq -n --slurpfile add "$newjson" \
        '{schema:"ralph-retro/index@1", runs:$add[0]}' > "$INDEX"
    fi
  else
    # hand-rolled JSON: read existing runs as raw text isn't safe to merge, so
    # only initialise if absent; otherwise warn (jq strongly recommended).
    if [ ! -f "$INDEX" ]; then
      {
        printf '{\n  "schema": "ralph-retro/index@1",\n  "runs": [\n'
        sep='    '
        while IFS=$'\t' read -r l i c v r; do
          [ -z "$l" ] && continue
          printf '%s{"log":"%s","issue":"%s","cost_usd":%s,"verdict":"%s","uat_result":"untested","reviewed_at":"%s"}' \
            "$sep" "$l" "$i" "${c:-0}" "$v" "$r"
          sep=$',\n    '
        done < "$NEW_ROWS_FILE"
        printf '\n  ]\n}\n'
      } > "$INDEX"
    else
      echo "digest: WARNING — jq not found and $INDEX exists; cannot safely merge ledger rows." >&2
      echo "        Install jq, or merge these rows by hand:" >&2
      cat "$NEW_ROWS_FILE" >&2
    fi
  fi
  rm -f "$newjson"
}
append_ledger

# 2) IMPROVEMENTS.md — append a dated batch block under the Open section.
{
  echo ""
  echo "### Batch $REVIEWED_AT — ${#LOGS[@]} run(s), \$$BATCH_COST"
  if [ "${#AGG_COUNT[@]}" -gt 0 ]; then
    echo "- Recurring signals this batch:"
    for label in "${!AGG_COUNT[@]}"; do
      echo "  - \`$label\` × ${AGG_COUNT[$label]}"
    done
  fi
  if [ "${#FLAGGED[@]}" -gt 0 ]; then
    echo "- Flagged for deep-read: ${FLAGGED[*]}"
  fi
  echo "- [ ] (retro) root-cause the recurring signals above and route fixes."
} >> "$IMPROVEMENTS"

# 3) Archive — move each digested log out of logs/ so it is never re-ingested.
for log in "${LOGS[@]}"; do
  [ -f "$log" ] || continue
  base="$(basename "$log")"
  mv "$log" "$ARCHIVE/$base" 2>/dev/null \
    || cp "$log" "$ARCHIVE/$base"
done

echo "digest: wrote ledger ($INDEX), appended backlog ($IMPROVEMENTS), archived ${#LOGS[@]} log(s) to $ARCHIVE/."
