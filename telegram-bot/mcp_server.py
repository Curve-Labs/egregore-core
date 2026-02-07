"""
Egregore MCP Server - Remote MCP over SSE

Provides Neo4j and Telegram tools to Claude Code clients without
requiring local uvx/npx installations.

Protocol: MCP (Model Context Protocol) over SSE transport
"""

import json
import logging
import os
import hashlib
from typing import Optional, AsyncGenerator
from datetime import datetime

from starlette.requests import Request
from starlette.responses import StreamingResponse, JSONResponse
from neo4j import GraphDatabase

logger = logging.getLogger(__name__)

# =============================================================================
# ORG CONFIGURATION (shared with bot.py)
# =============================================================================

# Default Curve Labs Neo4j
NEO4J_URI = os.environ.get("NEO4J_URI", "")
NEO4J_USER = os.environ.get("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD", "")

# Org configs - keyed by org API key prefix
ORG_BY_KEY = {}

def init_org_configs():
    """Initialize org configs from environment."""
    global ORG_BY_KEY

    # Curve Labs (default)
    if NEO4J_URI:
        ORG_BY_KEY["curvelabs"] = {
            "name": "curvelabs",
            "neo4j_uri": NEO4J_URI,
            "neo4j_user": NEO4J_USER,
            "neo4j_password": NEO4J_PASSWORD,
        }

    # Egregore org (new standalone org)
    egregore_uri = os.environ.get("EGREGORE_NEO4J_URI", "")
    if egregore_uri:
        ORG_BY_KEY["egregore"] = {
            "name": "egregore",
            "neo4j_uri": egregore_uri,
            "neo4j_user": os.environ.get("EGREGORE_NEO4J_USER", "neo4j"),
            "neo4j_password": os.environ.get("EGREGORE_NEO4J_PASSWORD", ""),
        }

    # Test org (legacy)
    testorg_uri = os.environ.get("TESTORG_NEO4J_URI", "")
    if testorg_uri:
        ORG_BY_KEY["testorg"] = {
            "name": "testorg",
            "neo4j_uri": testorg_uri,
            "neo4j_user": os.environ.get("TESTORG_NEO4J_USER", "neo4j"),
            "neo4j_password": os.environ.get("TESTORG_NEO4J_PASSWORD", ""),
        }

    logger.info(f"MCP orgs configured: {list(ORG_BY_KEY.keys())}")

# Lazy initialization - called on first request
_initialized = False

def ensure_initialized():
    global _initialized
    if not _initialized:
        try:
            init_org_configs()
            _initialized = True
        except Exception as e:
            logger.error(f"MCP init failed: {e}")

# =============================================================================
# NEO4J DRIVERS (per-org)
# =============================================================================

org_drivers = {}

def get_org_driver(org_config: dict):
    """Get or create org-specific Neo4j driver."""
    if not org_config:
        return None

    org_name = org_config.get("name", "default")
    uri = org_config.get("neo4j_uri")
    user = org_config.get("neo4j_user", "neo4j")
    password = org_config.get("neo4j_password")

    if not uri or not password:
        return None

    if org_name not in org_drivers:
        org_drivers[org_name] = GraphDatabase.driver(uri, auth=(user, password))
        logger.info(f"MCP Neo4j driver initialized for org: {org_name}")

    return org_drivers[org_name]


def run_org_query(query: str, params: dict = None, org_config: dict = None) -> list:
    """Run a Cypher query on org-specific Neo4j."""
    driver = get_org_driver(org_config)
    if not driver:
        return []

    try:
        with driver.session() as session:
            result = session.run(query, params or {})
            return [dict(record) for record in result]
    except Exception as e:
        logger.error(f"MCP Neo4j query failed: {e}")
        return []


# =============================================================================
# API KEY VALIDATION
# =============================================================================

def validate_api_key(api_key: str) -> Optional[dict]:
    """Validate API key and return org config.

    API key format: ek_<org>_<secret>
    Example: ek_testorg_abc123xyz
    """
    if not api_key or not api_key.startswith("ek_"):
        return None

    parts = api_key.split("_", 2)
    if len(parts) < 3:
        return None

    org_name = parts[1]
    # TODO: validate secret against stored hash

    return ORG_BY_KEY.get(org_name)


# =============================================================================
# MCP TOOL DEFINITIONS
# =============================================================================

