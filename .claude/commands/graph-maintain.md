# /graph-maintain — Graph Maintenance Cycle

Run one scan-detect-act cycle on the knowledge graph. Composable with `/loop` for recurring maintenance (e.g. `/loop 1h /graph-maintain`).

## When to invoke

**Trigger phrases**: "maintain the graph", "clean up the graph", "graph hygiene", "fix graph issues", "graph health", "run maintenance"

**Not this command**:
- One-time full diagnostic → `/graph-diagnostic`
- Environment health check → `/checkup`
- File→graph sync → `bash bin/sync-graph.sh`

## Instructions

Run one maintenance cycle. Each cycle: scan → auto-fix safe patterns → present suggestions → flag the rest → report.

### Step 1: Scan

```bash
SCAN=$(bash bin/graph-maintenance.sh scan)
```

Parse the JSON result. It contains `findings` (7 patterns) and `health` metrics.

### Step 2: Auto-fix

For each auto-fixable pattern with items:

**Stale handoffs** (pending > 30 days):
```bash
bash bin/graph-maintenance.sh fix stale-handoffs
```
Report: `✦ Resolved {N} stale handoffs`

**Quest decay** (active quests with no artifacts > 30 days):
For each quest found:
```bash
bash bin/graph-maintenance.sh fix quest-decay "{quest-id}"
```
Report: `✦ Paused {N} dormant quests: {ids}`

**Date type inconsistencies** (datetime strings instead of date):
```bash
bash bin/graph-maintenance.sh fix date-type-mix
```
Report: `✦ Migrated {N} date fields to proper date type`

### Step 3: Suggest

For patterns with action "suggest", present to the user via AskUserQuestion:

**Disconnected artifacts** — artifacts not linked to any quest. For each, ask: "Link {artifact title} to a quest?" with options being active quest IDs, or "skip".

**Duplicate persons** — potential merge candidates. For each, ask: "Merge {variants}?" with the primary name as default.

If the user approves:
```bash
bash bin/graph-maintenance.sh fix disconnected-artifacts "{artifact-id}" "{quest-id}"
bash bin/graph-maintenance.sh fix duplicate-persons "{keep-name}" "{remove-name}"
```

### Step 4: Flag

List remaining issues (ghost artifacts, orphaned sessions) as informational — don't auto-fix these:

```
⚠ {N} ghost artifacts (no filePath): {ids}
⚠ {N} orphaned sessions (no relationships): {ids}
```

### Step 5: Report

Show a compact summary:

```
┌ Graph Maintenance ────────────────────────┐
│ ✦ Fixed: {N} stale handoffs               │
│ ✦ Fixed: {N} dormant quests paused        │
│ ✦ Fixed: {N} date types migrated          │
│ ◇ Suggested: {N} artifact links           │
│ ◇ Suggested: {N} person merges            │
│ ⚠ Flagged: {N} ghosts, {N} orphans        │
├───────────────────────────────────────────┤
│ Nodes: {N}  Edges: {N}  Orphan rate: {N}% │
└───────────────────────────────────────────┘
```

### Step 6: Telemetry

```bash
bash bin/telemetry.sh emit "command" '{"command":"graph-maintain"}' 2>/dev/null &
```

## Notes

- Scan is always read-only and safe to repeat
- Auto-fixes are idempotent — running twice produces the same result
- When composed with `/loop`, each cycle should show fewer findings than the last
- The suggest step requires user input — when running via `/loop`, skip suggestions and only auto-fix + flag
