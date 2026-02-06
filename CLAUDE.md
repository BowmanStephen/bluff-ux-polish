# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack
- Next.js 16 (App Router, `src/` directory)
- React 19, TypeScript (strict mode)
- Tailwind CSS v4 (PostCSS plugin, no `tailwind.config` — theming via `@theme inline` in `globals.css`)
- Vitest + Testing Library for tests
- npm

## Commands
```bash
npm run dev          # Start dev server
npm run build        # Production build
npm run lint         # ESLint (next/core-web-vitals + typescript)
npx tsc --noEmit     # Typecheck (CI runs this separately from build)
npm test             # Run tests once (Vitest)
npm run test:watch   # Run tests in watch mode
```

CI runs all four checks in order: lint → typecheck → build → test.

## Architecture

Single-page Next.js App Router app. All source code lives under `src/`.

- `src/app/` — App Router: `layout.tsx` (root layout with fonts, skip-to-content), `page.tsx` (home), `globals.css` (Tailwind v4 theme)
- `src/app/error.tsx` / `global-error.tsx` — Error boundaries (global-error uses inline styles, no CSS dependency)
- `src/app/manifest.ts`, `robots.ts`, `sitemap.ts` — PWA manifest + SEO config via Next.js dynamic routes
- `src/app/__tests__/` — Tests colocated via `__tests__` folders alongside routes

No `src/components/`, `src/lib/`, or `src/hooks/` directories yet — create them as needed.

**Path alias:** `@/` → `./src/` (configured in both `tsconfig.json` and `vitest.config.ts`)

## Conventions
- Components split at ~150 lines
- Build UI in blocks (nav → hero → features), not full pages
- Tailwind for all styling — no CSS modules
- Dark mode via `prefers-color-scheme` media query (CSS custom properties in `globals.css`)
- JSON-LD structured data added to pages for SEO

## Testing
- Vitest with jsdom environment, `@testing-library/react`, `@testing-library/jest-dom`
- Tests go in `__tests__/` folders next to the code they test (e.g., `src/app/__tests__/page.test.tsx`)
- `next/image` must be mocked in tests (see existing mock in `page.test.tsx`)
- Run a single test file: `npx vitest src/app/__tests__/page.test.tsx`
- Setup file: `vitest.setup.ts` (imports jest-dom matchers)

## Scripts
- `scripts/daily-compound-review.sh` — Nightly script that extracts learnings from Claude Code sessions and appends them below.
- `scripts/auto-compound.sh` — Nightly agent that picks the top `Agent-Safe` Linear issue and implements it via draft PR. Run with `--dry-run` to preview without invoking Claude.
- `scripts/nightly-wrapper.sh` — Orchestrator that runs review then auto-compound sequentially. Triggered by launchd at 10:30 PM. Run with `--dry-run` to preview both stages.

## Agent Constraints

These rules govern the autonomous auto-compound agent. They are non-negotiable.

### Scope Limits
- Agent ONLY picks issues labeled `Agent-Safe` in Linear
- Agent ONLY picks issues estimated at **3 points or fewer** (skip unestimated issues)
- Agent ONLY works on this repo (`bluff-ux-polish`) — no cross-repo changes

### Branch Rules
- Agent ALWAYS works on a feature branch (`agent/<issue-identifier>`)
- Agent NEVER commits directly to `main`
- Agent NEVER force-pushes

### PR Rules
- Agent creates **draft PRs only** — never ready-for-review or auto-merge
- PR title includes the Linear issue identifier (e.g., `STE-XXX: ...`)
- PR body includes what was changed, why, and how to verify

### Iteration Cap
- Maximum **5 edit-test cycles** per run before the agent gives up
- If build/lint/typecheck fails after 5 attempts, abandon the branch and log the failure

### File Restrictions — DO NOT MODIFY
- `.github/` — CI/CD workflows
- `package.json` / `package-lock.json` — no dependency changes
- `.env*` — environment files
- `CLAUDE.md` — only the review script appends here, not the agent
- `scripts/` — the agent doesn't modify its own automation scripts
- `next.config.*` — framework configuration

### Rollback Plan
- If the agent's PR fails CI: auto-close the PR, leave a comment explaining the failure
- If the agent cannot find an eligible issue: exit cleanly, log "no eligible issues"
- All agent activity is logged to `scripts/logs/auto-compound-<date>.log`

### Budget
- Maximum spend per run: **$1.00 USD** (via `--max-budget-usd`)
- If the budget is exhausted mid-task, commit whatever progress exists and note it in the PR

---

<!-- Compound review learnings are appended below this line -->

## Compound Review: 2026-02-05



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
