Sync this repo to the public egregore-core repo. One-way: curve-labs-core → egregore-core.

Arguments: $ARGUMENTS (Optional: "dry" for dry-run, "diff" to just show what changed)

## What this does

Rsync everything from this repo (curve-labs-core) to the sibling egregore-core repo, excluding personal/generated files. Then optionally commit and push.

The two repos should be identical software — only memory and personal state differ.

## Prerequisites

Both repos must exist as siblings:
```
../curve-labs-core/   ← you are here (development)
../egregore-core/     ← public distribution
```

## Step 1: Validate

```bash
# Check egregore-core exists
CORE_DIR="$(cd "$(dirname "$(git rev-parse --show-toplevel)")"/egregore-core 2>/dev/null && pwd)"
if [ -z "$CORE_DIR" ]; then
  echo "Error: ../egregore-core not found. Clone it first."
  exit 1
fi
```

If `$ARGUMENTS` is empty or not provided, assume full sync (not dry-run).

## Step 2: Rsync

```bash
rsync -av --delete \
  --exclude='.git' \
  --exclude='.git/' \
  --exclude='memory' \
  --exclude='.env' \
  --exclude='.env.local' \
  --exclude='.DS_Store' \
  --exclude='.egregore-state.json' \
  --exclude='egregore.json' \
  --exclude='.mcp.json' \
  --exclude='mcp.json' \
  --exclude='mcp.shared.*.json' \
  --exclude='node_modules' \
  --exclude='__pycache__' \
  --exclude='.claude/settings.local.json' \
  --exclude='.playwright-mcp' \
  --exclude='api' \
  --exclude='ascii-oracle' \
  --exclude='blog' \
  --exclude='telegram-bot' \
  --exclude='tests' \
  --exclude='data' \
  --exclude='packages' \
  --exclude='Dockerfile' \
  --exclude='TELEGRAM_BOT_PLAN.md' \
  "$(git rev-parse --show-toplevel)/" \
  "$CORE_DIR/"
```

**If `$ARGUMENTS` is "dry"**: Add `--dry-run` to rsync. Show what would change, don't actually sync.

## Step 3: Show diff

```bash
cd "$CORE_DIR"
git status
git diff --stat
```

**If `$ARGUMENTS` is "diff"**: Stop here. Just show the diff, don't commit.

## Step 4: Commit and push

```bash
cd "$CORE_DIR"
git add -A
git commit -m "Sync from curve-labs-core: $(date +%Y-%m-%d)"
git push origin main
```

## Output

### Full sync
```
> /sync-public

Syncing curve-labs-core → egregore-core...

  rsync: 14 files changed, 3 deleted

  Changed:
    .claude/commands/activity.md
    .claude/commands/ask.md
    bin/graph.sh
    CLAUDE.md
    ...

  Committing to egregore-core...
    ✓ Committed: "Sync from curve-labs-core: 2026-02-07"
    ✓ Pushed to origin/main

Done. egregore-core is up to date.
```

### Dry run
```
> /sync-public dry

Dry run — showing what would change:

  Would update: .claude/commands/activity.md
  Would update: bin/graph.sh
  Would delete: old-file.md

  3 files would change. Run /sync-public to apply.
```

### Diff only
```
> /sync-public diff

Current diff between repos:

  .claude/commands/activity.md | 12 ++---
  bin/graph.sh                 |  3 +-

  2 files differ.
```

## Rules

- **Never sync**: `.git/`, `memory/`, `.env`, `.egregore-state.json`, `egregore.json`, `.mcp.json`, `mcp.json`, `mcp.shared.*.json`, `node_modules/`, `__pycache__/`, `.claude/settings.local.json`, `.playwright-mcp/`, `api/`, `ascii-oracle/`, `blog/`, `telegram-bot/`, `tests/`, `data/`, `packages/`, `Dockerfile`, `TELEGRAM_BOT_PLAN.md`
- **Always sync everything else** — commands, bin scripts, CLAUDE.md, README.md, settings.json, start scripts, `.env.example`, etc.
- The `--delete` flag ensures files removed from curve-labs-core are also removed from egregore-core
- Always show the diff before committing
- Commit message includes the date for traceability