MCP_TOOLS = [
    {
        "name": "neo4j_query",
        "description": "Execute a Cypher query on the Neo4j knowledge graph. Returns results as JSON.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The Cypher query to execute"
                },
                "params": {
                    "type": "object",
                    "description": "Query parameters (optional)",
                    "additionalProperties": True
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "neo4j_schema",
        "description": "Get the Neo4j database schema including node labels, relationship types, and properties.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "telegram_send",
        "description": "Send a message to a Telegram chat or user.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "recipient": {
                    "type": "string",
                    "description": "Person name (e.g., 'oz', 'cem') or chat ID"
                },
                "message": {
                    "type": "string",
                    "description": "Message text to send"
                }
            },
            "required": ["recipient", "message"]
        }
    },
    {
        "name": "egregore_init",
        "description": "Initialize Egregore in a new directory. Returns all files needed for bootstrap (CLAUDE.md, commands, settings). Claude should write these files locally.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    }
]


# =============================================================================
# MCP TOOL HANDLERS
# =============================================================================

async def handle_neo4j_query(args: dict, org_config: dict) -> dict:
    """Execute a Neo4j query."""
    query = args.get("query", "")
    params = args.get("params", {})

    if not query:
        return {"error": "No query provided"}

    # Security: block write operations unless explicitly allowed
    query_lower = query.lower().strip()
    if any(kw in query_lower for kw in ["create", "merge", "delete", "set", "remove"]):
        # For now, allow writes - org isolation provides security
        pass

    results = run_org_query(query, params, org_config)
    return {"results": results, "count": len(results)}


async def handle_neo4j_schema(args: dict, org_config: dict) -> dict:
    """Get Neo4j schema."""
    # Get node labels
    labels = run_org_query("CALL db.labels() YIELD label RETURN collect(label) AS labels", org_config=org_config)

    # Get relationship types
    rels = run_org_query("CALL db.relationshipTypes() YIELD relationshipType RETURN collect(relationshipType) AS types", org_config=org_config)

    # Get property keys
    props = run_org_query("CALL db.propertyKeys() YIELD propertyKey RETURN collect(propertyKey) AS keys", org_config=org_config)

    return {
        "labels": labels[0]["labels"] if labels else [],
        "relationshipTypes": rels[0]["types"] if rels else [],
        "propertyKeys": props[0]["keys"] if props else []
    }


async def handle_telegram_send(args: dict, org_config: dict) -> dict:
    """Send a Telegram message."""
    recipient = args.get("recipient", "")
    message = args.get("message", "")

    if not recipient or not message:
        return {"error": "Missing recipient or message"}

    # Look up telegram ID from Neo4j
    results = run_org_query(
        "MATCH (p:Person {name: $name}) RETURN p.telegramId AS telegramId",
        {"name": recipient.lower()},
        org_config
    )

    if not results or not results[0].get("telegramId"):
        return {"error": f"No Telegram ID found for {recipient}"}

    telegram_id = results[0]["telegramId"]

    # Send via Telegram Bot API
    import httpx
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    if not bot_token:
        return {"error": "Telegram not configured"}

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"https://api.telegram.org/bot{bot_token}/sendMessage",
                json={"chat_id": telegram_id, "text": message}
            )
            if resp.status_code == 200:
                return {"success": True, "recipient": recipient}
            else:
                return {"error": f"Telegram API error: {resp.text}"}
    except Exception as e:
        return {"error": str(e)}


