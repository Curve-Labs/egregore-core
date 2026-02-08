Pull latest for current repo and shared memory.

**Note:** `/activity` auto-syncs. Use `/pull` only when you need to sync without viewing activity.

## What to do

1. Stash uncommitted changes if any
2. Pull develop from origin
3. Pop stash
4. Pull memory repo via symlink

**Does NOT sync sibling repos.** Use `/sync-repos` for that.

## Execution

```bash
# 1. Stash if dirty
STASHED="false"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  git stash push -m "pull auto-stash" --quiet
  STASHED="true"
fi

# 2. Pull develop
git fetch origin --quiet
git pull origin develop --quiet

# 3. Restore stash
if [ "$STASHED" = "true" ]; then
  git stash pop --quiet || echo "Warning: stash pop had conflicts — resolve manually"
fi

# 4. Memory (via symlink)
git -C memory pull origin main --quiet
```

## Output

```
Pulling...
  develop        ↓ 3 commits → synced
  memory         ↓ 2 commits → pulled

For sibling repos (tristero, lace): /sync-repos
```
