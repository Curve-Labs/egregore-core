#!/bin/bash
# Egregore Coder Workspace Init
# Called by Coder agent on workspace start.
# Clones repos, writes config, sets up memory symlink, writes bootstrap.
# Idempotent — safe to run on every workspace restart.
set -euo pipefail

HOME_DIR="$HOME"
EGREGORE_DIR="$HOME_DIR/egregore"
MEMORY_DIR="$HOME_DIR/memory"

# Required env vars (injected by Coder template)
: "${ORG_SLUG:?ORG_SLUG not set}"
: "${GITHUB_ORG:?GITHUB_ORG not set}"

# CODER_USERNAME is the user's GitHub username (set by Coder template).
# Used for git identity and Anthropic key lookup instead of calling GitHub API.
GH_USERNAME="${CODER_USERNAME:-}"

# ─── Git credential setup ────────────────────────────────────────

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper store
  echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > "$HOME_DIR/.git-credentials"
  chmod 600 "$HOME_DIR/.git-credentials"
fi

# Set git identity from CODER_USERNAME (= github username)
# Falls back to GitHub API if CODER_USERNAME is not set (shouldn't happen)
if [ ! -f "$HOME_DIR/.egregore/.git-identity-set" ]; then
  mkdir -p "$HOME_DIR/.egregore"
  if [ -n "$GH_USERNAME" ]; then
    # Look up display name from our API (fast, no GitHub API call needed)
    GH_NAME="$GH_USERNAME"
    if [ -n "${EGREGORE_API_KEY:-}" ] && [ -n "${API_URL:-}" ]; then
      MEMBER_INFO=$(curl -sf "${API_URL}/api/org/${ORG_SLUG}/members/${GH_USERNAME}" \
        -H "Authorization: Bearer $EGREGORE_API_KEY" --max-time 5 2>/dev/null || echo '{}')
      DISPLAY_NAME=$(echo "$MEMBER_INFO" | jq -r '.display_name // empty')
      if [ -n "$DISPLAY_NAME" ]; then
        GH_NAME="$DISPLAY_NAME"
      fi
    fi
    git config --global user.name "$GH_NAME"
    git config --global user.email "${GH_USERNAME}@users.noreply.github.com"
    touch "$HOME_DIR/.egregore/.git-identity-set"
  elif [ -n "${GITHUB_TOKEN:-}" ]; then
    # Fallback: use GitHub API (org-level token, but extract user info)
    GH_USER=$(curl -sf -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user --max-time 5 2>/dev/null || echo '{}')
    GH_NAME=$(echo "$GH_USER" | jq -r '.name // .login // "egregore"')
    GH_LOGIN=$(echo "$GH_USER" | jq -r '.login // "egregore"')
    git config --global user.name "$GH_NAME"
    git config --global user.email "${GH_LOGIN}@users.noreply.github.com"
    touch "$HOME_DIR/.egregore/.git-identity-set"
  fi
fi

# ─── Clone or update Egregore repo ───────────────────────────────

REPO_NAME="${REPO_NAME:-egregore-core}"
FORK_URL="${FORK_URL:-https://github.com/${GITHUB_ORG}/${REPO_NAME}.git}"

if [ ! -d "$EGREGORE_DIR/.git" ]; then
  echo "Cloning Egregore repo..."
  git clone "$FORK_URL" "$EGREGORE_DIR"
else
  echo "Updating Egregore repo..."
  cd "$EGREGORE_DIR"
  git fetch origin --quiet 2>/dev/null || true
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  if [ "$CURRENT_BRANCH" = "develop" ] || [ "$CURRENT_BRANCH" = "main" ]; then
    git pull --ff-only origin "$CURRENT_BRANCH" 2>/dev/null || true
  fi
fi

# ─── Clone or update memory repo ─────────────────────────────────

MEMORY_URL="${MEMORY_URL:-}"
if [ -n "$MEMORY_URL" ]; then
  if [ ! -d "$MEMORY_DIR/.git" ]; then
    echo "Cloning memory repo..."
    git clone "$MEMORY_URL" "$MEMORY_DIR"
  else
    echo "Updating memory repo..."
    cd "$MEMORY_DIR"
    git pull --ff-only origin main 2>/dev/null || true
  fi

  # Create memory symlink (idempotent)
  ln -sfn "$MEMORY_DIR" "$EGREGORE_DIR/memory"
fi

# ─── Clone managed repos ─────────────────────────────────────────

MANAGED_REPOS="${MANAGED_REPOS:-}"
if [ -n "$MANAGED_REPOS" ]; then
  IFS=',' read -ra REPOS <<< "$MANAGED_REPOS"
  for repo in "${REPOS[@]}"; do
    repo=$(echo "$repo" | xargs) # trim whitespace
    [ -z "$repo" ] && continue
    REPO_DIR="$HOME_DIR/$repo"
    if [ ! -d "$REPO_DIR/.git" ]; then
      echo "Cloning managed repo: $repo"
      git clone "https://github.com/${GITHUB_ORG}/$repo.git" "$REPO_DIR" 2>/dev/null || echo "Warning: could not clone $repo"
    else
      echo "Updating managed repo: $repo"
      cd "$REPO_DIR"
      git fetch origin --quiet 2>/dev/null || true
    fi
  done
