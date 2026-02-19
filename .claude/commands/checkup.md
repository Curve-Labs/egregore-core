# Checkup

Run a full diagnostic of the Egregore environment. Check every service and dependency, render a TUI diagnostic box, and auto-fix what you can.

## When to invoke

- User says "checkup", "diagnose", "what's broken", "health check", "status check"
- Session greeting shows `⚠ Issues detected — run /checkup`
- User reports something not working and root cause is unclear

## Procedure

Run checks in **3 sequential batches**. Within each batch, checks can run in parallel. **Never run network checks (5-6) in the same parallel batch as local checks (7-10)** — a network timeout will cascade-cancel the siblings.

**Batch 1** (local, fast): Checks 1-4 — config, env, GitHub token, API key slug
**Batch 2** (network, may timeout): Checks 5-6 — graph, telegram
**Batch 3** (local + git): Checks 7-10 — memory, git, framework, alias

Collect results into a `checks` array, then render the diagnostic box.

### Check 1: Config (egregore.json)

```bash
jq . egregore.json
```

- **Pass** if valid JSON with non-empty `org_name`, `github_org`, `slug`, `api_url`
- **Fail** if file missing, invalid JSON, or required fields empty
- **Fix**: run `/setup`

Extract `slug` and `org_name` for display.

### Check 2: Environment (.env)

```bash
test -f .env && grep -c '^[A-Z]' .env
```

- **Pass** if `.env` exists and has both `GITHUB_TOKEN` and `EGREGORE_API_KEY`
- **Fail** if missing file or missing keys
- **Fix**: for missing `GITHUB_TOKEN`, run `bash bin/github-auth.sh`. For missing `EGREGORE_API_KEY`, tell user to ask team admin.

Count the keys present for display.

### Check 3: GitHub token

```bash
TOKEN=$(grep '^GITHUB_TOKEN=' .env | cut -d'=' -f2-)
curl -s -H "Authorization: token $TOKEN" https://api.github.com/user --max-time 5
```

- **Pass** if response has `.login`
- **Fail** if 401, timeout, or no login
- **Fix**: run `bash bin/github-auth.sh`

Show `authenticated as {login}` on pass.

### Check 4: API key slug

```bash
CURRENT_KEY=$(grep '^EGREGORE_API_KEY=' .env | cut -d'=' -f2-)
EXPECTED_SLUG=$(jq -r '.slug // empty' egregore.json)
KEY_SLUG=$(echo "$CURRENT_KEY" | cut -d'_' -f2)
```

- **Pass** if `KEY_SLUG == EXPECTED_SLUG`
- **Fail** if mismatch or key missing
- **Fix**: fetch correct key via API:
  ```bash
  API_URL=$(jq -r '.api_url' egregore.json)
  TOKEN=$(grep '^GITHUB_TOKEN=' .env | cut -d'=' -f2-)
  curl -s -X GET "${API_URL}/api/org/${EXPECTED_SLUG}/key" -H "Authorization: Bearer $TOKEN" --max-time 10
  ```
  Then update `.env` with the returned `api_key`.

Show `valid (slug: {slug})` on pass, `slug mismatch (key={KEY_SLUG}, config={EXPECTED_SLUG})` on fail.

### Check 5: Graph (Neo4j)

```bash
timeout 10 bash bin/graph.sh test 2>&1; echo "EXIT:$?"
```

- **Pass** if output contains "Connected"
- **Fail** if timeout (exit 124), error, or no "Connected"
- **Fix**: report "API or network is down. No action needed from you."

### Check 6: Telegram

```bash
timeout 10 bash bin/notify.sh test 2>&1; echo "EXIT:$?"
```

- **Pass** if output contains "connected"
- **Fail** if timeout (exit 124) or error
- **Fix**: report status. No user action needed — Telegram is optional.

**Important**: Run checks 5 and 6 together in their own batch, separate from all other checks. Append `EXIT:$?` so you always get output even on timeout — this prevents Claude Code from treating it as a tool error.

### Check 7: Memory repo

