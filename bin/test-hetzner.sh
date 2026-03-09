#!/bin/bash
if [ -z "$HETZNER_API_TOKEN" ]; then
  echo "Set HETZNER_API_TOKEN first"
  exit 1
fi

H="Authorization: Bearer $HETZNER_API_TOKEN"
BASE="https://api.hetzner.cloud/v1"

echo "=== Minimal create test ==="

# Absolute minimum — no labels, no user_data, no location
TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'EOF'
{"name":"egregore-test-min","server_type":"cax11","image":"ubuntu-24.04"}
EOF

echo "Request body:"
cat "$TMPFILE"
echo ""

HTTP_CODE=$(curl -s -o /tmp/hetzner-resp.json -w "%{http_code}" -X POST "$BASE/servers" \
  -H "$H" -H "Content-Type: application/json" -d @"$TMPFILE")

echo "HTTP $HTTP_CODE"
cat /tmp/hetzner-resp.json | jq .

rm -f "$TMPFILE"

if [ "$HTTP_CODE" = "201" ]; then
  SERVER_ID=$(cat /tmp/hetzner-resp.json | jq -r '.server.id')
  IP=$(cat /tmp/hetzner-resp.json | jq -r '.server.public_net.ipv4.ip')
  LOC=$(cat /tmp/hetzner-resp.json | jq -r '.server.datacenter.location.name')
  echo ""
  echo "Success! Server $SERVER_ID at $IP ($LOC)"
  echo "Deleting test server..."
  curl -s -X DELETE "$BASE/servers/$SERVER_ID" -H "$H" | jq .
  echo "Cleaned up."
fi

rm -f /tmp/hetzner-resp.json