fi

# ─── Write egregore.json ─────────────────────────────────────────

ORG_NAME="${ORG_NAME:-Egregore}"
API_URL="${API_URL:-https://egregore-production-55f2.up.railway.app}"

# Build managed repos JSON array
MANAGED_JSON="[]"
if [ -n "$MANAGED_REPOS" ]; then
  MANAGED_JSON=$(echo "$MANAGED_REPOS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF{printf "%s\"%s\"", (NR>1?",":""), $0}' | sed 's/^/[/;s/$/]/')
fi

cat > "$EGREGORE_DIR/egregore.json" <<EOF
{
  "org_name": "${ORG_NAME}",
  "github_org": "${GITHUB_ORG}",
  "memory_repo": "${MEMORY_URL}",
  "api_url": "${API_URL}",
  "repo_name": "${REPO_NAME}",
  "slug": "${ORG_SLUG}",
  "repos": ${MANAGED_JSON}
}
EOF

# ─── Fetch user's Anthropic key from API ─────────────────────────

ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"
if [ -z "$ANTHROPIC_KEY" ] && [ -n "${EGREGORE_API_KEY:-}" ] && [ -n "${API_URL:-}" ] && [ -n "$GH_USERNAME" ]; then
  FETCHED=$(curl -sf "${API_URL}/api/user/keys/fetch?key_name=anthropic_api_key&github_username=${GH_USERNAME}" \
    -H "Authorization: Bearer $EGREGORE_API_KEY" --max-time 5 2>/dev/null || echo '{}')
  KEY_VAL=$(echo "$FETCHED" | jq -r '.value // empty')
  if [ -n "$KEY_VAL" ] && [ "$KEY_VAL" != "null" ]; then
    ANTHROPIC_KEY="$KEY_VAL"
    echo "Fetched Anthropic API key from settings"
  fi
fi

# Write flag if no Anthropic key (bootstrap will show prompt)
if [ -z "$ANTHROPIC_KEY" ]; then
  touch "$HOME_DIR/.egregore/.needs-anthropic-key"
else
  rm -f "$HOME_DIR/.egregore/.needs-anthropic-key"
fi

# ─── Write .env (secrets) ────────────────────────────────────────

cat > "$EGREGORE_DIR/.env" <<EOF
GITHUB_TOKEN=${GITHUB_TOKEN:-}
EGREGORE_API_KEY=${EGREGORE_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
EOF
chmod 600 "$EGREGORE_DIR/.env"

# ─── Write .egregore-state.json (user identity) ──────────────────

if [ -n "$GH_USERNAME" ] && [ ! -f "$EGREGORE_DIR/.egregore-state.json" ]; then
  cat > "$EGREGORE_DIR/.egregore-state.json" <<EOF
{
  "org_setup": true,
  "github_username": "${GH_USERNAME}",
  "onboarding_complete": false,
  "workspace_ready": true
}
EOF
fi

# ─── Ensure ~/.egregore exists ────────────────────────────────────

mkdir -p "$HOME_DIR/.egregore"

# ─── Write bootstrap script (auto-start Egregore on terminal open) ─

cat > "$HOME_DIR/.egregore-bootstrap.sh" <<'BOOTEOF'
#!/bin/bash
# Egregore bootstrap — auto-start Claude in egregore dir

# Convenience command for manual restart
egregore() {
  if [ -d "$HOME/egregore" ]; then
    cd ~/egregore && claude "start"
  else
    echo "Workspace not ready. Restart from the Coder dashboard."
  fi
}

export PATH="$HOME/.local/bin:$HOME/.claude/bin:/usr/local/bin:$PATH"

# Check if Anthropic key is missing
if [ -f "$HOME/.egregore/.needs-anthropic-key" ]; then
  echo ""
  echo "  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo "  Anthropic API key not set."
  echo ""
  echo "  Go to egregore.xyz/settings to connect your"
  echo "  Anthropic account, then restart this workspace."
  echo "  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo ""
  echo "  Type 'egregore' to retry after setting your key."
  echo ""
  exec zsh
fi

# Start Egregore
if [ -d "$HOME/egregore" ] && command -v claude &>/dev/null; then
  cd ~/egregore
  exec claude "start"
else
  echo ""
  echo "  Workspace setup incomplete."
  echo "  Type 'egregore' to retry, or restart from the Coder dashboard."
  echo ""
  exec zsh
fi
BOOTEOF
chmod +x "$HOME_DIR/.egregore-bootstrap.sh"

echo "Egregore workspace ready: ${ORG_NAME} (${ORG_SLUG})"
