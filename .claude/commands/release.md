Merge develop into main. Maintainer only.

## What to do

1. **Verify maintainer**: Only oz can release
2. **Show summary**: What's on develop since last release
3. **Confirm** with the user
4. **Merge** develop → main (no fast-forward)
5. **Tag** the release
6. **Sync public** repo (egregore-core)
7. **Notify** team
8. **Clean up** merged working branches

## Step 1: Verify maintainer

```bash
git config user.name
```

Map to short name. If not oz: **"Only the maintainer can release. Ask oz to run /release."** Stop here.

## Step 2: Show what's on develop

```bash
git fetch origin --quiet
git log origin/main..origin/develop --oneline --no-merges
```

Also check for open PRs to develop:
```bash
gh pr list --base develop --state open --json number,title,author
```

If there are open PRs, warn: **"⚠ {N} open PRs to develop. Consider merging or closing them first."**

If develop is identical to main: **"Nothing to release — develop and main are in sync."** Stop here.

## Step 3: Confirm

Show the commit list and ask:
```
Release to main?

  abc1234 Update save command for develop workflow (oz)
  def5678 Add session-start script (oz)
  ghi9012 Fix onboarding for new orgs (cem)

  3 commits. Proceed? (y/n)
```

## Step 4: Merge

```bash
git checkout main && git pull origin main --quiet
git merge develop --no-ff -m "Release: $(date +%Y-%m-%d)"
git push origin main
```

## Step 5: Tag

```bash
git tag "release/$(date +%Y-%m-%d)" && git push origin --tags
```

If a tag for today already exists, append a counter: `release/2026-02-07-2`

## Step 6: Sync public repo

Run the `/sync-public` flow to update egregore-core with the new main.

## Step 7: Notify team

```bash
bash bin/notify.sh group "New release on main: [summary of changes]. Run /pull to update."
```

## Step 8: Clean up

Delete merged `dev/*` remote branches:
```bash
git branch -r --merged origin/main | grep 'origin/dev/' | sed 's|origin/||' | xargs -I{} git push origin --delete {}
```

Return to develop:
```bash
git checkout develop
```

## Example

```
> /release

Checking permissions...
  ✓ Maintainer: oz

Fetching latest...

Changes on develop since last release:
  abc1234 Update save command for develop workflow (oz)
  def5678 Add session-start script (oz)
  ghi9012 Fix onboarding for new orgs (cem)

  3 commits ready to release.

  ⚠ 1 open PR to develop: #16 "Bot analytics" by ali
  (This PR will NOT be included — only merged PRs are released.)

Release to main? (y/n)
> y

  Merging develop → main...
    ✓ Merged (no-ff)
    ✓ Pushed to origin/main
    ✓ Tagged: release/2026-02-07

  Syncing to egregore-core...
    ✓ Synced and pushed

  Notifying team...
    ✓ Sent to Egregore channel

  Cleaning up...
    ✓ Deleted 2 merged dev/* branches

Done. Main is updated. Team notified.
```

## Rules

- **Only oz can release** — enforced by checking git config user.name
- **Never fast-forward** — `--no-ff` creates a merge commit for clear release history
- **Always tag** — releases are traceable
- **Always sync public** — egregore-core stays up to date with main
- **Always notify** — team knows when main changes
