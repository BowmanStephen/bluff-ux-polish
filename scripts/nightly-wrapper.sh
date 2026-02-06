#!/usr/bin/env bash
# nightly-wrapper.sh — Orchestrates the nightly compound loop.
# Runs compound review first, waits for it to complete, then runs auto-compound.
#
# Usage: ./scripts/nightly-wrapper.sh [--dry-run]
#   --dry-run: Pass --dry-run to both sub-scripts.
#
# Designed to be triggered by launchd at 10:30 PM nightly.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_DIR/scripts/logs"
TODAY=$(date +%Y-%m-%d)
WRAPPER_LOG="$LOG_DIR/nightly-wrapper-${TODAY}.log"
DRY_RUN_FLAG=""

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN_FLAG="--dry-run"
fi

mkdir -p "$LOG_DIR"

# ── Logging helper ────────────────────────────────────────────
log() {
  echo "[$(date '+%H:%M:%S')] $1" | tee -a "$WRAPPER_LOG"
}

# ── Start ─────────────────────────────────────────────────────
log "=== Nightly compound loop starting ==="
log "    Repo: $REPO_DIR"
log "    Dry-run: ${DRY_RUN_FLAG:-no}"
LOOP_START=$(date +%s)

# ── Stage 1: Compound Review ─────────────────────────────────
log "--- Stage 1: Compound Review ---"
STAGE1_START=$(date +%s)
STAGE1_EXIT=0

"$REPO_DIR/scripts/daily-compound-review.sh" $DRY_RUN_FLAG 2>&1 | tee -a "$WRAPPER_LOG" || STAGE1_EXIT=$?

STAGE1_END=$(date +%s)
STAGE1_DURATION=$(( STAGE1_END - STAGE1_START ))
log "--- Stage 1 finished in ${STAGE1_DURATION}s (exit code: $STAGE1_EXIT) ---"

if [[ $STAGE1_EXIT -ne 0 ]]; then
  log "WARNING: Compound review failed. Continuing to auto-compound anyway."
fi

# ── Stage 2: Auto-Compound Agent ─────────────────────────────
log "--- Stage 2: Auto-Compound Agent ---"
STAGE2_START=$(date +%s)
STAGE2_EXIT=0

"$REPO_DIR/scripts/auto-compound.sh" $DRY_RUN_FLAG 2>&1 | tee -a "$WRAPPER_LOG" || STAGE2_EXIT=$?

STAGE2_END=$(date +%s)
STAGE2_DURATION=$(( STAGE2_END - STAGE2_START ))
log "--- Stage 2 finished in ${STAGE2_DURATION}s (exit code: $STAGE2_EXIT) ---"

# ── Summary ───────────────────────────────────────────────────
LOOP_END=$(date +%s)
LOOP_DURATION=$(( LOOP_END - LOOP_START ))

log "=== Nightly compound loop finished ==="
log "    Total duration: ${LOOP_DURATION}s"
log "    Review:        exit $STAGE1_EXIT (${STAGE1_DURATION}s)"
log "    Auto-compound: exit $STAGE2_EXIT (${STAGE2_DURATION}s)"
log "    Log: $WRAPPER_LOG"

# Exit with failure if either stage failed
if [[ $STAGE1_EXIT -ne 0 || $STAGE2_EXIT -ne 0 ]]; then
  exit 1
fi
