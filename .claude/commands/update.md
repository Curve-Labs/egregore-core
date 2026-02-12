Update local Egregore environment — sync framework from upstream, pull repos, merge MCP config.

## What to do

1. **Sync framework from upstream** (Curve-Labs/egregore-core)
2. **Run `/pull`** (smart sync all repos)
3. **Merge shared MCPs** from `mcp.shared.json` into local `.mcp.json`
4. Show what changed
5. Remind to restart if MCPs changed

## Step 1: Framework sync

Egregore is a framework — updates come from upstream, not from your own repo's history.

```bash
# Ensure upstream remote exists (no-op if already there)
git remote add upstream https://github.com/Curve-Labs/egregore-core.git 2>/dev/null || true

# Fetch latest upstream
git fetch upstream main --quiet

# Check what would change before applying
DIFF=$(git diff HEAD -- bin/ .claude/commands/ CLAUDE.md skills/ 2>/dev/null || true)
UPSTREAM_DIFF=$(git diff HEAD...upstream/main -- bin/ .claude/commands/ CLAUDE.md skills/ 2>/dev/null || true)

# If there are upstream changes, apply them
if [ -n "$UPSTREAM_DIFF" ]; then
  git checkout upstream/main -- bin/ .claude/commands/ CLAUDE.md skills/
  # Show what changed
  git diff --stat HEAD
fi
```

**Framework paths synced:** `bin/`, `.claude/commands/`, `CLAUDE.md`, `skills/`
**Never touched:** `egregore.json`, `.env`, `memory/`, `.egregore-state.json`, `.mcp.json`

If framework files changed, stage and commit them:
```bash
git add bin/ .claude/commands/ CLAUDE.md skills/
git commit -m "Update Egregore framework from upstream"
```

## Step 2: Pull repos

Run `/pull` logic (sync develop, rebase working branch, pull memory).

## Step 3: MCP config merging

```bash
# Read mcp.shared.json (repo) and .mcp.json (local)
# For each server in shared:
#   - If not in local: add it (new)
#   - If in local: keep local version (unchanged)
# Personal MCPs in local but not in shared: keep them
```

## Files

- `mcp.shared.json` — shared MCPs (committed to repo)
- `.mcp.json` — local config (gitignored, personal + shared merged)

## Example

```
> /update

Syncing framework from upstream...
  bin/session-start.sh       | 12 +++---
  .claude/commands/update.md | 38 +++++++++++++---
  skills/reflect/prompt.md   |  4 +-
  3 files changed, 32 insertions(+), 22 deletions(-)
  ✓ Framework updated and committed

Pulling...
  [memory]    ✓ 3 new commits
  [egregore]  ✓ 1 new commit
  [tristero]  ✓ current

Updating MCP config...
  + neo4j (new)
  = telegram (unchanged)
  · supabase (yours, kept)

⚠ MCP config changed — restart Claude Code to load neo4j
```

## If framework is already current

```
Syncing framework from upstream...
  ✓ Already up to date
```

## If no MCP changes

```
Updating MCP config...
  = neo4j (unchanged)
  = telegram (unchanged)
  · supabase (yours, kept)

✓ No restart needed
```

## Next

Restart Claude Code if MCPs changed, then `/activity` to see what's new.
