#!/usr/bin/env bash
# Ralph MULTI-REPO parallel loop (pitchIN workspace).
#
# The coordinator runs from the ai/ orchestrator root (itself a git repo). It:
#   1. Reads canonical project facts from .claude/skill-config.json (via jq) and
#      loop overrides from ralph/ralph.config (shell-sourced).
#   2. Pre-assigns one ready-for-agent HUB issue per worker (cap workers by issue count).
#   3. For each assigned issue, parses its repo:<key> labels into a SLICE, creates an
#      isolated per-repo git worktree on branch ralph/slice-<N>, and launches one headless
#      claude worker with the slice's env wired in.
#   4. After each worker exits, pushes ONLY the slice branch in each touched code repo.
#
# Isolation comes from per-repo worktrees; safety from never pushing a base branch.
# There is NO single-repo branch guard — the orchestrator runs from ai/, not a code branch.
#
# Usage:  bash ralph/loop-parallel.sh <N>      (N = number of parallel workers, >= 1)
# Stop:   touch ralph/STOP                     (checked before launch)
#
# Portable bash (Git Bash on Windows): avoid GNU-only flags where a portable form exists.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1   # ai/ orchestrator root (parent of ralph/)

SKILL_CONFIG=".claude/skill-config.json"

# ── Config: loop overrides (sourced), then canonical facts from skill-config.json ──
# ralph.config is a KEY=value shell file holding only what differs from skill-config.
[ -f ralph/ralph.config ] && . ralph/ralph.config

if [ ! -f "$SKILL_CONFIG" ]; then
  echo "ERROR: $SKILL_CONFIG not found (must run from the ai/ root)." >&2
  exit 1
fi

# Hub slug: ralph.config override, else skill-config .tracker.repo.
HUB="${RALPH_HUB_REPO:-$(jq -r '.tracker.repo' "$SKILL_CONFIG")}"
READY_LABEL="${RALPH_READY_LABEL:-ready-for-agent}"
# Repo keys the loop can work. Override via ralph.config; else all keys in skill-config.
RALPH_REPOS="${RALPH_REPOS:-$(jq -r '.repos | keys | join(" ")' "$SKILL_CONFIG")}"

# ── Args ────────────────────────────────────────────────────────────────────
N="${1:-}"
if [[ -z "$N" || ! "$N" =~ ^[0-9]+$ || "$N" -lt 1 ]]; then
  echo "Usage: bash ralph/loop-parallel.sh <N>  (N = number of workers, >= 1)" >&2
  exit 1
fi

# ── Dependency preconditions ──────────────────────────────────────────────────
# The loop needs: jq (read skill-config.json), gh (hub issues), git (worktrees),
# claude (workers). Fail fast with a clear, fixable message if any is missing.
for dep in jq gh git claude; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    case "$dep" in
      jq)     fix="install it: winget install jqlang.jq" ;;
      gh)     fix="install the GitHub CLI: https://cli.github.com" ;;
      git)    fix="install Git: https://git-scm.com" ;;
      claude) fix="install the Claude Code CLI" ;;
    esac
    echo "ERROR: required tool '$dep' not found on PATH — $fix" >&2
    exit 1
  fi
done

PROMPT="ralph/PROMPT.md"
LOGDIR="ralph/logs"
mkdir -p "$LOGDIR"

ts=$(date +%Y%m%d-%H%M%S)
COORDINATOR_LOG="$LOGDIR/coordinator-$ts.log"

log() { echo "$*" | tee -a "$COORDINATOR_LOG"; }

log "=== Ralph multi-repo parallel coordinator — $ts ==="
log "Requested workers: $N"
log "Hub: $HUB | Ready label: $READY_LABEL | Repos: $RALPH_REPOS"

# ── STOP file check ──────────────────────────────────────────────────────────
if [[ -f ralph/STOP ]]; then
  log "STOP file found — aborting before launch. Remove ralph/STOP to run again."
  rm -f ralph/STOP
  exit 0
fi

