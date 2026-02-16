# Developer Reference

Internal operations guide for Egregore infrastructure. Not synced to the public repo.

---

## Neo4j Architecture

### Two databases, by design

Railway has two sets of Neo4j env vars — these are **intentionally separate**:

| Env var | Aura ID | Tier | Purpose |
|---|---|---|---|
| `NEO4J_HOST` / `NEO4J_USER` / `NEO4J_PASSWORD` | `c02bbdac` | AuraDB Free | **Curve Labs private.** CL's own Egregore data only. |
| `EGREGORE_NEO4J_HOST` / `EGREGORE_NEO4J_USER` / `EGREGORE_NEO4J_PASSWORD` | `668bb747` | AuraDB Business Critical | **Customer database.** All orgs created via setup use this. |

Within each database, tenant isolation is done at the query level via `inject_org_scope()` — every labeled node gets `{org: $_org}` injected automatically.

### How it works

1. **Startup**: `load_org_configs()` in `api/auth.py` builds the `curvelabs` entry using `NEO4J_HOST` (→ `c02bbdac`).
2. **Customer org reload**: `load_orgs_from_neo4j()` connects to `EGREGORE_NEO4J_HOST` (→ `668bb747`) to load all customer `Org` nodes into `ORG_CONFIGS`. Each inherits the customer database creds.
3. **Setup**: New orgs created via `/api/org/setup` get `EGREGORE_NEO4J_HOST` creds directly — never CL's private instance.
4. **Runtime**: Every query goes through `execute_query()` using the org's own `neo4j_host` from its config. CL queries hit `c02bbdac`, customer queries hit `668bb747`.
5. **Cross-org queries** (user profile endpoints): `_get_seed_org()` prefers `EGREGORE_NEO4J_HOST` since these are customer-facing web UI endpoints.

### Org scoping internals

`inject_org_scope()` in `api/services/graph.py`:
- Adds `org: $_org` to every `(var:Label {props})` and bare `(var:Label)` pattern
- Skips system labels defined in `SYSTEM_LABELS = {"Org", "TelegramUser"}`
- Skips `CALL` statements entirely
- The `_org` parameter is set to the org's slug before every query

The guard layer (`api/services/guard.py`):
- **Blocked tokens**: `DELETE`, `DETACH`, `DROP`, `REMOVE` — Egregore is append-only
- **Blocked pairs**: `CREATE INDEX`, `CREATE CONSTRAINT`
- **Blocked parameters**: `_org`, `org` — clients can't set these
- **Allowlisted procedures**: `db.schema.visualization`, `db.labels`, etc.
- **Rate limit**: 120 queries per 60 seconds per org

### Important: `execute_query` error handling

`execute_query()` returns `{"error": ...}` on failure — it does **not** throw exceptions. If you need to detect failures:

```python
result = await execute_query(org, "MERGE ...")
if "error" in result:
    logger.error(f"Query failed: {result['error']}")
```

A `try/except` around `execute_query` only catches network/connection errors, not Neo4j query errors.

---

## ORG_CONFIGS Lifecycle

`ORG_CONFIGS` is the central in-memory dict that maps org slugs to their config (API key, Neo4j creds, Telegram tokens, etc.).

```
Startup:
  1. load_org_configs()     — builds from env vars (CURVELABS_API_KEY, ORG_CONFIGS JSON, EGREGORE_ORGS)
  2. load_orgs_from_neo4j() — queries Neo4j for Org nodes, adds/updates entries in ORG_CONFIGS

Runtime:
  3. /api/org/setup         — adds new org to ORG_CONFIGS in-memory + writes Org node to Neo4j
  4. /api/admin/reload      — re-runs load_orgs_from_neo4j() (any valid API key required)

Restart:
  - In-memory ORG_CONFIGS is rebuilt from steps 1+2
  - If Neo4j write failed during setup, the org is LOST on restart
  - Org nodes without api_key are skipped during load (line 135 in auth.py)
```

### Checking loaded orgs

```bash
# From an egregore instance with a valid API key:
curl -s -H "Authorization: Bearer $API_KEY" \
  https://egregore-production-55f2.up.railway.app/api/org/status

# Force reload from Neo4j:
curl -s -X POST -H "Authorization: Bearer $API_KEY" \
  https://egregore-production-55f2.up.railway.app/api/admin/reload
```