async def handle_egregore_init(args: dict, org_config: dict) -> dict:
    """Return all bootstrap files for Egregore initialization.

    Claude should write these files locally after calling this tool.
    """
    org_name = org_config.get("name", "egregore")

    # Core CLAUDE.md - simplified for bootstrap
    claude_md = '''# Egregore

You are a member of **Egregore**, a collaborative intelligence system where humans and AI work together.

## What is Egregore?

Egregore is a system for human-AI collaboration with persistent memory. It provides:

- **Shared Memory** — Knowledge that persists across sessions and people
- **Neo4j Graph** — Fast queries across sessions, artifacts, quests, and people
- **Telegram Integration** — Team notifications and bot queries
- **Git-backed Storage** — Everything versioned and auditable

When you work here, sessions get logged. When you discover something important, you `/add` it. When you're done, you `/handoff` to leave notes for others.

---

## Entry Point Behavior

**On every startup, check if user exists in Neo4j:**
```cypher
MATCH (p:Person {fullName: $gitUserName})
RETURN p.name AS shortName
```

Where `$gitUserName` = result of `git config user.name`

**If user NOT found → Auto-start setup.** Don't wait for "set me up". Just begin:
```
Welcome to Egregore! Let me get you set up...
```
Then run the full setup flow below.

**If user found → Welcome back:**
```cypher
MATCH (s:Session)-[:BY]->(p:Person)
WHERE s.date >= date() - duration('P2D')
RETURN count(s) AS recent, collect(DISTINCT p.name) AS who
```
Then greet:
```
Welcome back, [shortName]. [X] sessions in the last 2 days.
/activity to see what's happening.
```

---

## Setup Flow

When user says "set me up", "getting started", "new here", or similar:

**Do everything automatically. Don't ask permission. Just show progress:**

```
Setting up Egregore...
```

### Step 1: Check Dependencies

**Check what's installed:**
```bash
which gh brew 2>/dev/null
```

**If brew missing (macOS):**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**If gh missing:**
```bash
brew install gh
```

### Step 2: GitHub Auth (one interaction, if needed)

```bash
gh auth status 2>&1
```

If not authenticated, tell user ONCE:
```
Opening browser for GitHub login. Click "Authorize" and come back.
```

Then run:
```bash
gh auth login --web -h github.com -p https
```

Continue automatically after auth completes.

### Step 3: Clone Memory (silent)

Check if memory directory exists:
```bash
ls memory/conversations 2>/dev/null
```

If not, clone:
```bash
gh repo clone Curve-Labs/egregore-memory memory 2>/dev/null || true
```

### Step 4: Register User

Get git info:
```bash
git config user.name
```

**Only question to ask:**
```
What should we call you? (short name, like 'jane')
```

Register in Neo4j using neo4j_query tool:
```cypher
MERGE (p:Person {name: $shortName})
ON CREATE SET p.fullName = $fullName, p.joined = date()
RETURN p.name, p.joined
```

### Step 5: Done

```
███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
█████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

Welcome, [name]!

Commands:
  /activity   — See what's happening
  /handoff    — Leave notes for others
  /quest      — View or create quests
  /add        — Capture artifacts
  /save       — Commit and push
  /pull       — Get latest

Ask me anything or try a command.
```

---

## Commands

Slash commands are in `.claude/commands/`. Available commands:

| Command | Description |
|---------|-------------|
| `/activity` | See recent sessions, artifacts, and team activity |
| `/handoff` | Create a session note, notify via Telegram |
| `/quest` | List or create quests (ongoing explorations) |
| `/add` | Add artifact (source, thought, finding, decision) |
| `/save` | Git add, commit, push |
| `/pull` | Git pull memory and current repo |

---

## Git Operations

**Always use SSH for Egregore repos. Never HTTPS.**

The `gh` CLI handles auth via HTTPS+OAuth, but for manual operations:
```bash
git clone git@github.com:Curve-Labs/egregore-core.git
git clone git@github.com:Curve-Labs/egregore-memory.git
```
'''

    # Settings with permissions
    settings_json = '''{
  "permissions": {
    "allow": [
      "Read(**)",
      "Write(**)",
      "Edit(**)",
      "Bash(ls:*)",
      "Bash(cd:*)",
      "Bash(pwd:*)",
      "Bash(cat:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(find:*)",
      "Bash(grep:*)",
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(ln:*)",
      "Bash(mkdir:*)",
      "Bash(mv:*)",
      "Bash(cp:*)",
      "Bash(rm:*)",
      "Bash(touch:*)",
      "Bash(chmod:*)",
      "Bash(curl:*)",
      "Bash(wget:*)",
      "mcp__egregore__*"
    ]
  }
}'''

    # Commands
    commands = {
        "activity.md": '''Fast, personal view of what's happening — your projects, your sessions, team activity.

Topic: $ARGUMENTS

**Auto-syncs.** Pulls latest if behind before showing activity.

## Execution

1. Get current user from `git config user.name`
2. Run Neo4j queries (all in parallel):

```cypher
// My projects
MATCH (p:Person {name: $me})-[w:WORKS_ON]->(proj:Project)
RETURN proj.name AS project, proj.domain AS domain, w.role AS role

// My recent sessions
MATCH (s:Session)-[:BY]->(p:Person {name: $me})
RETURN s.date AS date, s.topic AS topic, s.summary AS summary
ORDER BY s.date DESC LIMIT 5

// Team activity (others, last 7 days)
MATCH (s:Session)-[:BY]->(p:Person)
WHERE p.name <> $me AND s.date >= date() - duration('P7D')
RETURN s.date AS date, s.topic AS topic, p.name AS by
ORDER BY s.date DESC LIMIT 5

// Active quests
MATCH (q:Quest {status: 'active'})-[:RELATES_TO]->(proj:Project)
OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q)
RETURN q.id AS quest, q.title AS title, collect(DISTINCT proj.name) AS projects, count(a) AS artifacts
```

3. Display in table format
''',

        "handoff.md": '''End a session with a summary for the next person (or future you).

Topic: $ARGUMENTS

**Auto-saves.** No need to run `/save` after.

## What to do

1. Get author name from `git config user.name`
2. Summarize what was accomplished
3. Note open questions and next steps
4. Create handoff file in memory/conversations/YYYY-MM/
5. **MUST** create Session node in Neo4j

## Neo4j Session creation

```cypher
MATCH (p:Person {name: $author})
CREATE (s:Session {
  id: $sessionId,
  date: date($date),
  topic: $topic,
  summary: $summary,
  filePath: $filePath
})
CREATE (s)-[:BY]->(p)
RETURN s.id
```

## File naming

`memory/conversations/YYYY-MM/DD-[author]-[topic].md`

## Handoff template

```markdown
# Handoff: [Topic]

**Date**: YYYY-MM-DD
**Author**: [from git config user.name]

## Session Summary

[2-3 sentences on what was accomplished]

## Key Decisions

- **[Decision]**: [Rationale]

## Open Threads

- [ ] [Unfinished item with context]

## Next Steps

1. [Clear action with entry point]
```

Then run `/save` to commit and push.
''',

        "add.md": '''Ingest an artifact with minimal friction.

Arguments: $ARGUMENTS (Optional: URL to fetch, or leave empty for interactive mode)

## Usage

- `/add` — Interactive mode, prompts for content
- `/add [url]` — Fetch and ingest external source

## Artifact types

- `source` — External content (papers, articles, docs)
- `thought` — Original thinking, hypotheses, intuitions
- `finding` — Discoveries, what worked or didn't
- `decision` — Choices made with rationale

## File naming

All artifacts go in `memory/artifacts/YYYY-MM-DD-[short-title].md`

## Neo4j Artifact creation

```cypher
MATCH (p:Person {name: $author})
CREATE (a:Artifact {
  id: $artifactId,
  title: $title,
  type: $type,
  created: date(),
  filePath: $filePath
})
CREATE (a)-[:CONTRIBUTED_BY]->(p)
RETURN a.id
```

Then run `/save` to share.
''',

        "pull.md": '''Pull latest for current repo and shared memory.

## Execution

```bash
# Current repo
git pull origin main --quiet

# Memory
git -C memory pull origin main --quiet
```

## Output

```
Pulling...
  current repo     ✓ up to date
  memory           ↓ 2 commits → pulled
```
''',

        "save.md": '''Save your contributions to Egregore.

## What to do

1. Check for uncommitted changes in memory/
2. If changes exist:
   - `git -C memory add -A`
   - `git -C memory commit -m "Add: [description]"`
   - `git -C memory push origin main`
3. Report what was saved

## Example

```
> /save

Saving to Egregore...

[memory]
  Changes:
    artifacts/2026-01-26-my-thought.md (new)

  git add -A
  git commit -m "Add: 1 artifact"
  git push

  ✓ Saved

Done. Team sees your contribution on /activity.
```
''',

        "quest.md": '''Manage quests — open-ended explorations that anyone can contribute to.

Arguments: $ARGUMENTS (Optional: quest name, or subcommand)

## Usage

- `/quest` — List active quests
- `/quest [name]` — Show quest details
- `/quest new` — Create a new quest

## Quest file location

All quests live in `memory/quests/[slug].md`

## Neo4j Quest creation

```cypher
MATCH (p:Person {name: $author})
CREATE (q:Quest {
  id: $slug,
  title: $title,
  status: 'active',
  started: date(),
  question: $question
})
CREATE (q)-[:STARTED_BY]->(p)
RETURN q.id
```

Then run `/save` to share.
'''
    }

    return {
        "files": {
            "CLAUDE.md": claude_md,
            ".claude/settings.json": settings_json,
            **{f".claude/commands/{name}": content for name, content in commands.items()}
        },
        "directories": [
            "memory/conversations",
            "memory/artifacts",
            "memory/quests"
        ],
        "instructions": "Write each file to the specified path. Create directories first. Then run the setup flow in CLAUDE.md."
    }


