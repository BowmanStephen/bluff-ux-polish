#!/usr/bin/env bash
# auto-compound.sh — Nightly agent that picks the top Linear issue and implements it.
# Creates a feature branch, implements the change, and opens a draft PR.
#
# Usage: ./scripts/auto-compound.sh [--dry-run]
#   --dry-run: Print the prompt and config, skip the Claude invocation.
#
# Designed to run after daily-compound-review.sh (so CLAUDE.md is fresh).

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_DIR/scripts/logs"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/auto-compound-${TODAY}.log"
BUDGET="1.00"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] Will print config and prompt, then exit."
fi

# ── Append System Prompt ──────────────────────────────────────
read -r -d '' AGENT_PROMPT << 'PROMPT_EOF' || true
You are an autonomous nightly agent for the bluff-ux-polish project.

WORKFLOW:
1. Query Linear (via MCP) for the highest-priority issue in the "Bluff UX Polish"
   project that has the "Agent-Safe" label, is in "Backlog" status, and is
   estimated at 3 points or fewer. If no eligible issue exists, output exactly:
   NO_ELIGIBLE_ISSUE
   and stop immediately.

2. Output the issue identifier and title on the first line as:
   ISSUE: <identifier> — <title>

3. Create a feature branch: git checkout -b agent/<identifier-lowercase>

4. Read the full issue description from Linear. Understand what needs to be done.

5. Implement the changes. Follow the project's CLAUDE.md constraints strictly.
   DO NOT modify: .github/, package.json, package-lock.json, .env*,
   CLAUDE.md, scripts/, next.config.*

6. After implementation, run verification:
   npm run lint && npx tsc --noEmit && npm run build && npm test

7. If verification fails, fix the issues and re-run. Maximum 5 attempts.
   If still failing after 5 attempts, output: FAILED_AFTER_5_ATTEMPTS
   and stop.

8. Once verification passes, commit all changes:
   git add -A
   git commit with a message: "<identifier>: <short description>"

9. Push the branch:
   git push -u origin agent/<identifier-lowercase>

10. Create a draft PR using gh:
    gh pr create --draft --title "<identifier>: <title>" --body "..."
    Include in the PR body: what changed, why, how to verify,
    and the Linear issue link.

11. Output the PR URL on the final line as:
    PR_URL: <url>
PROMPT_EOF

# ── Pre-flight checks ─────────────────────────────────────────
echo "==> Auto-compound agent starting at $(date)"
echo "    Repo: $REPO_DIR"
echo "    Budget: \$${BUDGET}"
echo "    Log: $LOG_FILE"

mkdir -p "$LOG_DIR"

cd "$REPO_DIR"

# Ensure we're on main and up to date
git checkout main 2>/dev/null || {
  echo "ERROR: Failed to checkout main."
  exit 1
}

git pull --ff-only origin main 2>/dev/null || {
  echo "ERROR: Failed to pull latest main. Resolve conflicts first."
  exit 1
}

# Verify clean working tree
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Working tree is dirty. Commit or stash changes first."
  git status --short
  exit 1
fi

echo "    Git: on main, clean, up to date."

# ── Dry-run exit ───────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "[dry-run] Would invoke claude with:"
  echo "  --append-system-prompt (${#AGENT_PROMPT} chars)"
  echo "  --dangerously-skip-permissions"
  echo "  --max-budget-usd $BUDGET"
  echo ""
  echo "--- PROMPT PREVIEW ---"
  echo "$AGENT_PROMPT"
  echo "--- END PREVIEW ---"
  exit 0
fi

# ── Invoke Claude ──────────────────────────────────────────────
echo "==> Invoking Claude agent..."

EXIT_CODE=0
claude -p "Begin the nightly auto-compound workflow. Follow the system prompt instructions step by step." \
  --append-system-prompt "$AGENT_PROMPT" \
  --dangerously-skip-permissions \
  --max-budget-usd "$BUDGET" \
  2>&1 | tee "$LOG_FILE" || EXIT_CODE=$?

# ── Parse output ───────────────────────────────────────────────
if grep -q "NO_ELIGIBLE_ISSUE" "$LOG_FILE" 2>/dev/null; then
  echo ""
  echo "==> No eligible issue found in Linear. Nothing to do."
  git checkout main 2>/dev/null
  exit 0
fi

if grep -q "FAILED_AFTER_5_ATTEMPTS" "$LOG_FILE" 2>/dev/null; then
  echo ""
  echo "==> Agent failed after 5 attempts. Check log: $LOG_FILE"
  git checkout main 2>/dev/null
  exit 1
fi

PR_URL=$(grep "^PR_URL:" "$LOG_FILE" 2>/dev/null | head -1 | sed 's/^PR_URL: *//' || true)
if [[ -n "$PR_URL" ]]; then
  echo ""
  echo "==> Draft PR created: $PR_URL"
fi

# ── Cleanup ────────────────────────────────────────────────────
echo "==> Returning to main branch..."
git checkout main 2>/dev/null || true

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "==> Agent exited with code $EXIT_CODE. Check log: $LOG_FILE"
  exit 1
fi

echo "==> Auto-compound agent finished at $(date)"