---

## Running Tests

Tests live in `tests/` with their own `pyproject.toml` and uv-managed venv.

### Quick start

```bash
# Run all tests (from repo root)
cd tests && uv run python -m pytest

# Run specific test file
cd tests && uv run python -m pytest test_install_flows.py

# Run specific test class or method
cd tests && uv run python -m pytest test_install_flows.py::TestFounderSetup::test_founder_setup_creates_org

# Run by marker
cd tests && uv run python -m pytest -m api        # API endpoint tests
cd tests && uv run python -m pytest -m security    # Security/guard tests
cd tests && uv run python -m pytest -m isolation   # Tenant isolation tests
```

### Why uv, not pytest directly

The system Python (pyenv) has a broken libintl dependency on this machine. `uv run` manages its own Python and venv in `tests/.venv/`, sidestepping the issue entirely.

### Test structure

| File | What it tests | Marker |
|---|---|---|
| `test_install_flows.py` | Founder setup, joiner, token claim | `api` |
| `test_full_flow.py` | Full E2E: setup + invite + accept + join | `api`, `flow` |
| `test_invite_flow.py` | Invite + accept edge cases | `api` |
| `test_guard.py` | Query validation, blocked operations | `security` |
| `test_org_scope.py` | `inject_org_scope()` transformations | `security` |
| `test_tenant_isolation.py` | Cross-tenant query isolation | `isolation` |
| `test_tokens.py` | Setup/invite token lifecycle | `api` |
| `test_security.py` | API auth, key validation | `security` |
| `test_capture.py` | Memory capture reliability | `capture` |
| `test_sync.py` | Git sync accuracy | `sync` |
| `test_retrieval.py` | Knowledge retrieval | `retrieval` |
| `test_quality.py` | Data quality checks | `quality` |

### Mocking

API tests mock all external calls with **respx** (HTTP-level mocking for httpx). No real GitHub/Neo4j/Telegram calls. See `conftest.py` for test org constants (`ALPHA_CONFIG`, `BETA_CONFIG`) and the `_patch_org_configs` fixture.

### Adding a new API test

1. Use `app_client` fixture for the FastAPI TestClient
2. Use `_patch_org_configs` if you need to control ORG_CONFIGS
3. Mock GitHub API calls with `@respx.mock` + `respx.get(url).mock(...)`
4. Mock Neo4j calls with `respx.post(url__regex=r"https://neo4j.*").mock(...)`
5. Mark with `@pytest.mark.api`

---

## Git Workflow

### Branch model

```
main ← stable releases (protected, only via /release)
  │
  develop ← integration branch (PRs land here)
    │
    dev/{author}/{date}-session ← working branches
```

### Common operations

```bash
# Session start (done automatically by hook)
bin/session-start.sh

# Push + PR to develop
/save

# Merge develop → main (maintainer only)
/release

# Sync public repo (one-way: curve-labs-core → egregore-core)
/sync-public        # full sync + commit + push
/sync-public dry    # show what would change
/sync-public diff   # show current diff
```

### Deploying to Railway

Railway auto-deploys from main. The workflow:

```bash
# 1. Work on your branch
#    (code changes, test, etc.)

# 2. Push and create PR to develop
/save

# 3. Merge to develop (auto-merge for markdown-only, review for code)
#    Then merge develop → main:
git checkout main && git merge develop && git push origin main

# 4. Railway picks up the push and deploys
#    Check: https://egregore-production-55f2.up.railway.app/health
```

### When gh CLI auth expires

If `gh pr create` returns 401, merge directly:

```bash
git checkout develop && git merge your-branch && git push origin develop
git checkout main && git merge develop && git push origin main
```

---

## Admin Operations

### Viewing Neo4j data

```bash
# From any configured egregore instance:
bash bin/graph.sh test
bash bin/graph.sh schema
bash bin/graph.sh query "MATCH (o:Org) RETURN o.id, o.name, o.github_org"
bash bin/graph.sh query "MATCH (p:Person) RETURN p.name, p.org, p.github"
```

### Stale Org nodes

Old test installations leave behind Org nodes in Neo4j. They're harmless — `load_orgs_from_neo4j()` skips any Org without an `api_key`. But they accumulate.

