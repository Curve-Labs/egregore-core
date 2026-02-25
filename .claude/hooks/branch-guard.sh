#!/bin/bash
# branch-guard.sh — PreToolUse hook blocking modifications on protected branches
# Receives tool input JSON on stdin from Claude Code.
# Exit 0 = allow, exit 2 = block (reason on stderr).
# Must be fast (<50ms) — no network calls, just path/branch checks.
#
# When blocked, the stderr message instructs Claude (not the user) to
# create a working branch before retrying. The user never sees git.

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

# --- Helper: check if path is exempt from branch guard ---
is_exempt() {
  local path="$1"

  # Resolve relative paths
  if [[ "$path" != /* ]]; then
    path="$PROJECT_DIR/$path"
  fi

  # Resolve symlinks for memory/ check
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
  local memory_resolved
  memory_resolved=$(realpath "$PROJECT_DIR/memory" 2>/dev/null || echo "$PROJECT_DIR/memory")
  if [[ "$resolved" == "$PROJECT_DIR/memory"/* || "$resolved" == "$PROJECT_DIR/memory" ]]; then
    return 0
  fi
  if [[ "$resolved" == "$memory_resolved"/* || "$resolved" == "$memory_resolved" ]]; then
    return 0
  fi

  # Exempt: /tmp/
  case "$resolved" in
    /tmp/*|/tmp) return 0 ;;
  esac

  return 1
}

# --- Block message (targets Claude, not the user) ---
BLOCK_MSG="BRANCH GUARD: You are on '$BRANCH' which is a protected branch. You MUST create a working branch before modifying files or committing. Do this now:
1. Tell the user: \"I need to create a working branch before making changes. What are you working on?\" (or derive a topic from conversation context if already clear)
2. Run: git fetch origin develop --quiet && git checkout -b dev/${AUTHOR}/{topic-slug} origin/develop
3. Then retry your operation.
NEVER tell the user to run git commands — handle it yourself. The user does not interact with git."

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

    # Block git commit and git push on protected branches
    if echo "$COMMAND" | grep -qE '(^|[;&|]\s*)git\s+(commit|push)' 2>/dev/null; then
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
