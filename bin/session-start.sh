#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# --- Config ---
STATE_FILE="$SCRIPT_DIR/.egregore-state.json"
DATE=$(date +%Y-%m-%d)

# --- Determine author identity ---
# Priority: .egregore-state.json github_username > repo-local git config > GitHub API auto-detect > global git config
ENV_FILE="$SCRIPT_DIR/.env"
STORED_USERNAME=""
FIRST_SESSION=""
AUTHOR=""
if [ -f "$STATE_FILE" ]; then
  STORED_USERNAME=$(jq -r '.github_username // empty' "$STATE_FILE" 2>/dev/null)
fi

if [ -n "$STORED_USERNAME" ]; then
  # Identity stored during setup — use it and ensure repo-local git config matches
  AUTHOR="$STORED_USERNAME"
  CURRENT_LOCAL=$(git config --local user.name 2>/dev/null || echo "")
  if [ "$CURRENT_LOCAL" != "$STORED_USERNAME" ]; then
    STORED_NAME=$(jq -r '.github_name // empty' "$STATE_FILE" 2>/dev/null)
    git config user.name "${STORED_NAME:-$STORED_USERNAME}" 2>/dev/null || true
    git config user.email "${STORED_USERNAME}@users.noreply.github.com" 2>/dev/null || true
  fi