# NOTE: no branch guard. The orchestrator intentionally runs from ai/ (not a code
# branch). Per-repo worktrees provide isolation; never pushing a base branch is the safety.

# ── Per-repo merged config (path from skill-config; base/gate = override ?? skill-config) ──
# Resolve once up front so worktree creation and env wiring can reuse them.
declare -A REPO_PATH REPO_BASE REPO_GATE
for k in $RALPH_REPOS; do
  path=$(jq -r --arg k "$k" '.repos[$k].path // empty' "$SKILL_CONFIG")
  if [[ -z "$path" ]]; then
    log "WARN: repo key '$k' has no .repos.$k.path in $SKILL_CONFIG — skipping it."
    continue
  fi
  sc_base=$(jq -r --arg k "$k" '.repos[$k].default_branch // empty' "$SKILL_CONFIG")
  sc_gate=$(jq -r --arg k "$k" '.repos[$k].code_gate // empty' "$SKILL_CONFIG")

  base_var="RALPH_REPO_${k}_BASE"; base="${!base_var:-$sc_base}"
  gate_var="RALPH_REPO_${k}_GATE"; gate="${!gate_var:-$sc_gate}"

  REPO_PATH["$k"]="$path"
  REPO_BASE["$k"]="$base"
  REPO_GATE["$k"]="$gate"
  log "  repo $k: path=$path base=$base gate=[$gate]"
done

# ── Enumerate ready HUB issues upfront (coordinator pre-assignment) ──────────
# We need labels too, to slice each issue into its repo subset.
log "Fetching open $READY_LABEL issues from hub $HUB ..."
ISSUES_JSON=$(gh -R "$HUB" issue list \
  --state open \
  --label "$READY_LABEL" \
  --json number,labels \
  2>>"$COORDINATOR_LOG")

TOTAL_ISSUES=$(echo "$ISSUES_JSON" | jq 'length')
log "Found $TOTAL_ISSUES $READY_LABEL issue(s)."

if [[ "$TOTAL_ISSUES" -eq 0 ]]; then
  log "No $READY_LABEL issues — nothing for ralph to work."
  exit 0
fi

# Cap workers by available issues (no point spawning more workers than issues).
WORKER_COUNT=$(( N < TOTAL_ISSUES ? N : TOTAL_ISSUES ))
log "Launching $WORKER_COUNT worker(s) (capped by available issues)."

# Pre-assign one issue number per worker (decided upfront — no in-worker race).
declare -a ASSIGNED_ISSUES
for idx in $(seq 0 $(( WORKER_COUNT - 1 ))); do
  ASSIGNED_ISSUES[$idx]=$(echo "$ISSUES_JSON" | jq ".[$idx].number")
done

# ── Launch workers ────────────────────────────────────────────────────────────
declare -a WORKER_PIDS
declare -a WORKER_LOGS
declare -a WORKER_SLICES   # space-separated repo keys per worker, for the push phase

