#!/usr/bin/env bash
# daily-compound-review.sh — Extract learnings from recent Claude Code sessions
# and append them to CLAUDE.md. Designed to run nightly via cron or launchd.
#
# Usage: ./scripts/daily-compound-review.sh [--dry-run]
#   --dry-run: Print what would be appended without modifying files or committing

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_MD="$REPO_DIR/CLAUDE.md"
CLAUDE_DIR="$HOME/.claude"
HISTORY_FILE="$CLAUDE_DIR/history.jsonl"
PROJECTS_DIR="$CLAUDE_DIR/projects"
LOOKBACK_HOURS=24
MAX_CONTENT_CHARS=50000
TODAY=$(date +%Y-%m-%d)
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] No files will be modified."
fi

# ── Stage 1: Find recent sessions ─────────────────────────────
echo "==> Stage 1: Scanning history for sessions in the last ${LOOKBACK_HOURS}h..."

if [[ ! -f "$HISTORY_FILE" ]]; then
  echo "ERROR: history.jsonl not found at $HISTORY_FILE"
  exit 1
fi

SESSION_IDS=$(HISTORY_FILE="$HISTORY_FILE" LOOKBACK_HOURS="$LOOKBACK_HOURS" python3 << 'PYEOF'
import json, time, os

history_file = os.environ["HISTORY_FILE"]
lookback_ms = int(os.environ["LOOKBACK_HOURS"]) * 3600 * 1000

with open(history_file) as f:
    lines = f.readlines()

now_ms = int(time.time() * 1000)
cutoff = now_ms - lookback_ms
seen = set()

for line in lines:
    try:
        entry = json.loads(line)
    except json.JSONDecodeError:
        continue
    ts = entry.get("timestamp", 0)
    sid = entry.get("sessionId", "")
    if ts > cutoff and sid and sid not in seen:
        seen.add(sid)
        print(sid)
PYEOF
) || true

if [[ -z "$SESSION_IDS" ]]; then
  echo "Nothing to review — no sessions found in the last ${LOOKBACK_HOURS}h."
  exit 0
fi

SESSION_COUNT=$(echo "$SESSION_IDS" | wc -l | tr -d ' ')
echo "    Found $SESSION_COUNT session(s)."

# ── Stage 2: Extract conversation text ─────────────────────────
echo "==> Stage 2: Extracting conversation content..."

CONTENT=$(SESSION_IDS="$SESSION_IDS" PROJECTS_DIR="$PROJECTS_DIR" MAX_CONTENT_CHARS="$MAX_CONTENT_CHARS" python3 << 'PYEOF'
import json, os, glob

session_ids = os.environ["SESSION_IDS"].strip().split("\n")
projects_dir = os.environ["PROJECTS_DIR"]
max_chars = int(os.environ["MAX_CONTENT_CHARS"])

total = ""

for sid in session_ids:
    if not sid.strip():
        continue
    # Search all project directories for this session file
    pattern = os.path.join(projects_dir, "*", f"{sid.strip()}.jsonl")
    matches = glob.glob(pattern)
    if not matches:
        continue
    filepath = matches[0]

    try:
        with open(filepath) as f:
            lines = f.readlines()
    except (IOError, OSError):
        continue

    for line in lines:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = entry.get("type", "")
        if msg_type not in ("user", "assistant"):
            continue

        message = entry.get("message", {})
        content = message.get("content", "")
        role = message.get("role", msg_type)

        texts = []
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    texts.append(block.get("text", ""))

        for text in texts:
            text = text.strip()
            if not text:
                continue
            total += f"\n[{role}]: {text}\n"

        if len(total) >= max_chars:
            total = total[:max_chars]
            break

    if len(total) >= max_chars:
        break

print(total)
PYEOF
) || true

if [[ -z "$CONTENT" || ${#CONTENT} -lt 50 ]]; then
  echo "No content to analyze — sessions had no extractable text."
  exit 0
fi

echo "    Extracted ${#CONTENT} characters from conversations."

# ── Stage 3: Feed to Claude for extraction ─────────────────────
echo "==> Stage 3: Sending to Claude for learning extraction..."

SYSTEM_PROMPT='You are reviewing Claude Code conversation threads from the last 24 hours.
Extract CONCRETE, ACTIONABLE learnings for a project CLAUDE.md file.

Output under ONLY these headings (skip any heading with zero items):
### Gotchas     — things that broke, surprised, or wasted time
### Patterns    — approaches that worked well, repeat these
### Decisions   — choices made and their reasoning
### Context     — project facts a future AI session needs to know

RULES:
- Each item: one line, imperative voice, specific
- Skip generic advice or obvious things
- Maximum 15 items total
- If ZERO genuine learnings, respond with exactly: NO_NEW_LEARNINGS'

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Would send ${#CONTENT} chars to Claude with extraction prompt."
  echo "[dry-run] Skipping Claude call. Showing first 500 chars of content:"
  echo "${CONTENT:0:500}"
  exit 0
fi

LEARNINGS=$(echo "$CONTENT" | claude -p \
  --system-prompt "$SYSTEM_PROMPT" \
  --dangerously-skip-permissions \
  --max-budget-usd 0.50 2>/dev/null) || {
  echo "ERROR: Claude CLI call failed."
  exit 1
}

if [[ -z "$LEARNINGS" || "$LEARNINGS" == "NO_NEW_LEARNINGS" ]]; then
  echo "No new learnings extracted — nothing to append."
  exit 0
fi

echo "    Learnings extracted successfully."

# ── Stage 4: Append to CLAUDE.md ───────────────────────────────
echo "==> Stage 4: Appending to CLAUDE.md..."

SECTION=$(cat << EOF

## Compound Review: $TODAY

$LEARNINGS
EOF
)

if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "# CLAUDE.md" > "$CLAUDE_MD"
fi

echo "$SECTION" >> "$CLAUDE_MD"
echo "    Appended review section for $TODAY."

# ── Stage 5: Git commit + push ─────────────────────────────────
echo "==> Stage 5: Committing and pushing..."

cd "$REPO_DIR"
git add CLAUDE.md
git commit -m "$(cat <<EOF
compound: daily review $TODAY

Auto-extracted learnings from $SESSION_COUNT Claude Code session(s).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" 2>/dev/null || {
  echo "WARNING: git commit failed (maybe no changes?). Skipping push."
  exit 0
}

git push origin main 2>/dev/null || {
  echo "WARNING: git push failed. Commit is local only."
  exit 1
}

echo "==> Done! Compound review for $TODAY committed and pushed."