else
  # No stored identity — try GitHub API to auto-detect (self-healing for pre-fix installs)
  if [ -f "$ENV_FILE" ]; then
    GH_TOKEN=$(grep '^GITHUB_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
    if [ -n "$GH_TOKEN" ]; then
      GH_USER_JSON=$(curl -s -H "Authorization: token $GH_TOKEN" https://api.github.com/user --max-time 5 2>/dev/null || echo "")
      GH_LOGIN=$(echo "$GH_USER_JSON" | jq -r '.login // empty' 2>/dev/null)
      GH_NAME=$(echo "$GH_USER_JSON" | jq -r '.name // empty' 2>/dev/null)
      if [ -n "$GH_LOGIN" ]; then
        AUTHOR="$GH_LOGIN"
        # Set repo-local config and save to state for next time
        git config user.name "${GH_NAME:-$GH_LOGIN}" 2>/dev/null || true
        git config user.email "${GH_LOGIN}@users.noreply.github.com" 2>/dev/null || true
        # Save to state file so we don't need API call next time
        # Include onboarding_complete + name so it doesn't re-trigger onboarding
        # Determine if founder or joiner: if github_username != github_org, they're a joiner
        GITHUB_ORG_CFG=$(jq -r '.github_org // empty' "$SCRIPT_DIR/egregore.json" 2>/dev/null)
        if [ -n "$GITHUB_ORG_CFG" ] && [ "$GH_LOGIN" != "$GITHUB_ORG_CFG" ]; then
          USAGE_TYPE="joiner_group"
        else
          USAGE_TYPE="founder_group"
        fi
        if [ -f "$STATE_FILE" ]; then
          jq --arg u "$GH_LOGIN" --arg n "${GH_NAME:-$GH_LOGIN}" --arg ut "$USAGE_TYPE" \
            '.github_username = $u | .github_name = $n | .name = $n | .onboarding_complete = true | .usage_type = $ut' "$STATE_FILE" > "$STATE_FILE.tmp" \
            && mv "$STATE_FILE.tmp" "$STATE_FILE"
          FIRST_SESSION="false"
        else
          cat > "$STATE_FILE" << STATEEOF
{
  "github_username": "$GH_LOGIN",
  "github_name": "${GH_NAME:-$GH_LOGIN}",
  "name": "${GH_NAME:-$GH_LOGIN}",
  "onboarding_complete": true,
  "usage_type": "$USAGE_TYPE",
  "first_session": true
}
STATEEOF
          FIRST_SESSION="true"
        fi
      fi
    fi
  fi

  # Final fallback: git config user.name (global or local)
  if [ -z "$AUTHOR" ]; then
    FULLNAME=$(git config user.name 2>/dev/null || echo "")
    AUTHOR=$(echo "$FULLNAME" | tr '[:upper:]' '[:lower:]' | cut -d' ' -f1)
  fi
fi

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

# --- Auto-provision EGREGORE_API_KEY if missing ---
ENV_FILE="$SCRIPT_DIR/.env"
CONFIG="$SCRIPT_DIR/egregore.json"

if [ -f "$ENV_FILE" ] && ! grep -q '^EGREGORE_API_KEY=' "$ENV_FILE" 2>/dev/null; then
  GITHUB_TOKEN=$(grep '^GITHUB_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
  API_URL=$(jq -r '.api_url // empty' "$CONFIG" 2>/dev/null)
  GITHUB_ORG=$(jq -r '.github_org // empty' "$CONFIG" 2>/dev/null)

  if [ -n "$GITHUB_TOKEN" ] && [ -n "$API_URL" ] && [ -n "$GITHUB_ORG" ]; then
    SLUG=$(echo "$GITHUB_ORG" | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d ' ')
    KEY_RESPONSE=$(curl -s -X GET "${API_URL}/api/org/${SLUG}/key" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      --max-time 10 2>/dev/null || echo "")

    if [ -n "$KEY_RESPONSE" ]; then
      FETCHED_KEY=$(echo "$KEY_RESPONSE" | jq -r '.api_key // empty' 2>/dev/null)
      if [ -n "$FETCHED_KEY" ] && [ "$FETCHED_KEY" != "null" ]; then
        echo "EGREGORE_API_KEY=$FETCHED_KEY" >> "$ENV_FILE"
      fi
    fi
  fi
fi

# --- Self-register in instance registry (for pre-registry installs) ---
# Wrapped in subshell — registration is optional, must not block session start
if command -v jq &>/dev/null && [ -f "$CONFIG" ]; then
  (
    REGISTRY_DIR="$HOME/.egregore"
    REGISTRY="$REGISTRY_DIR/instances.json"
    INST_SLUG=$(jq -r '.github_org // empty' "$CONFIG" | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d ' ')
    INST_NAME=$(jq -r '.org_name // empty' "$CONFIG")

    if [ -n "$INST_SLUG" ] && [ -n "$INST_NAME" ]; then
      mkdir -p "$REGISTRY_DIR"
      if [ ! -f "$REGISTRY" ]; then echo "[]" > "$REGISTRY"; fi

      ALREADY=$(jq --arg p "$SCRIPT_DIR" '[.[] | select(.path == $p)] | length' "$REGISTRY")
      if [ "$ALREADY" = "0" ]; then
        ENTRY=$(jq -n --arg s "$INST_SLUG" --arg n "$INST_NAME" --arg p "$SCRIPT_DIR" \
          '{slug: $s, name: $n, path: $p}')
        jq --argjson e "$ENTRY" '. + [$e]' "$REGISTRY" > "$REGISTRY.tmp" \
          && mv "$REGISTRY.tmp" "$REGISTRY"
      fi
    fi
  ) 2>/dev/null || true
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

# Wait for fetches
wait $FETCH_PID 2>/dev/null || true
if [ -n "$MEM_FETCH_PID" ]; then
  wait $MEM_FETCH_PID 2>/dev/null || true
fi

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

# --- Sync develop (without checkout — safe for concurrent sessions) ---
CURRENT_BRANCH=$(git branch --show-current)

# Update local develop ref from remote without switching branches
git fetch origin develop:develop --quiet 2>/dev/null || true
DEVELOP_SYNCED="true"

# Count commits on develop ahead of main
COMMITS_AHEAD=0
if git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
  COMMITS_AHEAD=$(git rev-list origin/main..develop --count 2>/dev/null || echo "0")
fi

# --- Resume working branch or stay on current ---
# Branch creation is deferred to conversation — Claude creates a topic-based
# branch (dev/{author}/{topic-slug}) when the user says what they're working on.
# This avoids meaningless date-only branches and lets PRs have descriptive names.
ACTION="ready"
BRANCH="$CURRENT_BRANCH"

if [[ "$CURRENT_BRANCH" == dev/* ]] || [[ "$CURRENT_BRANCH" == feature/* ]] || [[ "$CURRENT_BRANCH" == bugfix/* ]]; then
  # Already on a working branch — rebase onto develop to stay current
  if git rebase develop --quiet 2>/dev/null; then
    ACTION="resumed"
  else
    git rebase --abort 2>/dev/null || true
    git merge develop --quiet -m "Sync with develop" 2>/dev/null || true
    ACTION="resumed"
  fi
elif [[ "$CURRENT_BRANCH" != "develop" ]]; then
  # On main or some other branch — switch to develop so we're ready
  git checkout develop --quiet 2>/dev/null || true
  BRANCH="develop"
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

# --- Bootstrap graph on first launch (deferred from web setup to avoid orphans) ---
# Runs in background — must not block session start
if [ -f "$CONFIG" ] && [ -f "$ENV_FILE" ]; then
  (
    API_KEY=$(grep '^EGREGORE_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
    if [ -n "$API_KEY" ]; then
      ORG_NAME=$(jq -r '.org_name // empty' "$CONFIG" 2>/dev/null)
      GITHUB_ORG=$(jq -r '.github_org // empty' "$CONFIG" 2>/dev/null)

      if [ -n "$ORG_NAME" ] && [ -n "$GITHUB_ORG" ]; then
        # Check if Org node exists — if not, bootstrap
        # $_org is auto-injected by the API from the API key
        EXISTS=$(bash "$SCRIPT_DIR/bin/graph.sh" query "MATCH (o:Org {id: \$_org}) RETURN o.id" 2>/dev/null || echo "")
        if echo "$EXISTS" | jq -e '.values | length == 0' &>/dev/null; then
          bash "$SCRIPT_DIR/bin/graph.sh" query \
            "MERGE (o:Org {id: \$_org}) SET o.name = \$name, o.github_org = \$github_org" \
            "{\"name\":\"$ORG_NAME\",\"github_org\":\"$GITHUB_ORG\"}" 2>/dev/null || true
          bash "$SCRIPT_DIR/bin/graph.sh" query \
            "MERGE (pr:Project {name: 'Egregore'}) WITH pr MATCH (o:Org {id: \$_org}) MERGE (pr)-[:PART_OF]->(o)" \
            2>/dev/null || true
        fi

        # Always ensure Person node exists (idempotent)
        # Match by github username first (stable across renames), fall back to name
        if [ -n "$AUTHOR" ]; then
          GH_USERNAME_STATE=""
          GH_FULLNAME_STATE=""
          if [ -f "$STATE_FILE" ]; then
            GH_USERNAME_STATE=$(jq -r '.github_username // empty' "$STATE_FILE" 2>/dev/null)
            GH_FULLNAME_STATE=$(jq -r '.github_name // empty' "$STATE_FILE" 2>/dev/null)
          fi
          PERSON_PARAMS=$(jq -n \
            --arg name "$AUTHOR" \
            --arg github "${GH_USERNAME_STATE:-$AUTHOR}" \
            --arg fullName "${GH_FULLNAME_STATE:-}" \
            '{name: $name, github: $github, fullName: $fullName}')
          bash "$SCRIPT_DIR/bin/graph.sh" query \
            "MERGE (p:Person {github: \$github}) ON CREATE SET p.name = \$name SET p.fullName = CASE WHEN \$fullName <> '' THEN \$fullName ELSE p.fullName END WITH p MATCH (o:Org {id: \$_org}) MERGE (p)-[:MEMBER_OF]->(o) RETURN p.name" \
            "$PERSON_PARAMS" 2>/dev/null || true
        fi
      fi
    fi
  ) &
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
echo "  User: $AUTHOR"
if [ "$ACTION" = "resumed" ]; then
  echo "  Branch: $BRANCH (resumed)"
else
  echo "  Branch: $BRANCH"
fi
echo "  Develop: synced"
if [ "$MEMORY_SYNCED" = "true" ]; then echo "  Memory: synced"; fi
if [ "$COMMITS_AHEAD" -gt 0 ] 2>/dev/null; then echo "  $COMMITS_AHEAD changes on develop since last release."; fi

# --- First session welcome ---
if [ -z "$FIRST_SESSION" ] && [ -f "$STATE_FILE" ]; then
  FIRST_SESSION=$(jq -r '.first_session // false' "$STATE_FILE" 2>/dev/null)
fi

if [ "$FIRST_SESSION" = "true" ]; then
  echo ""
  echo "  Welcome! This is your first session."
  echo ""
  echo "IMPORTANT: Display the above greeting exactly as-is. Then ask the user if they'd like a quick onboarding tour (run /onboarding), or if they want to jump straight in."
  # Clear the flag so it only shows once
  jq '.first_session = false' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
else
  # --- Tutorial tip (if onboarding done but tutorial not) ---
  TUTORIAL_COMPLETE="true"
  if [ -f "$STATE_FILE" ]; then
    TUTORIAL_COMPLETE=$(jq -r '.tutorial_complete // false' "$STATE_FILE" 2>/dev/null || echo "true")
  fi

  if [ "$TUTORIAL_COMPLETE" != "true" ]; then
    echo "  Tip: Run /tutorial to learn the core loop."
  fi

  echo ""
  echo "IMPORTANT: Display the above greeting to the user exactly as-is (preserve the ASCII art formatting) on their first message. Then ask: What are you working on?"
fi