for idx in $(seq 0 $(( WORKER_COUNT - 1 ))); do
  ISSUE_NUM="${ASSIGNED_ISSUES[$idx]}"
  WORKER_ID=$(( idx + 1 ))
  WORKER_LOG="$LOGDIR/worker-$WORKER_ID-issue-$ISSUE_NUM-$ts.log"
  WORKER_LOGS[$idx]="$WORKER_LOG"

  # Slice: subset of RALPH_REPOS whose repo:<key> label is present on this issue.
  ISSUE_LABELS=$(echo "$ISSUES_JSON" | jq -r ".[$idx].labels[].name")
  SLICE_REPOS=""
  for k in $RALPH_REPOS; do
    # only consider configured repos (those with a resolved path)
    [[ -z "${REPO_PATH[$k]:-}" ]] && continue
    if echo "$ISSUE_LABELS" | grep -qx "repo:$k"; then
      SLICE_REPOS="${SLICE_REPOS:+$SLICE_REPOS }$k"
    fi
  done

  if [[ -z "$SLICE_REPOS" ]]; then
    log "SKIP: issue #$ISSUE_NUM has no repo:<key> label matching [$RALPH_REPOS] — mis-triaged, skipping."
    WORKER_PIDS[$idx]=""
    WORKER_SLICES[$idx]=""
    continue
  fi

  SLICE_BRANCH="ralph/slice-$ISSUE_NUM"
  WORKER_SLICES[$idx]="$SLICE_REPOS"
  log "Spawning worker $WORKER_ID → issue #$ISSUE_NUM | slice: [$SLICE_REPOS] | branch: $SLICE_BRANCH"

  # ── Create one idempotent worktree per repo in the slice ────────────────────
  # Build the per-repo env exports (RALPH_WORKTREE_<k> / RALPH_GATE_<k>) as we go.
  declare -a SLICE_ENV=()
  declare -A SLICE_WT=()      # key -> absolute worktree path (reused in push phase)
  worktree_ok=1
  for k in $SLICE_REPOS; do
    code_repo="${REPO_PATH[$k]}"
    base="${REPO_BASE[$k]}"
    target="$PWD/ralph/worktrees/slice-$ISSUE_NUM/$k"
    SLICE_WT["$k"]="$target"

    # Prune stale worktree metadata first, then add — reuse if already present.
    git -C "$code_repo" worktree prune 2>>"$COORDINATOR_LOG" || true

    if [[ -d "$target" ]]; then
      log "  worktree exists, reusing: $target"
    elif git -C "$code_repo" worktree add "$target" -b "$SLICE_BRANCH" "$base" 2>>"$COORDINATOR_LOG"; then
      log "  worktree added: $code_repo [$SLICE_BRANCH @ $base] -> $target"
    else
      # Branch likely already exists — reuse it without -b. Never hard-fail the run.
      if git -C "$code_repo" worktree add "$target" "$SLICE_BRANCH" 2>>"$COORDINATOR_LOG"; then
        log "  worktree added (reused existing branch $SLICE_BRANCH): $target"
      else
        log "  WARN: could not create worktree for repo $k (issue #$ISSUE_NUM) — slice may be incomplete."
        worktree_ok=0
      fi
    fi

    SLICE_ENV+=( "RALPH_WORKTREE_${k}=$target" )
    SLICE_ENV+=( "RALPH_GATE_${k}=${REPO_GATE[$k]}" )
  done

  if [[ "$worktree_ok" -eq 0 ]]; then
    log "  NOTE: worktree setup for issue #$ISSUE_NUM was partial; launching worker anyway."
  fi

  # ── Launch the worker with the slice env wired in ───────────────────────────
  (
    export RALPH_ISSUE="$ISSUE_NUM"
    export RALPH_WORKER_ID="$WORKER_ID"
    export RALPH_HUB_REPO="$HUB"
    export RALPH_SLICE_BRANCH="$SLICE_BRANCH"
    export RALPH_SLICE_REPOS="$SLICE_REPOS"
    # Per-repo worktree paths and gate commands (RALPH_WORKTREE_<k>, RALPH_GATE_<k>).
    for kv in "${SLICE_ENV[@]}"; do
      export "$kv"
    done

    echo "=== Worker $WORKER_ID | Issue #$ISSUE_NUM | slice [$SLICE_REPOS] | $ts ===" | tee "$WORKER_LOG"

    claude -p "$(cat "$PROMPT")" \
        --model sonnet \
        --dangerously-skip-permissions \
        2>&1 | tee -a "$WORKER_LOG"

    # Rate-limit guard: detect session/usage limit hit.
    worker_rate_limited=0
    if grep -qi "hit your session limit\|usage limit" "$WORKER_LOG"; then
      worker_rate_limited=1
      echo "RATE_LIMITED — session/usage limit reached for worker $WORKER_ID." \
        | tee -a "$WORKER_LOG"
      grep -io "resets[^.]*" "$WORKER_LOG" | head -1 | tee -a "$WORKER_LOG"
    fi

    # ── Push ONLY the slice branch in each touched repo — NEVER a base branch ──
    # Skip entirely when the worker was rate-limited: it did no usable work, so a
    # push just emits noisy failures (e.g. 403s) that mask real signals.
    if [[ "$worker_rate_limited" -eq 1 ]]; then
      echo "SKIP push: worker $WORKER_ID was rate-limited — nothing to push." \
        | tee -a "$WORKER_LOG"
    else
      for k in $SLICE_REPOS; do
        wt="${SLICE_WT[$k]}"
        git -C "$wt" push origin "$SLICE_BRANCH" 2>&1 | tee -a "$WORKER_LOG" \
          || echo "WARN: git -C $wt push origin $SLICE_BRANCH failed (repo $k) — CI will not run." \
               | tee -a "$WORKER_LOG"
      done
    fi

  ) &

  WORKER_PIDS[$idx]=$!
  log "Worker $WORKER_ID PID: ${WORKER_PIDS[$idx]}"