**Why we can't just delete them**: The guard layer blocks `DELETE` operations (append-only by design). The `_BLOCKED_TOKENS` in `api/services/guard.py` include `DELETE` and `DETACH`.

**Current approach**: Soft-ignore. Stale Org nodes without `api_key` are filtered out during startup load. They take up negligible space.

**To actually clean up** (requires direct Neo4j access, bypassing the API):

```
# Connect to Neo4j Aura console directly
# CL data: c02bbdac  |  Customer data: 668bb747
# In the Neo4j Browser:
MATCH (o:Org) WHERE o.api_key IS NULL RETURN o.id, o.name
# Review, then:
MATCH (o:Org) WHERE o.api_key IS NULL DETACH DELETE o
```

Or to remove a specific test org:
```
MATCH (o:Org {id: "oguzhan"}) DETACH DELETE o
```

**Future option**: Add an admin endpoint that bypasses the guard for Org cleanup only, authenticated with a dedicated admin secret.

### Checking an org's config on the server

```bash
# Health check
curl -s https://egregore-production-55f2.up.railway.app/health

# Org status (requires org's API key)
curl -s -H "Authorization: Bearer ek_slug_key" \
  https://egregore-production-55f2.up.railway.app/api/org/status

# Force reload all orgs from Neo4j
curl -s -X POST -H "Authorization: Bearer ek_slug_key" \
  https://egregore-production-55f2.up.railway.app/api/admin/reload
```

### Debugging a failed setup

If someone creates an org and the invite/accept flow can't find the API key:

1. **Check Neo4j**: Does the Org node exist with an `api_key`?
   ```bash
   bash bin/graph.sh query "MATCH (o:Org {id: 'the-slug'}) RETURN o.id, o.api_key IS NOT NULL AS has_key"
   ```

2. **Check ORG_CONFIGS**: Is it loaded?
   ```bash
   curl -s -H "Authorization: Bearer any_valid_key" \
     https://egregore-production-55f2.up.railway.app/api/admin/reload
   ```

3. **Common causes**:
   - Neo4j bootstrap failed silently during setup (check Railway logs for "Neo4j Org bootstrap error")
   - API restarted between setup and invite (Org node missing → not reloaded)
   - Wrong Neo4j database (setup should write to `668bb747`, not `c02bbdac`)

### Railway env vars (what's needed)

| Var | Purpose | Notes |
|---|---|---|
| `NEO4J_HOST` | CL's private Neo4j | `c02bbdac.databases.neo4j.io` |
| `NEO4J_USER` | CL Neo4j username | `neo4j` |
| `NEO4J_PASSWORD` | CL Neo4j password | |
| `EGREGORE_NEO4J_HOST` | Customer shared Neo4j | `668bb747.databases.neo4j.io` |
| `EGREGORE_NEO4J_USER` | Customer Neo4j username | `neo4j` |
| `EGREGORE_NEO4J_PASSWORD` | Customer Neo4j password | |
| `CURVELABS_API_KEY` | Curve Labs org API key | Seeds the first ORG_CONFIG |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth app secret | For web auth flow |
| `TELEGRAM_BOT_TOKEN` | Shared Telegram bot | All orgs share one bot |
| `EGREGORE_API_URL` | Public API URL | `https://egregore-production-55f2.up.railway.app` |
| `EGREGORE_SITE_URL` | Frontend URL | `https://egregore-core.netlify.app` |
| `CORS_ORIGINS` | Allowed browser origins | Comma-separated |

---

## Fork + Rename Pattern

GitHub limits one fork per source repo per account. Since users may create multiple Egregore instances (e.g., `egregore-fun`, `egregore-work`), we use fork + rename:

1. Fork `Curve-Labs/egregore-core` → creates `{owner}/egregore-core`
2. Rename `egregore-core` → `egregore-{instance_name}`
3. Now `{owner}/egregore-core` is "free" again for the next fork

This preserves the upstream link (users can pull updates from `Curve-Labs/egregore-core`), unlike template generation which creates a disconnected copy.

**Setup endpoint flow** (`/api/org/setup`):
```
fork_repo() → wait_for_fork() → rename_repo() (if named instance) → create memory repo → update egregore.json → bootstrap Neo4j Org node → return setup token
```

The setup is idempotent: if the repo already exists, it skips forking and continues with the rest.