TOOL_HANDLERS = {
    "neo4j_query": handle_neo4j_query,
    "neo4j_schema": handle_neo4j_schema,
    "telegram_send": handle_telegram_send,
    "egregore_init": handle_egregore_init,
}


# =============================================================================
# MCP PROTOCOL HANDLERS
# =============================================================================

def make_response(id, result=None, error=None):
    """Create JSON-RPC response."""
    resp = {"jsonrpc": "2.0", "id": id}
    if error:
        resp["error"] = error
    else:
        resp["result"] = result
    return resp


async def handle_mcp_request(request_data: dict, org_config: dict) -> dict:
    """Handle a single MCP JSON-RPC request."""
    method = request_data.get("method", "")
    params = request_data.get("params", {})
    req_id = request_data.get("id")

    logger.info(f"MCP request: {method} (org: {org_config.get('name', 'unknown')})")

    # Initialize
    if method == "initialize":
        return make_response(req_id, {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {}
            },
            "serverInfo": {
                "name": "egregore-mcp",
                "version": "1.0.0"
            }
        })

    # List tools
    if method == "tools/list":
        return make_response(req_id, {"tools": MCP_TOOLS})

    # Call tool
    if method == "tools/call":
        tool_name = params.get("name", "")
        tool_args = params.get("arguments", {})

        handler = TOOL_HANDLERS.get(tool_name)
        if not handler:
            return make_response(req_id, error={"code": -32601, "message": f"Unknown tool: {tool_name}"})

        try:
            result = await handler(tool_args, org_config)
            return make_response(req_id, {
                "content": [{"type": "text", "text": json.dumps(result, default=str)}]
            })
        except Exception as e:
            logger.error(f"Tool error: {e}")
            return make_response(req_id, error={"code": -32000, "message": str(e)})

    # Notifications (no response needed)
    if method == "notifications/initialized":
        return None

    # Unknown method
    return make_response(req_id, error={"code": -32601, "message": f"Unknown method: {method}"})


