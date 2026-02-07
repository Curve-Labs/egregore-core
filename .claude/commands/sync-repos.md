Smart sync of all Egregore repos. Fetches first, only pulls if behind.

## Repos to sync

- `../curve-labs-memory` — shared knowledge
- `../tristero` — if exists
- `../lace` — if exists
- Current repo (curve-labs-core)

## Execution

For each repo, run these commands:

```bash
# 1. Fetch (always)
git -C /path/to/repo fetch origin --quiet

# 2. Compare local vs remote
LOCAL=$(git -C /path/to/repo rev-parse HEAD)
REMOTE=$(git -C /path/to/repo rev-parse origin/main)

# 3. Only pull if different
if [ "$LOCAL" != "$REMOTE" ]; then
  git -C /path/to/repo pull origin main --quiet
  # Count commits behind
  BEHIND=$(git -C /path/to/repo rev-list HEAD..origin/main --count)
fi
```

**For curve-labs-core**: sync the `develop` branch instead of main:
```bash
# Sync develop (not main)
git fetch origin --quiet
git checkout develop --quiet && git pull origin develop --quiet && git checkout - --quiet
# If on dev/* branch, rebase onto develop
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" == dev/* ]]; then
  git rebase develop --quiet || (git rebase --abort && git merge develop -m "Sync with develop")
fi
```

Use absolute paths with `git -C` to avoid permission prompts.

## Output format

```
Syncing Egregore repos...

  curve-labs-memory  ↓ 3 commits → pulled
  tristero           ✓ up to date
  lace               ✓ up to date
  curve-labs-core    ↓ 1 commit → pulled

Synced. Run /activity to see what's new.
```

## Rules

- Use `git -C /absolute/path` — no `cd` commands
- Fetch ALL repos first (parallel if possible), then compare/pull
- Show commit count when pulling
- Skip repos that don't exist (no error)
