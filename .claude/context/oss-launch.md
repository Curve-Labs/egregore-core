Egregore ships as one codebase with two modes, set by `mode` in `egregore.json`:

**Local mode** (`"mode": "local"`) — OSS. No API, no graph, no Telegram.
Installed via `npx create-egregore --local`. All core commands work
with filesystem only: `/reflect`, `/handoff`, `/quest`, `/ask`,
`/activity`, `/dashboard`, `/todo`, `/invite`. Memory is the source
of truth. Never mention `/connect`, graph, or API features in local
mode UI — it's a valid standalone experience, not a broken state.

**Connected mode** (`"mode": "connected"`) — Full features.
Installed via `npx create-egregore --token` or `npx create-egregore`
(interactive API flow). Graph, dashboard, notifications, hosted
workspaces all active. If graph is offline, show troubleshooting.

Mode detection: read `mode` from `egregore.json`. Fallback: if `mode`
is missing, check `api_url` — empty means local, set means connected.

Both modes live in the same codebase (CL/egregore-core → egregore-ai/egregore).
Changes are developed on develop branch. Connected code paths must never break.

Rules:
- NEVER remove existing graph/API/Supabase code paths.
- ADD `mode` checks in command specs: local mode skips graph/API calls silently.
- Commands in local mode: no "Graph offline" warnings, no "/connect" suggestions.
- Files = truth, graph = query layer on top.
- All changes must pass the existing test suite — connected mode unchanged.