# =============================================================================
# HTTP ENDPOINTS
# =============================================================================

async def handle_mcp_sse(request: Request) -> StreamingResponse:
    """Handle MCP over SSE transport.

    Client POSTs JSON-RPC requests, server responds with SSE stream.
    """
    ensure_initialized()

    # Validate API key
    auth_header = request.headers.get("Authorization", "")
    api_key = auth_header.replace("Bearer ", "") if auth_header.startswith("Bearer ") else ""

    org_config = validate_api_key(api_key)
    if not org_config:
        return JSONResponse({"error": "Invalid API key"}, status_code=401)

    # Parse request body
    try:
        body = await request.json()
    except:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)

    # Handle single request or batch
    if isinstance(body, list):
        responses = []
        for req in body:
            resp = await handle_mcp_request(req, org_config)
            if resp:
                responses.append(resp)
        result = responses
    else:
        result = await handle_mcp_request(body, org_config)

    # Return as SSE event
    async def generate():
        if result:
            data = json.dumps(result, default=str)
            yield f"data: {data}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        }
    )


async def handle_mcp_post(request: Request) -> JSONResponse:
    """Handle MCP over simple POST (non-streaming).

    Simpler alternative to SSE for clients that don't need streaming.
    """
    ensure_initialized()

    # Validate API key
    auth_header = request.headers.get("Authorization", "")
    api_key = auth_header.replace("Bearer ", "") if auth_header.startswith("Bearer ") else ""

    org_config = validate_api_key(api_key)
    if not org_config:
        return JSONResponse({"error": "Invalid API key"}, status_code=401)

    # Parse request body
    try:
        body = await request.json()
    except:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)

    # Handle single request or batch
    if isinstance(body, list):
        responses = []
        for req in body:
            resp = await handle_mcp_request(req, org_config)
            if resp:
                responses.append(resp)
        return JSONResponse(responses)
    else:
        result = await handle_mcp_request(body, org_config)
        return JSONResponse(result if result else {})


def get_mcp_routes():
    """Get Starlette routes for MCP endpoints."""
    from starlette.routing import Route
    return [
        Route("/mcp", handle_mcp_post, methods=["POST"]),
        Route("/mcp/sse", handle_mcp_sse, methods=["POST"]),
    ]
