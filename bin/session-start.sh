#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# --- Config ---
STATE_FILE="$SCRIPT_DIR/.egregore-state.json"
DATE=$(date +%Y-%m-%d)

# --- Determine author short name ---
FULLNAME=$(git config user.name 2>/dev/null || echo "")
case "$FULLNAME" in
  *Oguzhan*|*ozzi*) AUTHOR="oz" ;;
  *Cem*)            AUTHOR="cem" ;;
  *Ali*)            AUTHOR="ali" ;;
  *Pali*)           AUTHOR="pali" ;;
  *Damla*)          AUTHOR="damla" ;;
  *)                AUTHOR=$(echo "$FULLNAME" | tr '[:upper:]' '[:lower:]' | cut -d' ' -f1) ;;
esac

if [ -z "$AUTHOR" ]; then
  echo '{"error": "git user.name not set. Run: git config user.name \"Your Name\""}'
  exit 1
fi

# --- Check onboarding state ---
# If state file doesn't exist, assume onboarding complete (existing team member)
# State file is only created by onboarding flow for new orgs/users
ONBOARDING_COMPLETE="true"
if [ -f "$STATE_FILE" ]; then
  ONBOARDING_COMPLETE=$(jq -r '.onboarding_complete // false' "$STATE_FILE" 2>/dev/null || echo "true")
fi

if [ "$ONBOARDING_COMPLETE" != "true" ]; then
  echo "{\"onboarding_complete\": false, \"author\": \"$AUTHOR\"}"
  exit 0
fi

# --- Fetch all remotes in parallel ---
git fetch origin --quiet 2>/dev/null &
FETCH_PID=$!

# Sync memory in parallel
MEMORY_SYNCED="false"
if [ -L "$SCRIPT_DIR/memory" ] && [ -d "$SCRIPT_DIR/memory/.git" ]; then
  git -C "$SCRIPT_DIR/memory" fetch origin --quiet 2>/dev/null &
  MEM_FETCH_PID=$!
else
  MEM_FETCH_PID=""
fi

# Ensure upstream remote exists (for update checks)
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/Curve-Labs/egregore-core.git 2>/dev/null || true
fi
git fetch upstream --quiet 2>/dev/null &
UPSTREAM_FETCH_PID=$!

# Wait for fetches
wait $FETCH_PID 2>/dev/null || true
if [ -n "$MEM_FETCH_PID" ]; then
  wait $MEM_FETCH_PID 2>/dev/null || true
fi
wait $UPSTREAM_FETCH_PID 2>/dev/null || true

# --- Ensure develop branch exists locally ---
if ! git show-ref --verify --quiet refs/heads/develop 2>/dev/null; then
  if git show-ref --verify --quiet refs/remotes/origin/develop 2>/dev/null; then
    git checkout -b develop origin/develop --quiet 2>/dev/null
  else
    # No develop on remote either — create from main
    git checkout -b develop --quiet 2>/dev/null
    git push -u origin develop --quiet 2>/dev/null
  fi
fi

# --- Sync develop ---
CURRENT_BRANCH=$(git branch --show-current)

# Save current state if dirty
STASHED="false"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  git stash push -m "session-start auto-stash" --quiet 2>/dev/null
  STASHED="true"
fi

git checkout develop --quiet 2>/dev/null
git pull origin develop --quiet 2>/dev/null || true
DEVELOP_SYNCED="true"

# Count commits on develop ahead of main
COMMITS_AHEAD=0
if git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
  COMMITS_AHEAD=$(git rev-list origin/main..origin/develop --count 2>/dev/null || echo "0")
fi

# --- Create or resume working branch ---
ACTION="created"
BRANCH=""

