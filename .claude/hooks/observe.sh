#!/bin/bash
# PostToolUse observation hook — fires after Edit, Write, Bash, NotebookEdit.
# Appends one JSONL line per invocation to a per-session buffer file.
# No jq, no network, always exit 0. Observe layer — never blocks.

# No set -e — must never accidentally block by crashing
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# --- Read session ID (written by session-start.sh) ---
SESSION_ID=""
SID_FILE="$PROJECT_DIR/.egregore-session-id"
if [ -f "$SID_FILE" ]; then
  SESSION_ID=$(cat "$SID_FILE" 2>/dev/null) || true
fi
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

BUFFER="/tmp/egregore-obs-${SESSION_ID}.jsonl"

# --- Buffer guard: cap at 500KB ---
if [ -f "$BUFFER" ]; then
  SIZE=$(wc -c < "$BUFFER" 2>/dev/null | tr -d ' ')
  if [ "${SIZE:-0}" -gt 512000 ] 2>/dev/null; then
    exit 0
  fi
fi

# --- Read tool input from stdin ---
INPUT=$(cat 2>/dev/null) || exit 0

# Extract tool_name using grep/sed (no jq — saves ~15ms per invocation)
TOOL=$(echo "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:.*"\([^"]*\)"/\1/')
if [ -z "$TOOL" ]; then
  exit 0
fi

# --- Extract file path based on tool type ---
PATH_VALUE=""
case "$TOOL" in
  Edit|Write)
    PATH_VALUE=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:.*"\([^"]*\)"/\1/')
    ;;
  NotebookEdit)
    PATH_VALUE=$(echo "$INPUT" | grep -o '"notebook_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:.*"\([^"]*\)"/\1/')
    ;;
  Bash)
    # Best-effort: extract first path-like token from command
    CMD=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:.*"\([^"]*\)"/\1/')
    PATH_VALUE=$(echo "$CMD" | grep -oE '(/[a-zA-Z0-9_./-]+|[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,10})' | head -1)
    ;;
esac

# Strip project directory prefix for relative paths
if [ -n "$PATH_VALUE" ] && [ -n "$PROJECT_DIR" ]; then
  PATH_VALUE="${PATH_VALUE#$PROJECT_DIR/}"
fi

if [ -z "$PATH_VALUE" ]; then
  PATH_VALUE="unknown"
fi

# --- Timestamp ---
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Append JSONL line (O(1) local write) ---
echo "{\"ts\":\"$TS\",\"tool\":\"$TOOL\",\"path\":\"$PATH_VALUE\"}" >> "$BUFFER" 2>/dev/null

exit 0
