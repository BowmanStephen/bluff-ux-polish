#!/usr/bin/env bash
# auto-compound.sh — Nightly agent that picks the top Linear issue and implements it.
# Creates a feature branch, implements the change, and opens a draft PR.
#
# Usage: ./scripts/auto-compound.sh [--dry-run]
#   --dry-run: Query Linear and print the prompt, but skip the Claude invocation.
#
# Requires: ~/.config/linear/api-key (Personal API key from Linear settings)
# Designed to run after daily-compound-review.sh (so CLAUDE.md is fresh).

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_DIR/scripts/logs"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/auto-compound-${TODAY}.log"
BUDGET="1.00"
LINEAR_PROJECT="Rota Fortunae"
LINEAR_API_KEY_FILE="$HOME/.config/linear/api-key"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] Will query Linear and print prompt, then exit."
fi

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

# ── Query Linear API ──────────────────────────────────────────
echo "==> Querying Linear for Agent-Safe issues..."

if [[ ! -f "$LINEAR_API_KEY_FILE" ]]; then
  echo "ERROR: Linear API key not found at $LINEAR_API_KEY_FILE"
  echo "       Generate one at: Linear → Settings → Account → API"
  exit 1
fi

LINEAR_API_KEY=$(cat "$LINEAR_API_KEY_FILE")

ISSUE_JSON=$(LINEAR_API_KEY="$LINEAR_API_KEY" LINEAR_PROJECT="$LINEAR_PROJECT" python3 << 'PYEOF'
import json, urllib.request, os, sys

api_key = os.environ["LINEAR_API_KEY"]
project = os.environ["LINEAR_PROJECT"]

query = """
{
  issues(
    filter: {
      project: { name: { eq: "%s" } }
      labels: { name: { eq: "Agent-Safe" } }
      state: { type: { eq: "backlog" } }
    }
    orderBy: priority
    first: 10
  ) {
    nodes {
      identifier
      title
      description
      url
      estimate
      priority
    }
  }
}
""" % project

req = urllib.request.Request(
    "https://api.linear.app/graphql",
    data=json.dumps({"query": query}).encode(),
    headers={
        "Authorization": api_key,
        "Content-Type": "application/json"
    }
)

try:
    resp = urllib.request.urlopen(req)
    data = json.loads(resp.read())
except Exception as e:
    print("API_ERROR: %s" % str(e), file=sys.stderr)
    sys.exit(1)

errors = data.get("errors")
if errors:
    print("API_ERROR: %s" % errors[0].get("message", "Unknown"), file=sys.stderr)
    sys.exit(1)

nodes = data.get("data", {}).get("issues", {}).get("nodes", [])

# Filter: must have an estimate, and estimate must be <= 3
eligible = [n for n in nodes if n.get("estimate") and n["estimate"] <= 3]

if not eligible:
    print("NO_ELIGIBLE_ISSUE")
else:
    # Already sorted by priority from the API (1=Urgent first)
    print(json.dumps(eligible[0]))
PYEOF
) || {
  echo "ERROR: Linear API query failed. Check your API key."
  exit 1
}

if [[ "$ISSUE_JSON" == "NO_ELIGIBLE_ISSUE" ]]; then
  echo "    No eligible issues found in Linear. Nothing to do."
  exit 0
fi

# Parse issue fields
ISSUE_ID=$(echo "$ISSUE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['identifier'])")
ISSUE_TITLE=$(echo "$ISSUE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['title'])")
ISSUE_DESC=$(echo "$ISSUE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description','No description provided.'))")
ISSUE_URL=$(echo "$ISSUE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['url'])")
BRANCH_NAME="agent/$(echo "$ISSUE_ID" | tr '[:upper:]' '[:lower:]')"

echo "    Found: $ISSUE_ID — $ISSUE_TITLE"
echo "    Branch: $BRANCH_NAME"

# ── Build Agent Prompt ────────────────────────────────────────
read -r -d '' AGENT_PROMPT << PROMPT_EOF || true
You are an autonomous nightly agent for the bluff-ux-polish project.

YOUR ASSIGNED ISSUE:
- Identifier: $ISSUE_ID
- Title: $ISSUE_TITLE
- URL: $ISSUE_URL
- Description:
$ISSUE_DESC

WORKFLOW:
1. Create a feature branch: git checkout -b $BRANCH_NAME

2. Implement the changes described above. Follow the project's CLAUDE.md constraints strictly.
   DO NOT modify: .github/, package.json, package-lock.json, .env*,
   CLAUDE.md, scripts/, next.config.*

3. After implementation, run verification:
   npm run lint && npx tsc --noEmit && npm run build && npm test

4. If verification fails, fix the issues and re-run. Maximum 5 attempts.
   If still failing after 5 attempts, output: FAILED_AFTER_5_ATTEMPTS
   and stop.

5. Once verification passes, commit all changes:
   git add -A
   git commit with a message: "$ISSUE_ID: <short description>"

6. Push the branch:
   git push -u origin $BRANCH_NAME

7. Create a draft PR using gh:
   gh pr create --draft --title "$ISSUE_ID: $ISSUE_TITLE" --body "..."
   Include in the PR body: what changed, why, how to verify,
   and the Linear issue link: $ISSUE_URL

8. Output the PR URL on the final line as:
   PR_URL: <url>
PROMPT_EOF

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
echo "==> Invoking Claude agent for $ISSUE_ID..."

EXIT_CODE=0
claude -p "Begin the nightly auto-compound workflow. Implement the assigned issue step by step." \
  --append-system-prompt "$AGENT_PROMPT" \
  --dangerously-skip-permissions \
  --max-budget-usd "$BUDGET" \
  2>&1 | tee "$LOG_FILE" || EXIT_CODE=$?

# ── Parse output ───────────────────────────────────────────────
if grep -q "FAILED_AFTER_5_ATTEMPTS" "$LOG_FILE" 2>/dev/null; then
  echo ""
  echo "==> Agent failed after 5 attempts on $ISSUE_ID. Check log: $LOG_FILE"
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
