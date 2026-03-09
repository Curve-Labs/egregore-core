#!/bin/bash
# Egregore Coder Workspace Startup
# Clones repos, writes config, sets up memory symlink.
# Runs on every workspace start (idempotent).
set -euo pipefail

HOME_DIR="/home/egregore"
EGREGORE_DIR="$HOME_DIR/egregore"
MEMORY_DIR="$HOME_DIR/memory"

# ─── Git credential setup ────────────────────────────────────────

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper store
  echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > "$HOME_DIR/.git-credentials"
  chmod 600 "$HOME_DIR/.git-credentials"
  git config --global user.name "$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r '.name // .login' 2>/dev/null || echo 'egregore')"
  git config --global user.email "$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r '.login + "@users.noreply.github.com"' 2>/dev/null || echo 'egregore@users.noreply.github.com')"
fi

# ─── Clone or update Egregore repo ───────────────────────────────

if [ ! -d "$EGREGORE_DIR/.git" ]; then
  echo "Cloning Egregore repo..."
  git clone --branch develop "${FORK_URL:-https://github.com/${GITHUB_ORG}/${REPO_NAME:-egregore-core}.git}" "$EGREGORE_DIR" 2>/dev/null \
    || git clone "${FORK_URL:-https://github.com/${GITHUB_ORG}/${REPO_NAME:-egregore-core}.git}" "$EGREGORE_DIR"
else
  echo "Updating Egregore repo..."
  cd "$EGREGORE_DIR"
  git fetch origin --quiet
  # Only pull if on develop or main
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  if [ "$CURRENT_BRANCH" = "develop" ] || [ "$CURRENT_BRANCH" = "main" ]; then
    git pull --ff-only origin "$CURRENT_BRANCH" 2>/dev/null || true
  fi
fi

# ─── Clone or update memory repo ─────────────────────────────────

if [ -n "${MEMORY_URL:-}" ]; then
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

if [ -n "${MANAGED_REPOS:-}" ]; then
  IFS=',' read -ra REPOS <<< "$MANAGED_REPOS"
  for repo in "${REPOS[@]}"; do
    repo=$(echo "$repo" | xargs) # trim whitespace
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

MANAGED_JSON="[]"
if [ -n "${MANAGED_REPOS:-}" ]; then
  MANAGED_JSON=$(echo "$MANAGED_REPOS" | tr ',' '\n' | xargs -I{} echo '"{}"' | paste -sd',' - | sed 's/^/[/;s/$/]/')
fi

cat > "$EGREGORE_DIR/egregore.json" <<EOF
{
  "org_name": "${ORG_NAME:-Egregore}",
  "github_org": "${GITHUB_ORG}",
  "memory_repo": "${MEMORY_URL:-}",
  "api_url": "${API_URL:-https://egregore-production-55f2.up.railway.app}",
  "repo_name": "${REPO_NAME:-egregore-core}",
  "slug": "${ORG_SLUG}",
  "repos": ${MANAGED_JSON}
}
EOF

# ─── Write .env (secrets) ────────────────────────────────────────

cat > "$EGREGORE_DIR/.env" <<EOF
GITHUB_TOKEN=${GITHUB_TOKEN:-}
EGREGORE_API_KEY=${EGREGORE_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
EOF
chmod 600 "$EGREGORE_DIR/.env"

# ─── Copy framework files if not in repo ──────────────────────────

# If the cloned repo doesn't have bin/ (e.g. fresh fork), copy from base image
if [ ! -f "$EGREGORE_DIR/bin/session-start.sh" ]; then
  echo "Copying framework files from base image..."
  cp -r /opt/egregore/bin "$EGREGORE_DIR/bin"
  cp -r /opt/egregore/.claude "$EGREGORE_DIR/.claude"
  cp /opt/egregore/CLAUDE.md "$EGREGORE_DIR/CLAUDE.md"
fi

# ─── Ensure ~/.egregore exists ────────────────────────────────────

mkdir -p "$HOME_DIR/.egregore"

# ─── Write Claude Code settings for this workspace ───────────────

mkdir -p "$HOME_DIR/.claude"
cat > "$HOME_DIR/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(bin/*)",
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(jq *)",
      "Bash(curl *)"
    ]
  }
}
EOF

echo "Egregore workspace ready: ${ORG_NAME:-Egregore} (${ORG_SLUG:-unknown})"
