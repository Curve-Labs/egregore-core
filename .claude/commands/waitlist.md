# Waitlist

View and manage the Egregore waitlist.

## Usage

Run with no arguments to list pending entries, or pass a subcommand.

## Instructions

Read `GITHUB_TOKEN` from `.env`:
```bash
GITHUB_TOKEN=$(grep '^GITHUB_TOKEN=' .env | cut -d'=' -f2-)
```

Read `api_url` from `egregore.json`:
```bash
API_URL=$(jq -r '.api_url' egregore.json)
```

### Default (no args): list pending entries

```bash
curl -s "$API_URL/api/admin/waitlist?status=pending" -H "Authorization: Bearer $GITHUB_TOKEN"
```

Display as a clean table: #, Name, Email, Intent, Date. Skip entries that look like tests (test@test.com, "deploy-test", "cli-test"). Show the count of real entries.

### `approve <id>`

```bash
curl -s -X POST "$API_URL/api/admin/waitlist/approve" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"waitlist_id": <id>}'
```

Confirm before approving. Show who you're approving (name + email).

### `all`

Show all entries across all statuses (pending, approved, rejected). Run three queries in parallel and combine.

## Auth

Uses your GitHub token — only works for admin users (oguzhan, fcdagdelen).
