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

# --- Export telemetry identity env vars ---
export EGREGORE_USER="$AUTHOR"
export EGREGORE_ORG="$(jq -r '.slug // .github_org // empty' "$SCRIPT_DIR/egregore.json" 2>/dev/null || true)"
export EGREGORE_SESSION_ID="$(date -u +%Y%m%dT%H%M%S)-${AUTHOR}-$$"

# Persist session ID to file so telemetry.sh can read it
# (env vars from hooks don't propagate into the Claude Code agent)
SESSION_ID_DIR="$HOME/.egregore"
mkdir -p "$SESSION_ID_DIR"
PROJ_HASH=$(echo -n "$SCRIPT_DIR" | md5 2>/dev/null || echo -n "$SCRIPT_DIR" | md5sum 2>/dev/null | cut -d' ' -f1)
echo "$EGREGORE_SESSION_ID" > "$SESSION_ID_DIR/session-${PROJ_HASH}.id"

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

# --- Auto-provision or fix EGREGORE_API_KEY (background, non-blocking) ---
ENV_FILE="$SCRIPT_DIR/.env"
CONFIG="$SCRIPT_DIR/egregore.json"

# Check if key is missing OR if the key's slug doesn't match egregore.json slug
KEY_NEEDS_FIX="false"
if [ -f "$ENV_FILE" ]; then
  CURRENT_KEY=$(grep '^EGREGORE_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
  EXPECTED_SLUG=$(jq -r '.slug // empty' "$CONFIG" 2>/dev/null)
  if [ -z "$CURRENT_KEY" ]; then
    KEY_NEEDS_FIX="true"
  elif [ -n "$EXPECTED_SLUG" ]; then
    # Extract slug from key: ek_<slug>_<secret> → <slug>
    KEY_SLUG=$(echo "$CURRENT_KEY" | cut -d'_' -f2)
    if [ "$KEY_SLUG" != "$EXPECTED_SLUG" ]; then
      KEY_NEEDS_FIX="true"
    fi
  fi
fi

if [ "$KEY_NEEDS_FIX" = "true" ]; then
  (
    GITHUB_TOKEN=$(grep '^GITHUB_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
    API_URL=$(jq -r '.api_url // empty' "$CONFIG" 2>/dev/null)
    GITHUB_ORG=$(jq -r '.github_org // empty' "$CONFIG" 2>/dev/null)

    if [ -n "$GITHUB_TOKEN" ] && [ -n "$API_URL" ] && [ -n "$GITHUB_ORG" ]; then
      SLUG=$(jq -r '.slug // empty' "$CONFIG" 2>/dev/null)
      [ -z "$SLUG" ] && SLUG=$(echo "$GITHUB_ORG" | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d ' ')
      KEY_RESPONSE=$(curl -s -X GET "${API_URL}/api/org/${SLUG}/key" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "")

      if [ -n "$KEY_RESPONSE" ]; then
        FETCHED_KEY=$(echo "$KEY_RESPONSE" | jq -r '.api_key // empty' 2>/dev/null)
        if [ -n "$FETCHED_KEY" ] && [ "$FETCHED_KEY" != "null" ]; then
          # Replace existing key or append
          if grep -q '^EGREGORE_API_KEY=' "$ENV_FILE" 2>/dev/null; then
            sed -i.bak "s|^EGREGORE_API_KEY=.*|EGREGORE_API_KEY=$FETCHED_KEY|" "$ENV_FILE"
            rm -f "$ENV_FILE.bak"
          else
            echo "EGREGORE_API_KEY=$FETCHED_KEY" >> "$ENV_FILE"
          fi
        fi
      fi
    fi
  ) &
fi

# --- Self-register in instance registry (for pre-registry installs) ---
# Wrapped in subshell — registration is optional, must not block session start
if command -v jq &>/dev/null && [ -f "$CONFIG" ]; then
  (
    REGISTRY_DIR="$HOME/.egregore"
    REGISTRY="$REGISTRY_DIR/instances.json"
    INST_SLUG=$(jq -r '.slug // empty' "$CONFIG")
    [ -z "$INST_SLUG" ] && INST_SLUG=$(jq -r '.github_org // empty' "$CONFIG" | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d ' ')
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

# --- Compute session boundary for environment isolation ---
compute_boundary() {
  local hash
  hash=$(echo -n "$SCRIPT_DIR" | md5 2>/dev/null || echo -n "$SCRIPT_DIR" | md5sum 2>/dev/null | cut -d' ' -f1)
  local boundary_file="/tmp/egregore-boundary-${hash}.json"
  local project_dir="$SCRIPT_DIR"

  # Resolve memory directory (follow symlink)
  local memory_dir=""
  if [ -L "$SCRIPT_DIR/memory" ]; then
    memory_dir=$(realpath "$SCRIPT_DIR/memory" 2>/dev/null || echo "")
  fi

  # Validate and resolve managed repos
  local managed_repos_json="[]"
  local parent_dir
  parent_dir="$(dirname "$SCRIPT_DIR")"
  local repos
  repos=$(jq -r '.repos[]? // empty' "$SCRIPT_DIR/egregore.json" 2>/dev/null)
  if [ -n "$repos" ]; then
    # Validate repos first
    bash "$SCRIPT_DIR/bin/boundary.sh" validate-repos 2>/dev/null || true
    managed_repos_json="["
    local first=true
    for repo in $repos; do
      # Skip entries with path traversal or absolute paths
      [[ "$repo" == *".."* ]] && continue
      [[ "$repo" == /* ]] && continue
      local resolved
      resolved=$(realpath "$parent_dir/$repo" 2>/dev/null || echo "")
      [ -z "$resolved" ] && continue
      # Must resolve under parent directory
      [[ "$resolved" != "$parent_dir"/* ]] && continue
      $first || managed_repos_json="$managed_repos_json,"
      managed_repos_json="$managed_repos_json\"$resolved\""
      first=false
    done
    managed_repos_json="$managed_repos_json]"
  fi

  # Collect denied paths from instance registry
  local denied_paths_json="[]"
  local registry="$HOME/.egregore/instances.json"
  if [ -f "$registry" ]; then
    denied_paths_json=$(jq --arg self "$project_dir" \
      '[.[] | select(.path != $self) | .path]' "$registry" 2>/dev/null || echo "[]")
  fi

  # Write boundary file (atomic: write to tmp, then mv)
  jq -n \
    --arg project_dir "$project_dir" \
    --arg memory_dir "$memory_dir" \
    --argjson managed_repos "$managed_repos_json" \
    --argjson denied_paths "$denied_paths_json" \
    '{project_dir: $project_dir, memory_dir: $memory_dir, managed_repos: $managed_repos, denied_paths: $denied_paths}' \
    > "$boundary_file.tmp" && mv "$boundary_file.tmp" "$boundary_file"

  # Generate dynamic deny rules in .claude/settings.local.json
  local settings_local="$SCRIPT_DIR/.claude/settings.local.json"
  local deny_rules="[]"
  if [ "$denied_paths_json" != "[]" ]; then
    deny_rules=$(echo "$denied_paths_json" | jq '[.[] | "Read(" + . + "/**)", "Edit(" + . + "/**)", "Write(" + . + "/**)"]')
  fi
  # Deny writing to instance registry (reads allowed for multi-instance features)
  deny_rules=$(echo "$deny_rules" | jq '. + ["Edit(~/.egregore/instances.json)", "Write(~/.egregore/instances.json)"]')

  # Merge with existing settings.local.json — only touch permissions.deny
  mkdir -p "$SCRIPT_DIR/.claude"
  if [ -f "$settings_local" ]; then
    jq --argjson deny "$deny_rules" '.permissions.deny = $deny' "$settings_local" \
      > "$settings_local.tmp" && mv "$settings_local.tmp" "$settings_local"
  else
    jq -n --argjson deny "$deny_rules" \
      '{permissions: {deny: $deny}}' > "$settings_local"
  fi
}

# Run boundary computation (non-blocking, but fast — just file I/O)
compute_boundary 2>/dev/null || true

# --- Fetch all remotes in parallel ---
git fetch origin --quiet 2>/dev/null &

# Fetch upstream framework (for update check — non-blocking)
git remote add upstream https://github.com/Curve-Labs/egregore-core.git 2>/dev/null || true
git fetch upstream main --quiet 2>/dev/null &

# Sync memory in parallel
MEMORY_SYNCED="false"
if [ -L "$SCRIPT_DIR/memory" ] && [ -d "$SCRIPT_DIR/memory/.git" ]; then
  git -C "$SCRIPT_DIR/memory" fetch origin --quiet 2>/dev/null &
fi

# Fetch managed repos in parallel
MANAGED_REPOS=$(jq -r '.repos[]? // empty' "$SCRIPT_DIR/egregore.json" 2>/dev/null)
for REPO in $MANAGED_REPOS; do
  if [ -d "$SCRIPT_DIR/../$REPO/.git" ]; then
    git -C "$SCRIPT_DIR/../$REPO" fetch origin --quiet 2>/dev/null &
  fi
done

# Wait for all fetches
wait 2>/dev/null || true

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
  # Check if branch is already merged into develop — if so, switch to develop
  if git merge-base --is-ancestor "$CURRENT_BRANCH" develop 2>/dev/null; then
    git checkout develop --quiet 2>/dev/null || true
    BRANCH="develop"
  else
    # Unmerged working branch — rebase onto develop to stay current
    if git rebase develop --quiet 2>/dev/null; then
      ACTION="resumed"
    else
      git rebase --abort 2>/dev/null || true
      git merge develop --quiet -m "Sync with develop" 2>/dev/null || true
      ACTION="resumed"
    fi
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

# --- Sync managed repos ---
REPOS_STATUS=""
for REPO in $MANAGED_REPOS; do
  REPO_DIR="$SCRIPT_DIR/../$REPO"
  if [ -d "$REPO_DIR/.git" ]; then
    # Ensure develop branch exists locally
    if ! git -C "$REPO_DIR" show-ref --verify --quiet refs/heads/develop 2>/dev/null; then
      if git -C "$REPO_DIR" show-ref --verify --quiet refs/remotes/origin/develop 2>/dev/null; then
        git -C "$REPO_DIR" branch develop origin/develop --quiet 2>/dev/null || true
      fi
    else
      git -C "$REPO_DIR" fetch origin develop:develop --quiet 2>/dev/null || true
    fi
    # Collect status
    R_BRANCH=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo "?")
    R_DIRTY=""
    if [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null | head -1)" ]; then
      R_DIRTY=" *"
    fi
    REPOS_STATUS="${REPOS_STATUS}  ◇ ${REPO}: ${R_BRANCH}${R_DIRTY}\n"
  fi
done

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

          # Sync user + membership to Supabase (non-blocking, non-fatal)
          SB_API_URL=$(jq -r '.api_url // empty' "$CONFIG" 2>/dev/null)
          if [ -n "$SB_API_URL" ]; then
            curl -sf "${SB_API_URL}/api/user/ensure" \
              -H "Authorization: Bearer $API_KEY" \
              -H "Content-Type: application/json" \
              -d "{\"github_username\":\"${GH_USERNAME_STATE:-$AUTHOR}\",\"github_name\":\"${GH_FULLNAME_STATE:-}\"}" \
              --max-time 5 >/dev/null 2>&1 || true
          fi
        fi
      fi
    fi
  ) &
fi

# --- Retry failed transcript uploads (background, silent) ---
RETRY_QUEUE="$SCRIPT_DIR/.transcript-retry-queue"
TRANSCRIPTS_DIR="$SCRIPT_DIR/../egregore-transcripts"
if [ -f "$RETRY_QUEUE" ] && [ -s "$RETRY_QUEUE" ]; then
  (
    RETRIED=false
    # If git repo exists, retry push (CL internal)
    if [ -d "$TRANSCRIPTS_DIR/.git" ]; then
      if git -C "$TRANSCRIPTS_DIR" push origin main 2>/dev/null; then
        RETRIED=true
      fi
    fi
    # If API is available, retry upload for queued sessions (customer orgs)
    if [ "$RETRIED" = "false" ] && [ -f "$CONFIG" ] && [ -f "$ENV_FILE" ]; then
      R_API_URL=$(jq -r '.api_url // empty' "$CONFIG" 2>/dev/null || true)
      R_API_KEY=$(grep '^EGREGORE_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || true)
      if [ -n "$R_API_URL" ] && [ -n "$R_API_KEY" ]; then
        REMAINING=""
        COUNT=0
        while IFS= read -r SID && [ $COUNT -lt 5 ]; do
          SID=$(echo "$SID" | tr -cd 'a-zA-Z0-9_-')
          [ -z "$SID" ] && continue
          # Re-run the archive for this session (it will find the transcript)
          RETRIED=true
          COUNT=$((COUNT + 1))
        done < "$RETRY_QUEUE"
        if [ "$RETRIED" = "true" ]; then
          # Clear queue on any progress — archive script will re-queue failures
          rm -f "$RETRY_QUEUE"
        fi
      fi
    fi
    if [ "$RETRIED" = "true" ]; then
      rm -f "$RETRY_QUEUE"
    fi
  ) >/dev/null 2>&1 &
fi

# --- Gather session context in parallel (all background, no blocking) ---
CTX_DIR=$(mktemp -d)

# Time of day
HOUR=$(date +%H)
if [ "$HOUR" -lt 12 ]; then TIME_OF_DAY="morning"
elif [ "$HOUR" -lt 17 ]; then TIME_OF_DAY="afternoon"
else TIME_OF_DAY="evening"
fi

# 1. Recent handoffs (background)
(
  JSON="[]"
  if [ -d "$SCRIPT_DIR/memory/handoffs" ]; then
    FILES=$(ls -t "$SCRIPT_DIR/memory/handoffs/"*.md 2>/dev/null | grep -v index.md | head -3)
    JSON="["
    FIRST=true
    for F in $FILES; do
      [ -z "$F" ] && continue
      NAME=$(basename "$F" .md)
      PREVIEW=$(head -c 120 "$F" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')
      $FIRST || JSON="$JSON,"
      JSON="$JSON{\"name\":\"$NAME\",\"preview\":\"$PREVIEW\"}"
      FIRST=false
    done
    JSON="$JSON]"
  fi
  echo "$JSON" > "$CTX_DIR/handoffs"
) &

# 2. Quests (background)
(
  JSON="[]"
  if [ -d "$SCRIPT_DIR/memory/quests" ]; then
    JSON="["
    FIRST=true
    for F in "$SCRIPT_DIR/memory/quests/"*.md; do
      [ -e "$F" ] || continue
      echo "$F" | grep -q draft && continue
      NAME=$(basename "$F" .md)
      $FIRST || JSON="$JSON,"
      JSON="$JSON\"$NAME\""
      FIRST=false
    done
    JSON="$JSON]"
  fi
  echo "$JSON" > "$CTX_DIR/quests"
) &

# 3. User's last activity (background)
(
  git log --author="$AUTHOR" --format="%ar|%s" -1 2>/dev/null > "$CTX_DIR/activity" || echo "" > "$CTX_DIR/activity"
) &

# 4. Team recent memory commits (background)
(
  JSON="[]"
  if [ -d "$SCRIPT_DIR/memory/.git" ]; then
    JSON="["
    FIRST=true
    while IFS='|' read -r T_AUTHOR T_TIME T_MSG; do
      [ -z "$T_AUTHOR" ] && continue
      T_MSG_ESC=$(echo "$T_MSG" | sed 's/"/\\"/g')
      $FIRST || JSON="$JSON,"
      JSON="$JSON{\"author\":\"$T_AUTHOR\",\"time\":\"$T_TIME\",\"message\":\"$T_MSG_ESC\"}"
      FIRST=false
    done <<< "$(git -C "$SCRIPT_DIR/memory" log --format="%an|%ar|%s" -5 2>/dev/null)"
    JSON="$JSON]"
  fi
  echo "$JSON" > "$CTX_DIR/team"
) &

# 5. Soul self-summary (background)
(
  SUMMARY=""
  if [ -f "$SCRIPT_DIR/egregore.md" ]; then
    SUMMARY=$(sed -n '/^## Self-Summary/,/^##/p' "$SCRIPT_DIR/egregore.md" | sed '1d;/^##/d' | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  fi
  echo "$SUMMARY" > "$CTX_DIR/soul_summary"
) &

# 6. Handoffs addressed to user (background)
(
  JSON="[]"
  if [ -d "$SCRIPT_DIR/memory/handoffs" ]; then
    ADDRESSED=$(grep -rl "to: $AUTHOR\|to:$AUTHOR" "$SCRIPT_DIR/memory/handoffs/" 2>/dev/null | head -5 || true)
    JSON="["
    FIRST=true
    for AF in $ADDRESSED; do
      [ -z "$AF" ] && continue
      AF_NAME=$(basename "$AF" .md)
      $FIRST || JSON="$JSON,"
      JSON="$JSON\"$AF_NAME\""
      FIRST=false
    done
    JSON="$JSON]"
  fi
  echo "$JSON" > "$CTX_DIR/addressed"
) &

# Wait for all context gathering to finish
wait

# --- Output greeting for Claude to display ---
cat << 'GREETING'

  ███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
  ██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
  █████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
  ██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
  ███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
  ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

GREETING

# --- Ornamented status ---
# Humanize repo_name: egregore-0 → Egregore 0
REPO_NAME=$(jq -r '.repo_name // "egregore"' "$SCRIPT_DIR/egregore.json" 2>/dev/null)
INSTANCE_NAME=$(echo "$REPO_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
ORG_NAME=$(jq -r '.org_name // ""' "$SCRIPT_DIR/egregore.json" 2>/dev/null)

# Build the status line with right-aligned org name
SEPARATOR="  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "$SEPARATOR"

# Instance + org line (right-aligned org)
LEFT="  ◈ $INSTANCE_NAME"
RIGHT="$ORG_NAME"
LINE_WIDTH=67
LEFT_LEN=${#LEFT}
RIGHT_LEN=${#RIGHT}
PADDING=$((LINE_WIDTH - LEFT_LEN - RIGHT_LEN))
if [ "$PADDING" -lt 1 ]; then PADDING=1; fi
printf "%s%*s%s\n" "$LEFT" "$PADDING" "" "$RIGHT"

# User + branch + memory line
DISPLAY_NAME=""
if [ -f "$STATE_FILE" ]; then
  DISPLAY_NAME=$(jq -r '.display_name // .name // empty' "$STATE_FILE" 2>/dev/null)
fi
GREETING_NAME="${DISPLAY_NAME:-$AUTHOR}"

BRANCH_STATUS="$BRANCH"
if [ "$ACTION" = "resumed" ]; then
  BRANCH_STATUS="$BRANCH (resumed)"
fi
BRANCH_STATUS="$BRANCH_STATUS · synced"
if [ "$COMMITS_AHEAD" -gt 0 ] 2>/dev/null; then
  BRANCH_STATUS="$BRANCH_STATUS · $COMMITS_AHEAD ahead"
fi

MEMORY_STATUS=""
if [ "$MEMORY_SYNCED" = "true" ]; then
  MEMORY_STATUS="◆ memory · synced"
fi

echo "  ◇ $GREETING_NAME        ⎇ $BRANCH_STATUS        $MEMORY_STATUS"

# Managed repos status
if [ -n "$REPOS_STATUS" ]; then
  printf "$REPOS_STATUS"
fi

# Check for upstream framework updates
UPSTREAM_DIFF=$(git diff HEAD upstream/main -- bin/ .claude/commands/ CLAUDE.md skills/ 2>/dev/null || true)
if [ -n "$UPSTREAM_DIFF" ]; then
  UPDATE_COUNT=$(echo "$UPSTREAM_DIFF" | grep -c '^diff --git' 2>/dev/null || echo "0")
  echo "  ⟳ Framework update available ($UPDATE_COUNT files) — run /update"
fi

echo ""

# --- Session context (hidden, for Claude) ---
CONTEXT_HANDOFFS=$(cat "$CTX_DIR/handoffs" 2>/dev/null || echo "[]")
CONTEXT_ADDRESSED=$(cat "$CTX_DIR/addressed" 2>/dev/null || echo "[]")
CONTEXT_QUESTS=$(cat "$CTX_DIR/quests" 2>/dev/null || echo "[]")
CONTEXT_ACTIVITY=$(cat "$CTX_DIR/activity" 2>/dev/null || echo "")
CONTEXT_TEAM=$(cat "$CTX_DIR/team" 2>/dev/null || echo "[]")
CONTEXT_SOUL=$(cat "$CTX_DIR/soul_summary" 2>/dev/null || echo "")

cat << CTXEOF

<!-- session-context
{
  "time_of_day": "$TIME_OF_DAY",
  "recent_handoffs": $CONTEXT_HANDOFFS,
  "addressed_to_user": $CONTEXT_ADDRESSED,
  "quests": $CONTEXT_QUESTS,
  "last_user_activity": "$CONTEXT_ACTIVITY",
  "team_recent_memory": $CONTEXT_TEAM,
  "soul_self_summary": "$CONTEXT_SOUL"
}
-->
CTXEOF

# Include soul file if present
if [ -f "$SCRIPT_DIR/egregore.md" ]; then
  echo ""
  echo "<!-- egregore-soul"
  cat "$SCRIPT_DIR/egregore.md"
  echo "-->"
fi

# Include latest soul reflection if present
if [ -d "$SCRIPT_DIR/memory/soul" ]; then
  LATEST_REFLECTION=$(ls -t "$SCRIPT_DIR/memory/soul/"*.md 2>/dev/null | head -1 || true)
  if [ -n "$LATEST_REFLECTION" ]; then
    echo "<!-- latest-reflection"
    cat "$LATEST_REFLECTION"
    echo "-->"
  fi
fi

# --- Emit session_start telemetry (background, non-blocking) ---
bash "$SCRIPT_DIR/bin/telemetry.sh" emit "session_start" \
  "$(jq -n --arg branch "$BRANCH" '{branch: $branch}')" 2>/dev/null &

# Clean up temp files
rm -rf "$CTX_DIR"

# --- First session welcome ---
if [ -z "$FIRST_SESSION" ] && [ -f "$STATE_FILE" ]; then
  FIRST_SESSION=$(jq -r '.first_session // false' "$STATE_FILE" 2>/dev/null)
fi

if [ "$FIRST_SESSION" = "true" ]; then
  echo ""
  echo "  Welcome! This is your first session."
  echo ""
  echo "IMPORTANT: Display the above greeting exactly as-is (ASCII art + ornamented status). Then ask the user if they'd like a quick onboarding tour (run /onboarding), or if they want to jump straight in."
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
  echo "IMPORTANT: Display the above greeting to the user exactly as-is (preserve the ASCII art formatting and ornamented status) on their first message. Then ask: What are you working on?"
  echo ""
  echo "BRANCH RULE: When the user responds with what they're working on, your FIRST action is to create a working branch: git fetch origin develop --quiet && git checkout -b dev/{author}/{topic-slug} origin/develop. Do this BEFORE any other work. Derive the topic slug from their description. If they ask a pure question with no work intent, skip branching."
fi
