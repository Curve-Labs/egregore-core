Pull latest for current repo and shared memory.

**Note:** `/activity` auto-syncs. Use `/pull` only when you need to sync without viewing activity.

## What to do

1. Sync develop branch with remote
2. If on a `dev/*` working branch, rebase onto develop (fallback: merge)
3. Check memory symlink exists — if not, derive directory from `egregore.json` and create symlink
4. Pull memory repo via symlink

**Does NOT sync sibling repos.** Use `/sync-repos` for that.

## Execution

```bash
# 1. Update local develop ref without switching branches (safe for concurrent sessions)
git fetch origin develop:develop --quiet

# 2. If on a working branch, rebase onto develop
CURRENT=$(git branch --show-current)
if [[ "$CURRENT" == dev/* ]]; then
  git rebase develop --quiet || (git rebase --abort && git merge develop -m "Sync with develop")
fi

# 3. Memory — derive directory from egregore.json, never hardcode
MEMORY_DIR=$(basename "$(jq -r '.memory_repo' egregore.json)" .git)
if [ ! -L memory ]; then
  ln -s "../$MEMORY_DIR" memory
fi
git -C memory pull origin main --quiet
```

## Output

```
Pulling...
  develop        ↓ 3 commits → synced
  dev/oz/...     ✓ rebased onto develop
  memory         ↓ 2 commits → pulled

For sibling repos (tristero, lace): /sync-repos
```
