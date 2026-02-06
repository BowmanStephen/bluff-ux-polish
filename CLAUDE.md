# Bluff UX Polish

## Stack
- Next.js 16 (App Router, `src/` directory)
- TypeScript
- Tailwind CSS v4
- npm

## Conventions
- Components split at ~150 lines
- Build UI in blocks (nav → hero → features), not full pages
- Tailwind for all styling — no CSS modules

## Scripts
- `scripts/daily-compound-review.sh` — Nightly script that extracts learnings from Claude Code sessions and appends them below.

---

<!-- Compound review learnings are appended below this line -->

## Compound Review: 2026-02-05



Based on this conversation, I can extract the learnings directly without needing to search files.

### Gotchas
- Linear MCP `create_issue_label` API cannot move existing labels into groups or update parent references — only UI drag-and-drop works for reorganizing labels into groups
- Linear MCP `create_issue_label` rejects duplicate label names even when trying to recreate at team level vs workspace level — delete the old one first
- `claude mcp add` defaults to project-level config (`~/.claude.json`) not global (`~/.claude/settings.json`) — use `--scope user` for global availability
- Linear Triage feature requires Business/Enterprise plan — verify plan-tier requirements before creating backlog items for feature configuration
- Plan mode blocks system-modifying commands — exit plan mode before attempting MCP setup or configuration changes
- Linear workspace-level labels don't appear in team-level label settings view — switch the dropdown filter to see them

### Patterns
- When configuring MCP servers: add via CLI, restart Claude Code, run `/mcp` to authenticate, then verify with a simple API call (list_teams/get_user)
- Prioritize Linear backlog by tackling 1-point Foundation/config items first (enable cycles, organize labels) to establish structure before building automations
- When API tools lack update/edit capabilities, guide the user through UI steps instead of attempting workarounds that create duplicates

### Decisions
- Set Linear cycles to 1-week duration with Monday start, no cooldown, 4 upcoming cycles, and auto-add started/completed issues — appropriate cadence for solo developer
- Organized Linear labels into two mutually exclusive groups: Type (Bug/Feature/Improvement) and Context (Work/Personal/Experiment/Life)
- Canceled STE-273 (Enable Triage) rather than leaving it in backlog after discovering it requires a higher-tier Linear plan

### Context
- Linear MCP uses HTTP transport (`https://mcp.linear.app/mcp`) with OAuth — no local process or API key needed
- Stephen's Linear workspace: team "Stephen Bowman", admin role, project "Rota Fortunae" with 4 milestone phases
- Linear MCP tools available: create/update/get issues, list issues, create labels, list labels, search docs, list teams, get user, list cycles — but NO update_label or team_settings tools