```bash
test -L memory && test -d memory/.git
git -C memory status --porcelain
```

- **Pass** if symlink exists, is a git repo, and is clean
- **Warn** if dirty (uncommitted changes)
- **Fail** if symlink missing or not a git repo
- **Fix**: run `/setup`

Show `linked and synced` on pass, `dirty — N uncommitted changes` on warn.

### Check 8: Git state

```bash
git show-ref --verify refs/heads/develop
git rev-parse develop
git rev-parse origin/develop
```

- **Pass** if develop exists and matches origin/develop
- **Warn** if develop exists but diverged
- **Fail** if develop doesn't exist
- **Fix**: run `/pull`

### Check 9: Framework version

```bash
FRAMEWORK_VERSION=$(head -20 bin/session-start.sh | grep 'FRAMEWORK_VERSION=' | cut -d'"' -f2)
git fetch upstream main --quiet 2>/dev/null
UPSTREAM_VERSION=$(git show upstream/main:bin/session-start.sh 2>/dev/null | head -20 | grep 'FRAMEWORK_VERSION=' | cut -d'"' -f2)
```

- **Pass** if versions match or upstream unavailable
- **Warn** if upstream is newer
- **Fix**: run `/update`

Show `v{N} (current)` on pass, `v{N} → v{M} available` on warn.

### Check 10: Shell alias

```bash
SHELL_PROFILE=""
case "$SHELL" in
  */zsh)  SHELL_PROFILE="$HOME/.zshrc" ;;
  */bash) SHELL_PROFILE="$HOME/.bash_profile" ;;
  */fish) SHELL_PROFILE="$HOME/.config/fish/config.fish" ;;
esac
grep -l "$(pwd)" "$SHELL_PROFILE" 2>/dev/null
```

- **Pass** if an alias/function pointing to this directory exists in the shell profile
- **Fail** if not found
- **Fix**: run `bash bin/ensure-shell-function.sh`

Show `{alias_name} in {profile}` on pass.

## Rendering

After collecting all results, render a diagnostic box. Use exactly this format:

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⊕ CHECKUP                                          {date}         │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  CONFIG                                                              │
│  ✓ egregore.json valid (slug: {slug}, org: {org_name})              │
│  ✓ .env configured ({N} keys present)                               │
│                                                                      │
│  SERVICES                                                            │
│  ✓ GitHub — authenticated as {login}                                │
│  ✓ API key — valid (slug: {slug})                                   │
│  ✓ Graph — connected                                                │
│  ✓ Telegram — connected                                             │
│                                                                      │
│  WORKSPACE                                                           │
│  ✓ Memory — linked and synced                                       │
│  ✓ Git — develop synced                                             │
│  ✓ Framework v{N} (current)                                         │
│  ✓ Shell alias — {name} in {profile}                                │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  {passed} passed · {warnings} warnings · {errors} errors            │
└──────────────────────────────────────────────────────────────────────┘
```

Symbols:
- `✓` = passed
- `⚠` = warning (works but degraded)
- `✗` = failed

For failures, add a `→` line immediately after showing what Claude will do:

```
│  ✗ GitHub — token expired                                           │
│    → Re-authenticating with GitHub...                                │
```

## Auto-fix

After rendering the box, **automatically fix** what you can:

1. **GitHub token expired** → run `bash bin/github-auth.sh` and report result
2. **API key mismatch** → fetch correct key from API and update `.env`
3. **Memory not linked** → run `/setup`
4. **Git diverged** → run `/pull`
5. **Framework outdated** → run `/update`
6. **Shell alias missing** → run `bash bin/ensure-shell-function.sh`
7. **Graph/Telegram down** → just report. No user action.

After fixing, re-check the fixed items and report:
```
Fixed 2 of 3 issues:
✓ GitHub — re-authenticated as {login}
✓ API key — updated to correct slug
✗ Graph — still unreachable (API may be down)
```

## Key principle

Never tell the user to "run a command in terminal." Either fix it yourself or explain what's wrong in plain language.
