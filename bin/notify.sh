#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SCRIPT_DIR/egregore.json"

if [ ! -f "$CONFIG" ]; then
  echo "Error: egregore.json not found." >&2
  exit 1
fi

# Env vars override egregore.json (for production tokens not stored in repo)
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$(jq -r '.telegram_bot_token' "$CONFIG")}"
CHAT_ID="${TELEGRAM_CHAT_ID:-$(jq -r '.telegram_chat_id' "$CONFIG")}"

# Source .env if it exists (for local overrides)
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
  BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$BOT_TOKEN}"
  CHAT_ID="${TELEGRAM_CHAT_ID:-$CHAT_ID}"
fi

if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "null" ]; then
  echo "Error: TELEGRAM_BOT_TOKEN not set (env var or egregore.json)" >&2
  exit 1
fi

send_message() {
  local chat_id="$1"
  local text="$2"

  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg chat_id "$chat_id" --arg text "$text" \
      '{chat_id: $chat_id, text: $text, parse_mode: "Markdown"}')" \
    | jq -r 'if .ok then "Sent" else "Failed: " + .description end'
}

lookup_telegram_id() {
  local name="$1"
  bash "$SCRIPT_DIR/bin/graph.sh" query \
    "MATCH (p:Person {name: \$name}) RETURN p.telegramId AS tid" \
    "{\"name\": \"$name\"}" \
    | jq -r '.values[0][0] // empty'
}

case "${1:-help}" in
  send)
    # Send to a person by name (DM if telegramId exists, group fallback)
    recipient="${2:?Usage: notify.sh send <name> <message>}"
    message="${3:?Usage: notify.sh send <name> <message>}"

    tid=$(lookup_telegram_id "$recipient")
    if [ -n "$tid" ] && [ "$tid" != "null" ]; then
      send_message "$tid" "$message"
    elif [ -n "$CHAT_ID" ] && [ "$CHAT_ID" != "null" ]; then
      send_message "$CHAT_ID" "📨 @${recipient}: ${message}"
    else
      echo "No Telegram ID for $recipient and no group chat configured" >&2
      exit 1
    fi
    ;;
  group)
    # Send to the group chat
    message="${2:?Usage: notify.sh group <message>}"
    if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "null" ]; then
      echo "Error: telegram_chat_id not set in egregore.json" >&2
      exit 1
    fi
    send_message "$CHAT_ID" "$message"
    ;;
  file)
    # Send a file to group chat with optional caption
    filepath="${2:?Usage: notify.sh file <path> [caption]}"
    caption="${3:-}"
    if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "null" ]; then
      echo "Error: telegram_chat_id not set in egregore.json" >&2
      exit 1
    fi
    if [ ! -f "$filepath" ]; then
      echo "Error: file not found: $filepath" >&2
      exit 1
    fi
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
      -F "chat_id=$CHAT_ID" \
      -F "document=@$filepath" \
      -F "caption=$caption" \
      -F "parse_mode=Markdown" \
      | jq -r 'if .ok then "Sent" else "Failed: " + .description end'
    ;;
  test)
    if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "null" ]; then
      echo "Error: telegram_chat_id not set" >&2
      exit 1
    fi
    send_message "$CHAT_ID" "✓ Egregore connected"
    ;;
  help|*)
    echo "Usage: notify.sh <command>"
    echo ""
    echo "Commands:"
    echo "  send <name> <message>   Send to a person (DM or group fallback)"
    echo "  group <message>         Send to the group chat"
    echo "  file <path> [caption]   Send a file to the group chat"
    echo "  test                    Test connection"
    ;;
esac