if [[ "$CURRENT_BRANCH" == dev/* ]]; then
  # Resume existing session branch
  BRANCH="$CURRENT_BRANCH"
  git checkout "$BRANCH" --quiet 2>/dev/null

  # Rebase onto develop
  if git rebase develop --quiet 2>/dev/null; then
    ACTION="rebased"
  else
    git rebase --abort 2>/dev/null || true
    git merge develop --quiet -m "Sync with develop" 2>/dev/null || true
    ACTION="merged"
  fi
else
  # Create new session branch from develop
  BRANCH="dev/$AUTHOR/$DATE-session"

  # If branch already exists (same person, same day), use it
  if git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    git checkout "$BRANCH" --quiet 2>/dev/null
    if git rebase develop --quiet 2>/dev/null; then
      ACTION="resumed"
    else
      git rebase --abort 2>/dev/null || true
      git merge develop --quiet -m "Sync with develop" 2>/dev/null || true
      ACTION="resumed"
    fi
  else
    git checkout -b "$BRANCH" --quiet 2>/dev/null
    ACTION="created"
  fi
fi

# Restore stashed changes
if [ "$STASHED" = "true" ]; then
  git stash pop --quiet 2>/dev/null || true
fi

# --- Sync memory ---
if [ -L "$SCRIPT_DIR/memory" ] && [ -d "$SCRIPT_DIR/memory/.git" ]; then
  MEM_LOCAL=$(git -C "$SCRIPT_DIR/memory" rev-parse HEAD 2>/dev/null || echo "")
  MEM_REMOTE=$(git -C "$SCRIPT_DIR/memory" rev-parse origin/main 2>/dev/null || echo "")
  if [ -n "$MEM_LOCAL" ] && [ -n "$MEM_REMOTE" ] && [ "$MEM_LOCAL" != "$MEM_REMOTE" ]; then
    git -C "$SCRIPT_DIR/memory" pull origin main --quiet 2>/dev/null || true
  fi
  MEMORY_SYNCED="true"
fi

# --- Output greeting for Claude to display ---
cat << 'GREETING'

  ███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
  ██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
  █████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
  ██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
  ███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
  ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

GREETING

# Status line
if [ "$ACTION" = "created" ]; then
  echo "  New session started."
elif [ "$ACTION" = "resumed" ] || [ "$ACTION" = "rebased" ]; then
  echo "  Session resumed."
fi

echo "  Branch: $BRANCH"
echo "  Develop: synced"
[ "$MEMORY_SYNCED" = "true" ] && echo "  Memory: synced"
[ "$COMMITS_AHEAD" -gt 0 ] && echo "  $COMMITS_AHEAD changes on develop since last release."

# --- Check for upstream updates (non-blocking) ---
UPSTREAM_NOTICE=""
if git remote get-url upstream >/dev/null 2>&1; then
  git fetch upstream --quiet 2>/dev/null || true
  UPSTREAM_NEW=$(git rev-list HEAD..upstream/main --count 2>/dev/null || echo "0")
  if [ "$UPSTREAM_NEW" -gt 0 ]; then
    UPSTREAM_NOTICE="  ⬆ $UPSTREAM_NEW upstream updates available. Run /update-egregore to get them."
  fi
fi
[ -n "$UPSTREAM_NOTICE" ] && echo "$UPSTREAM_NOTICE"

echo ""
echo "IMPORTANT: Display the above greeting to the user exactly as-is (preserve the ASCII art formatting) on their first message. Then ask: What are you working on?"

# --- Register instance in ~/.egregore/instances.json ---
REGISTRY_DIR="$HOME/.egregore"
REGISTRY_FILE="$REGISTRY_DIR/instances.json"
ORG_NAME=$(jq -r '.org_name // "Egregore"' "$SCRIPT_DIR/egregore.json" 2>/dev/null)
ORG_SLUG=$(jq -r '.github_org // "default"' "$SCRIPT_DIR/egregore.json" 2>/dev/null | tr '[:upper:]' '[:lower:]')

mkdir -p "$REGISTRY_DIR"
if [ ! -f "$REGISTRY_FILE" ]; then
  echo '[]' > "$REGISTRY_FILE"
fi

jq --arg slug "$ORG_SLUG" --arg name "$ORG_NAME" --arg path "$SCRIPT_DIR" \
  'if any(.[]; .slug == $slug)
   then map(if .slug == $slug then {slug: $slug, name: $name, path: $path} else . end)
   else . + [{slug: $slug, name: $name, path: $path}]
   end' "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"

# --- Install egregore shell function if needed ---
SHELL_PROFILE=""
if [ -f "$HOME/.zshrc" ]; then
  SHELL_PROFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_PROFILE="$HOME/.bashrc"
elif [ -f "$HOME/.bash_profile" ]; then
  SHELL_PROFILE="$HOME/.bash_profile"
fi

if [ -n "$SHELL_PROFILE" ]; then
  if ! grep -q 'egregore()' "$SHELL_PROFILE" 2>/dev/null; then
    # Remove old alias if present (migration)
    if grep -q 'alias egregore=' "$SHELL_PROFILE" 2>/dev/null; then
      grep -v 'alias egregore=' "$SHELL_PROFILE" | grep -v '^# Egregore$' > "$SHELL_PROFILE.tmp"
      mv "$SHELL_PROFILE.tmp" "$SHELL_PROFILE"
    fi

    cat >> "$SHELL_PROFILE" << 'SHELL_FUNC'

# Egregore
egregore() {
  local registry="$HOME/.egregore/instances.json"
  if [ ! -f "$registry" ] || [ ! -s "$registry" ]; then
    echo "No Egregore instances found. Run: npx create-egregore"
    return 1
  fi
  local -a names paths
  local i=0
  while IFS=$'\t' read -r slug name epath; do
    if [ -d "$epath" ]; then
      names[$i]="$name"
      paths[$i]="$epath"
      i=$((i + 1))
    fi
  done < <(jq -r '.[] | [.slug, .name, .path] | @tsv' "$registry" 2>/dev/null)
  local count=$i
  if [ "$count" -eq 0 ]; then
    echo "No Egregore instances found. Run: npx create-egregore"
    return 1
  fi
  if [ "$count" -eq 1 ]; then
    cd "${paths[0]}" && claude start
    return
  fi
  echo ""
  echo "  Which Egregore?"
  echo ""
  for ((j=0; j<count; j++)); do
    echo "  $((j + 1)). ${names[$j]}"
  done
  echo ""
  local choice
  printf "  Pick [1-%d]: " "$count"
  read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
    echo "  Invalid choice."
    return 1
  fi
  cd "${paths[$((choice - 1))]}" && claude start
}
SHELL_FUNC
    echo "  [Installed 'egregore' command — type it from any terminal next time]"
  fi
fi
