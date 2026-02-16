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

Excludes are read from `.syncignore` at the repo root (single source of truth). If the file is missing, abort with an error.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SYNCIGNORE="$REPO_ROOT/.syncignore"

if [ ! -f "$SYNCIGNORE" ]; then
  echo "Error: .syncignore not found. Cannot sync without exclude list."
  exit 1
fi

# Build --exclude flags from .syncignore (skip comments and blank lines)
EXCLUDE_FLAGS=""
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/#.*//' | xargs)"
  [ -z "$line" ] && continue
  EXCLUDE_FLAGS="$EXCLUDE_FLAGS --exclude='$line'"
done < "$SYNCIGNORE"

eval rsync -av --delete $EXCLUDE_FLAGS "$REPO_ROOT/" "$CORE_DIR/"
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

- **Excludes live in `.syncignore`** at the repo root. Edit that file to add/remove private paths. Never hardcode excludes in this command.
- **Always sync everything not in `.syncignore`** — commands, bin scripts, CLAUDE.md, README.md, settings.json, start scripts, `.env.example`, etc.
- The `--delete` flag ensures files removed from curve-labs-core are also removed from egregore-core
- Always show the diff before committing — **review it for anything that shouldn't be public**
- Commit message includes the date for traceability
- When adding new private directories or files to the repo, **always add them to `.syncignore`**
