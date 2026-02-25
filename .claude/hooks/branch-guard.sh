#!/bin/bash
# branch-guard.sh — PreToolUse hook blocking modifications on protected branches
# Receives tool input JSON on stdin from Claude Code.
# Exit 0 = allow, exit 2 = block (reason on stderr).
# Must be fast (<50ms) — no network calls, just path/branch checks.

# No set -e — hook must never accidentally block by crashing
# If anything fails unexpectedly, fall through to exit 0 (allow)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# --- Get current branch ---
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0

# Only guard protected branches
case "$BRANCH" in
  develop|main|master) ;;
  *) exit 0 ;;
esac

# --- Read tool input from stdin ---
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true

if [ -z "$TOOL_NAME" ]; then
  exit 0
fi

# --- Read author from state file ---
AUTHOR=$(jq -r '.display_name // .name // "dev"' "$PROJECT_DIR/.egregore-state.json" 2>/dev/null) || AUTHOR="dev"

# --- Resolve memory directory (for exemption checks) ---
MEMORY_DIR=$(realpath "$PROJECT_DIR/memory" 2>/dev/null || echo "$PROJECT_DIR/memory")

# --- Helper: check if path is exempt from branch guard ---
is_exempt() {
  local path="$1"

  # Resolve relative paths
  if [[ "$path" != /* ]]; then
    path="$PROJECT_DIR/$path"
  fi

  # Resolve symlinks
  local resolved
  resolved=$(realpath "$path" 2>/dev/null || echo "$path")

  # Exempt: .claude/ directory
  case "$resolved" in
    "$PROJECT_DIR/.claude"/*|"$PROJECT_DIR/.claude") return 0 ;;
  esac

  # Exempt: .egregore-state.json
  if [[ "$resolved" == "$PROJECT_DIR/.egregore-state.json" ]]; then
    return 0
  fi

  # Exempt: .env
  if [[ "$resolved" == "$PROJECT_DIR/.env" ]]; then
    return 0
  fi

  # Exempt: memory/ (resolve symlink to check both the link and target)
  if [[ "$resolved" == "$PROJECT_DIR/memory"/* || "$resolved" == "$PROJECT_DIR/memory" ]]; then
    return 0
  fi
  if [[ "$resolved" == "$MEMORY_DIR"/* || "$resolved" == "$MEMORY_DIR" ]]; then
    return 0
  fi

  # Exempt: /tmp/
  case "$resolved" in
    /tmp/*|/tmp|/private/tmp/*|/private/tmp) return 0 ;;
  esac

  return 1
}

# --- Helper: check if bash command targets a non-hub repo ---
# Returns 0 (true) if the git command operates on memory/ or a managed repo
targets_other_repo() {
  local cmd="$1"

  # Memory repo: "cd memory", "cd $PROJECT_DIR/memory", "git -C memory", "git -C $MEMORY_DIR"
  if echo "$cmd" | grep -qE "(cd\s+[\"']?($PROJECT_DIR/)?memory|git\s+-C\s+[\"']?($PROJECT_DIR/)?memory|git\s+-C\s+[\"']?$MEMORY_DIR)" 2>/dev/null; then
    return 0
  fi

  # Managed repos: "git -C ../{repo}", "cd ../{repo}"
  local repos
  repos=$(jq -r '.repos[]? // empty' "$PROJECT_DIR/egregore.json" 2>/dev/null) || true
  for repo in $repos; do
    if echo "$cmd" | grep -qE "(cd\s+[\"']?(\.\./|$PROJECT_DIR/../)$repo|git\s+-C\s+[\"']?(\.\./|$PROJECT_DIR/../)$repo)" 2>/dev/null; then
      return 0
    fi
  done

  return 1
}

# --- Block message (short — Claude knows what to do from CLAUDE.md) ---
BLOCK_MSG="Protected branch: create a working branch first. Run: git fetch origin develop --quiet && git checkout -b dev/${AUTHOR}/{topic-slug} origin/develop"

# --- Check based on tool type ---
case "$TOOL_NAME" in
  Edit|Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true
    if [ -z "${FILE_PATH:-}" ]; then
      exit 0
    fi

    if ! is_exempt "$FILE_PATH"; then
      echo "$BLOCK_MSG" >&2
      exit 2
    fi
    ;;

  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
    if [ -z "${COMMAND:-}" ]; then
      exit 0
    fi

    # Only check commands that contain git commit or git push
    if echo "$COMMAND" | grep -qE 'git\s+(commit|push)' 2>/dev/null; then
      # Allow if targeting memory/ or a managed repo (separate repos, own branch model)
      if targets_other_repo "$COMMAND"; then
        exit 0
      fi
      echo "$BLOCK_MSG" >&2
      exit 2
    fi
    ;;

  *)
    exit 0
    ;;
esac

# Default: allow
exit 0
