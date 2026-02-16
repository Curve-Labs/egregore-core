#!/bin/bash
# One-time backfill: archive existing session transcripts to egregore-transcripts repo.
# Iterates over all .jsonl files in the Claude Code project directory.
# Rate-limited: batch commits to avoid git churn.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SCRIPT_DIR/egregore.json"
STATE_FILE="$SCRIPT_DIR/.egregore-state.json"
TRANSCRIPTS_DIR="$SCRIPT_DIR/../egregore-transcripts"

# --- Preflight checks ---
if [ ! -f "$CONFIG" ]; then
  echo "Error: Missing egregore.json"
  exit 1
fi

if [ ! -d "$TRANSCRIPTS_DIR/.git" ]; then
  echo "Error: Transcripts repo not found at $TRANSCRIPTS_DIR"
  echo "Clone it first: git clone https://github.com/Curve-Labs/egregore-transcripts.git ../egregore-transcripts"
  exit 1
fi

GITHUB_ORG=$(jq -r '.github_org // empty' "$CONFIG" 2>/dev/null)
SLUG=$(echo "$GITHUB_ORG" | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d ' ')
if [ -z "$SLUG" ]; then
  echo "Error: Could not determine org slug"
  exit 1
fi

AUTHOR=""
if [ -f "$STATE_FILE" ]; then
  AUTHOR=$(jq -r '.github_username // empty' "$STATE_FILE" 2>/dev/null)
  # Sanitize: GitHub usernames are alphanumeric + hyphens only
  AUTHOR=$(echo "$AUTHOR" | tr -cd 'a-zA-Z0-9_-')
fi

# --- Find Claude Code project directory ---
CLAUDE_DIR="$HOME/.claude/projects"
if [ ! -d "$CLAUDE_DIR" ]; then
  echo "No Claude Code projects directory found."
  exit 0
fi

# Pull latest to avoid conflicts
git -C "$TRANSCRIPTS_DIR" pull origin main --quiet 2>/dev/null || true

# --- Process all JSONL session files ---
echo "Scanning for session transcripts..."

# Use process substitution to avoid subshell variable scoping issue
ARCHIVED=0
SKIPPED=0
while read -r TRANSCRIPT_PATH; do
  SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)

  # Skip tiny files
  FILE_SIZE=$(wc -c < "$TRANSCRIPT_PATH" | tr -d ' ')
  if [ "$FILE_SIZE" -lt 100 ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Compute storage path
  STARTED_AT=$(head -1 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.timestamp // empty' 2>/dev/null || echo "")
  if [ -n "$STARTED_AT" ]; then
    MONTH=$(echo "$STARTED_AT" | grep -oE '^[0-9]{4}-[0-9]{2}' || date -u +%Y-%m)
  else
    MONTH=$(date -u +%Y-%m)
  fi

  DEST_DIR="$TRANSCRIPTS_DIR/transcripts/$SLUG/$MONTH"
  DEST_FILE="$DEST_DIR/${SESSION_ID}.jsonl.gz"

  # Skip if already archived
  if [ -f "$DEST_FILE" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Gzip into place
  mkdir -p "$DEST_DIR"
  if gzip -c "$TRANSCRIPT_PATH" > "$DEST_FILE" 2>/dev/null; then
    echo "  OK:   $SESSION_ID ($MONTH)"
    ARCHIVED=$((ARCHIVED + 1))
  else
    echo "  FAIL: $SESSION_ID"
    rm -f "$DEST_FILE"
  fi
done < <(find "$CLAUDE_DIR" -name "*.jsonl" -type f | sort)

echo ""
echo "Archived: $ARCHIVED, Skipped: $SKIPPED"

# --- Single batch commit + push ---
# Also check git status in case files exist but weren't committed
HAS_CHANGES=$(git -C "$TRANSCRIPTS_DIR" status --porcelain transcripts/ 2>/dev/null | head -1)
if [ "$ARCHIVED" -gt 0 ] || [ -n "$HAS_CHANGES" ]; then
  echo "Committing and pushing..."
  cd "$TRANSCRIPTS_DIR"
  git add transcripts/ 2>/dev/null
  git commit -m "Backfill $ARCHIVED session transcripts" \
    --author="${AUTHOR:-egregore} <${AUTHOR:-egregore}@users.noreply.github.com>" \
    2>/dev/null || echo "Nothing to commit"
  git push origin main 2>/dev/null || echo "Push failed — retry manually"
  echo "Done."
else
  echo "Nothing new to archive."
fi
