Pull upstream updates from Curve-Labs/egregore-core into your fork.

New commands, bug fixes, and improvements ship through egregore-core. Run this to get them.

## What to do

1. Ensure `upstream` remote exists pointing to `https://github.com/Curve-Labs/egregore-core.git`
2. Fetch upstream
3. Compare: count commits between current HEAD and upstream/main
4. If nothing new → say "Already up to date!" and stop
5. Stash local changes if any
6. Check out main, merge upstream/main, push to origin
7. Return to original branch, rebase onto main, unstash
8. Show what changed

## Execution

```bash
REPO_DIR="$(git rev-parse --show-toplevel)"
cd "$REPO_DIR"

# 1. Add upstream if missing
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/Curve-Labs/egregore-core.git
fi

# 2. Fetch
git fetch upstream --quiet

# 3. Check for new commits
NEW_COMMITS=$(git rev-list HEAD..upstream/main --count 2>/dev/null || echo "0")
CURRENT_SHA=$(git rev-parse --short HEAD)
UPSTREAM_SHA=$(git rev-parse --short upstream/main)
```

If `$NEW_COMMITS` is 0, output "Already up to date!" and stop.

Otherwise, show:
```
Checking for updates...
  upstream: Curve-Labs/egregore-core
  current:  $CURRENT_SHA
  latest:   $UPSTREAM_SHA

  $NEW_COMMITS new commits since your last sync.
```

Then continue:

```bash
# 4. Save current state
CURRENT_BRANCH=$(git branch --show-current)
STASHED="false"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  git stash push -m "update-egregore auto-stash" --quiet
  STASHED="true"
fi

# 5. Merge upstream into main
git checkout main --quiet
BEFORE_SHA=$(git rev-parse HEAD)
git merge upstream/main --no-edit --quiet
```

If merge fails (conflict), output the conflicting files and tell the user to resolve manually. Run `git merge --abort` and restore their branch.

If merge succeeds:

```bash
# 6. Push updated main to fork
git push origin main --quiet

# 7. Return to working branch
git checkout "$CURRENT_BRANCH" --quiet
if [[ "$CURRENT_BRANCH" == dev/* ]] || [[ "$CURRENT_BRANCH" == feature/* ]]; then
  git rebase main --quiet 2>/dev/null || (git rebase --abort 2>/dev/null; git merge main --no-edit --quiet)
fi

# 8. Restore stashed changes
if [ "$STASHED" = "true" ]; then
  git stash pop --quiet 2>/dev/null || true
fi

# 9. Show what changed
git diff --stat "$BEFORE_SHA"..HEAD
```

## Output

```
Checking for updates...
  upstream: Curve-Labs/egregore-core
  current:  abc1234
  latest:   def5678

  12 new commits since your last sync.

Updating...
  ✓ Merged upstream changes into main
  ✓ Pushed to your fork
  ✓ Rebased dev/oz/2026-02-08-session onto main

What changed:
  CLAUDE.md                    | 15 +++--
  bin/session-start.sh         | 42 +++++++---
  .claude/commands/reflect.md  | 28 +++++++

Done. You're on the latest version.
```

### Already up to date

```
Checking for updates...
  upstream: Curve-Labs/egregore-core

  ✓ Already up to date!
```

### Merge conflict

```
Checking for updates...
  12 new commits available.

Updating...
  ✗ Merge conflict in egregore.json

  Aborted merge. Your repo is unchanged.
  To resolve manually:
    git checkout main
    git merge upstream/main
    # fix conflicts
    git push origin main
```

## Rules

- Never force-push
- Never modify files outside the egregore repo
- If merge conflicts, abort cleanly and let the user resolve
- Always return to the user's original branch