done

# ── Wait for all workers ──────────────────────────────────────────────────────
log "All worker(s) launched. Waiting for completion..."

FAILURES=0
RATE_LIMITED=0
LAUNCHED=0

for idx in $(seq 0 $(( WORKER_COUNT - 1 ))); do
  WORKER_ID=$(( idx + 1 ))
  PID="${WORKER_PIDS[$idx]}"
  ISSUE_NUM="${ASSIGNED_ISSUES[$idx]}"
  WLOG="${WORKER_LOGS[$idx]}"

  # Skipped (mis-triaged) issues have no PID.
  if [[ -z "$PID" ]]; then
    continue
  fi
  (( LAUNCHED++ )) || true

  wait "$PID"
  EXIT_CODE=$?

  if [[ "$EXIT_CODE" -ne 0 ]]; then
    (( FAILURES++ )) || true
    log "Worker $WORKER_ID (issue #$ISSUE_NUM) FAILED — exit code $EXIT_CODE"
  else
    log "Worker $WORKER_ID (issue #$ISSUE_NUM) finished — exit code 0"
  fi

  if [[ -f "$WLOG" ]] && grep -qi "RATE_LIMITED" "$WLOG"; then
    (( RATE_LIMITED++ )) || true
    log "Worker $WORKER_ID was rate-limited."
    # Release the orphaned claim: a rate-limited worker never reaches a terminal
    # state, so it leaves 'in-progress' on the issue. Hand it back so the next
    # run can re-pick it cleanly (re-add the ready label, drop in-progress).
    if [[ -n "$ISSUE_NUM" && "$ISSUE_NUM" != "-" ]]; then
      gh -R "$HUB" issue edit "$ISSUE_NUM" \
        --remove-label in-progress --add-label "$READY_LABEL" >/dev/null 2>&1 \
        && log "Released claim on issue #$ISSUE_NUM (in-progress → $READY_LABEL)." \
        || log "WARN: could not release claim on issue #$ISSUE_NUM — relabel it by hand."
    fi
  fi

  if [[ -f "$WLOG" ]] && grep -q "<promise>NO_WORK</promise>" "$WLOG"; then
    log "Worker $WORKER_ID reported NO_WORK (issue #$ISSUE_NUM may have been reclaimed)."
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
# A rate-limited worker exits 0 but did no usable work — don't count it as a success.
SUCCESSES=$(( LAUNCHED - FAILURES - RATE_LIMITED ))
(( SUCCESSES < 0 )) && SUCCESSES=0
log ""
log "=== Ralph multi-repo parallel run complete ==="
log "Launched: $LAUNCHED | Succeeded: $SUCCESSES | Failed: $FAILURES | Rate-limited: $RATE_LIMITED"
log "Review hand-offs on the hub: gh -R $HUB issue list --label needs-human-verify"
log "Coordinator log: $COORDINATOR_LOG"

if [[ "$RATE_LIMITED" -gt 0 ]]; then
  log "NOTE: $RATE_LIMITED worker(s) hit the session/usage limit. Re-launch after the limit resets."
fi

if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi

exit 0
