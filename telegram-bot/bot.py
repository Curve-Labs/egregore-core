"""
Egregore Bot

A Telegram bot that answers natural language queries about Egregore
by querying the Neo4j knowledge graph directly.

Uses LLM (Haiku) to:
1. Parse questions and pick the right query
2. Format results as natural language

Deploy to Railway with webhook mode for production.
"""

import os
import json
import logging
import time
from datetime import date
from typing import Optional

from analytics import log_query_event, log_event
import secrets
import hashlib
import uuid

from dotenv import load_dotenv
load_dotenv(override=False)

import httpx
from neo4j import GraphDatabase

from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, ChatMemberHandler, filters, ContextTypes
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse
from starlette.routing import Route
import uvicorn

# MCP server - import safely
try:
    from mcp_server import get_mcp_routes
    MCP_ENABLED = True
except Exception as e:
    import logging
    logging.error(f"MCP server import failed: {e}")
    MCP_ENABLED = False
    def get_mcp_routes():
        return []

# =============================================================================
# CONFIG
# =============================================================================

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Telegram
BOT_TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
WEBHOOK_URL = os.environ.get("WEBHOOK_URL", "")
PORT = int(os.environ.get("PORT", 8443))

# Neo4j Aura (default/legacy - used if no org match)
NEO4J_URI = os.environ.get("NEO4J_URI", "")
NEO4J_USER = os.environ.get("NEO4J_USER", "")
NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD", "")

# GitHub token for adding collaborators
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")

# Anthropic (for Haiku)
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

# Spirit adapter admin secret (required for /spirit/init)
SPIRIT_ADMIN_SECRET = os.environ.get("SPIRIT_ADMIN_SECRET", "")

# Security: Only respond to allowed chats/users
# Channel: -1003081443167, Oz: 154132702, Ali: 952778083, Cem: 72463248, Pali: 515146069, Damla: 5549297057
DEFAULT_ALLOWED = [-1003081443167, 154132702, 952778083, 72463248, 515146069, 5549297057]
ALLOWED_CHAT_IDS = [
    int(x) for x in os.environ.get("ALLOWED_CHAT_IDS", "").split(",") if x.strip()
] or DEFAULT_ALLOWED

# =============================================================================
# MULTI-ORG CONFIG
# =============================================================================

TESTORG_CHANNEL_ID = int(os.environ.get("TESTORG_CHANNEL_ID", "0") or "0")
EGREGORE_CHANNEL_ID = int(os.environ.get("EGREGORE_CHANNEL_ID", "0") or "0")

ORG_CONFIG = {
    -1003081443167: {
        "name": "curvelabs",
        "neo4j_uri": os.environ.get("NEO4J_URI", ""),
        "neo4j_user": os.environ.get("NEO4J_USER", "neo4j"),
        "neo4j_password": os.environ.get("NEO4J_PASSWORD", ""),
        "mcp_api_key": os.environ.get("CURVELABS_MCP_KEY", "ek_curvelabs_default"),
    },
}

# Egregore org (new standalone org)
if EGREGORE_CHANNEL_ID:
    ORG_CONFIG[EGREGORE_CHANNEL_ID] = {
        "name": "egregore",
        "neo4j_uri": os.environ.get("EGREGORE_NEO4J_URI", ""),
        "neo4j_user": os.environ.get("EGREGORE_NEO4J_USER", "neo4j"),
        "neo4j_password": os.environ.get("EGREGORE_NEO4J_PASSWORD", ""),
        "mcp_api_key": os.environ.get("EGREGORE_MCP_KEY", "ek_egregore_default"),
    }

# Test org (legacy)
if TESTORG_CHANNEL_ID:
    ORG_CONFIG[TESTORG_CHANNEL_ID] = {
        "name": "testorg",
        "neo4j_uri": os.environ.get("TESTORG_NEO4J_URI", ""),
        "neo4j_user": os.environ.get("TESTORG_NEO4J_USER", "neo4j"),
        "neo4j_password": os.environ.get("TESTORG_NEO4J_PASSWORD", ""),
        "mcp_api_key": os.environ.get("TESTORG_MCP_KEY", "ek_testorg_default"),
    }

ONBOARDING_REPOS = ["Curve-Labs/egregore-core", "Curve-Labs/egregore-memory"]
onboarding_state = {}

def get_org_for_chat(chat_id: int, user_id: int = None) -> dict:
    """Get org config for a chat."""
    if chat_id in ORG_CONFIG:
        return ORG_CONFIG[chat_id]
    return {
        "name": "default",
        "neo4j_uri": NEO4J_URI,
        "neo4j_user": NEO4J_USER,
        "neo4j_password": NEO4J_PASSWORD,
    }

# Log startup config
logger.info("=== Egregore Bot Starting ===")
logger.info(f"NEO4J_URI: {'SET' if NEO4J_URI else 'NOT SET'}")
logger.info(f"ANTHROPIC_API_KEY: {'SET' if ANTHROPIC_API_KEY else 'NOT SET'}")
logger.info(f"ALLOWED_CHAT_IDS: {ALLOWED_CHAT_IDS}")

# =============================================================================
# NEO4J CONNECTION
# =============================================================================

neo4j_driver = None
org_drivers = {}  # Cache of org-specific drivers

def get_neo4j_driver():
    """Get or create default Neo4j driver."""
    global neo4j_driver
    if neo4j_driver is None and NEO4J_URI:
        neo4j_driver = GraphDatabase.driver(
            NEO4J_URI,
            auth=(NEO4J_USER, NEO4J_PASSWORD)
        )
        logger.info("Neo4j driver initialized (default)")
    return neo4j_driver


def get_org_driver(org_config: dict):
    """Get or create org-specific Neo4j driver."""
    if not org_config:
        return get_neo4j_driver()

    org_name = org_config.get("name", "default")
    uri = org_config.get("neo4j_uri")
    user = org_config.get("neo4j_user", "neo4j")
    password = org_config.get("neo4j_password")

    if not uri or not password:
        logger.warning(f"Neo4j not configured for org {org_name}")
        return None

    if org_name not in org_drivers:
        org_drivers[org_name] = GraphDatabase.driver(uri, auth=(user, password))
        logger.info(f"Neo4j driver initialized for org: {org_name}")

    return org_drivers[org_name]


def run_query(query: str, params: dict = None) -> list:
    """Run a Cypher query on default Neo4j."""
    driver = get_neo4j_driver()
    if not driver:
        logger.warning("Neo4j not configured")
        return []

    try:
        with driver.session() as session:
            result = session.run(query, params or {})
            return [dict(record) for record in result]
    except Exception as e:
        logger.error(f"Neo4j query failed: {e}")
        return []


def run_org_query(query: str, params: dict = None, org_config: dict = None) -> list:
    """Run a Cypher query on org-specific Neo4j."""
    driver = get_org_driver(org_config)
    if not driver:
        logger.warning("Neo4j not configured for org")
        return []

    try:
        with driver.session() as session:
            result = session.run(query, params or {})
            return [dict(record) for record in result]
    except Exception as e:
        logger.error(f"Neo4j org query failed: {e}")
        return []


def lookup_person_by_telegram_id(telegram_id: int) -> Optional[str]:
    """Look up Person name by Telegram ID."""
    results = run_query(
        "MATCH (p:Person {telegramId: $tid}) RETURN p.name AS name",
        {"tid": telegram_id}
    )
    if results and results[0].get("name"):
        return results[0]["name"]
    return None


# Known Telegram IDs -> Person names (for auto-registration)
KNOWN_TELEGRAM_IDS = {
    154132702: "oz",
    952778083: "ali",
    72463248: "cem",
    515146069: "pali",
    5549297057: "damla",
}


def auto_register_telegram_id(telegram_id: int, first_name: str = None) -> Optional[str]:
    """Auto-register a Telegram ID to a Person node if we can match them.

    Returns the person's name if registered, None otherwise.
    """
    # First check if already registered
    existing = lookup_person_by_telegram_id(telegram_id)
    if existing:
        return existing

    # Check known IDs mapping
    if telegram_id in KNOWN_TELEGRAM_IDS:
        name = KNOWN_TELEGRAM_IDS[telegram_id]
        results = run_query(
            """MATCH (p:Person {name: $name})
               SET p.telegramId = $tid
               RETURN p.name AS name""",
            {"name": name, "tid": telegram_id}
        )
        if results:
            logger.info(f"Auto-registered {name} with Telegram ID {telegram_id}")
            return results[0].get("name")

    # Try matching by first name (lowercase)
    if first_name:
        name_lower = first_name.lower().strip()
        # Check if there's a Person with this name
        results = run_query(
            """MATCH (p:Person)
               WHERE p.name = $name OR toLower(p.fullName) STARTS WITH $name
               AND p.telegramId IS NULL
               SET p.telegramId = $tid
               RETURN p.name AS name""",
            {"name": name_lower, "tid": telegram_id}
        )
        if results:
            logger.info(f"Auto-registered {results[0].get('name')} with Telegram ID {telegram_id} (matched by first name)")
            return results[0].get("name")

    return None


# =============================================================================
# PREDEFINED QUERIES
# =============================================================================

QUERIES = {
    "recent_activity": {
        "description": "Recent sessions/activity from the team (last 7 days)",
        "params": [],
        "cypher": """
            MATCH (s:Session)-[:BY]->(p:Person)
            WHERE s.date >= date() - duration('P7D')
            RETURN s.date AS date, s.topic AS topic, p.name AS person, s.summary AS summary
            ORDER BY s.date DESC LIMIT 10
        """
    },
    "person_projects": {
        "description": "What projects a specific person works on",
        "params": ["name"],
        "cypher": """
            MATCH (p:Person {name: $name})-[w:WORKS_ON]->(proj:Project)
            RETURN proj.name AS project, proj.domain AS domain, w.role AS role
        """
    },
    "person_sessions": {
        "description": "Recent sessions by a specific person",
        "params": ["name"],
        "cypher": """
            MATCH (s:Session)-[:BY]->(p:Person {name: $name})
            RETURN s.date AS date, s.topic AS topic, s.summary AS summary
            ORDER BY s.date DESC LIMIT 5
        """
    },
    "quest_details": {
        "description": "Details about a specific quest",
        "params": ["quest_id"],
        "cypher": """
            MATCH (q:Quest {id: $quest_id})
            OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q)
            OPTIONAL MATCH (q)-[:STARTED_BY]->(p:Person)
            OPTIONAL MATCH (q)-[:RELATES_TO]->(proj:Project)
            RETURN q.title AS title, q.status AS status, q.question AS question,
                   p.name AS started_by,
                   collect(DISTINCT a.title) AS artifacts,
                   collect(DISTINCT proj.name) AS projects
        """
    },
    "active_quests": {
        "description": "All currently active quests",
        "params": [],
        "cypher": """
            MATCH (q:Quest {status: 'active'})
            OPTIONAL MATCH (q)-[:RELATES_TO]->(proj:Project)
            OPTIONAL MATCH (q)-[:STARTED_BY]->(p:Person)
            RETURN q.id AS id, q.title AS title,
                   collect(DISTINCT proj.name) AS projects,
                   p.name AS started_by
        """
    },
    "search_artifacts": {
        "description": "Search artifacts by keyword in title",
        "params": ["term"],
        "cypher": """
            MATCH (a:Artifact)
            WHERE toLower(a.title) CONTAINS toLower($term)
            OPTIONAL MATCH (a)-[:PART_OF]->(q:Quest)
            OPTIONAL MATCH (a)-[:CONTRIBUTED_BY]->(p:Person)
            RETURN a.title AS title, a.type AS type, a.created AS created,
                   p.name AS author, collect(DISTINCT q.id) AS quests
            LIMIT 10
        """
    },
    "all_people": {
        "description": "List all team members and their projects",
        "params": [],
        "cypher": """
            MATCH (p:Person)
            OPTIONAL MATCH (p)-[:WORKS_ON]->(proj:Project)
            RETURN p.name AS name, p.fullName AS fullName,
                   collect(DISTINCT proj.name) AS projects
        """
    },
    "project_details": {
        "description": "Details about a specific project",
        "params": ["name"],
        "cypher": """
            MATCH (proj:Project {name: $name})
            OPTIONAL MATCH (q:Quest {status: 'active'})-[:RELATES_TO]->(proj)
            OPTIONAL MATCH (p:Person)-[:WORKS_ON]->(proj)
            RETURN proj.name AS name, proj.domain AS domain,
                   proj.description AS description,
                   collect(DISTINCT q.id) AS quests,
                   collect(DISTINCT p.name) AS team
        """
    },
    "all_projects": {
        "description": "List all projects",
        "params": [],
        "cypher": """
            MATCH (proj:Project)
            OPTIONAL MATCH (p:Person)-[:WORKS_ON]->(proj)
            RETURN proj.name AS name, proj.domain AS domain,
                   collect(DISTINCT p.name) AS team
        """
    },
    "person_quests": {
        "description": "Quests started by a specific person",
        "params": ["name"],
        "cypher": """
            MATCH (q:Quest)-[:STARTED_BY]->(p:Person {name: $name})
            OPTIONAL MATCH (q)-[:RELATES_TO]->(proj:Project)
            WITH q, collect(DISTINCT proj.name) AS projects
            ORDER BY q.created DESC
            RETURN q.id AS id, q.title AS title, q.status AS status,
                   q.question AS question, projects
        """
    },
    "person_artifacts": {
        "description": "Artifacts contributed by a specific person",
        "params": ["name"],
        "cypher": """
            MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p:Person {name: $name})
            OPTIONAL MATCH (a)-[:PART_OF]->(q:Quest)
            WITH a, collect(DISTINCT q.id) AS quests
            ORDER BY a.created DESC
            RETURN a.title AS title, a.type AS type, a.created AS created, quests
            LIMIT 10
        """
    },
    "recent_artifacts": {
        "description": "Recently added artifacts",
        "params": [],
        "cypher": """
            MATCH (a:Artifact)
            OPTIONAL MATCH (a)-[:CONTRIBUTED_BY]->(p:Person)
            OPTIONAL MATCH (a)-[:PART_OF]->(q:Quest)
            WITH a, p, collect(DISTINCT q.id) AS quests
            ORDER BY a.created DESC LIMIT 10
            RETURN a.title AS title, a.type AS type, a.created AS created,
                   p.name AS author, quests
        """
    },
    "recent_quests": {
        "description": "Recently created quests",
        "params": [],
        "cypher": """
            MATCH (q:Quest)
            OPTIONAL MATCH (q)-[:STARTED_BY]->(p:Person)
            OPTIONAL MATCH (q)-[:RELATES_TO]->(proj:Project)
            WITH q, p, collect(DISTINCT proj.name) AS projects
            ORDER BY q.created DESC LIMIT 10
            RETURN q.id AS id, q.title AS title, q.status AS status,
                   p.name AS started_by, projects
        """
    },
    "activity_on_date": {
        "description": "All activity (sessions, artifacts) on a specific date. Use for 'what happened today/yesterday'",
        "params": ["date"],
        "cypher": """
            MATCH (s:Session)-[:BY]->(p:Person)
            WHERE s.date = date($date)
            RETURN 'session' AS type, s.topic AS title, p.name AS person, s.summary AS summary, s.date AS date
            UNION
            MATCH (a:Artifact)-[:AUTHORED_BY]->(p:Person)
            WHERE a.date = date($date)
            RETURN 'artifact' AS type, a.title AS title, p.name AS person, a.summary AS summary, a.date AS date
        """
    },
    "person_sessions_on_date": {
        "description": "Sessions by a specific person on a specific date. Use for 'what did X do today'",
        "params": ["name", "date"],
        "cypher": """
            MATCH (s:Session)-[:BY]->(p:Person {name: $name})
            WHERE s.date = date($date)
            RETURN s.date AS date, s.topic AS topic, s.summary AS summary
            ORDER BY s.date DESC
        """
    },
    "handoffs_to_person": {
        "description": "Handoffs addressed to a specific person. Use for 'what was handed off to X'",
        "params": ["recipient"],
        "cypher": """
            MATCH (a:Artifact {type: 'handoff'})-[:FOR]->(recipient:Person {name: $recipient})
            OPTIONAL MATCH (a)-[:AUTHORED_BY]->(author:Person)
            RETURN a.title AS title, a.summary AS summary, a.date AS date,
                   author.name AS from_person
            ORDER BY a.date DESC
        """
    },
    "handoffs_from_person": {
        "description": "Handoffs written by a specific person. Use for 'what did X hand off'",
        "params": ["author"],
        "cypher": """
            MATCH (a:Artifact {type: 'handoff'})-[:AUTHORED_BY]->(author:Person {name: $author})
            OPTIONAL MATCH (a)-[:FOR]->(recipient:Person)
            RETURN a.title AS title, a.summary AS summary, a.date AS date,
                   recipient.name AS to_person
            ORDER BY a.date DESC
        """
    }
}


# =============================================================================
# LLM AGENT WITH TOOL USE
# =============================================================================

def build_tools_schema() -> list:
    """Build Anthropic tools schema from QUERIES."""
    tools = []
    for name, q in QUERIES.items():
        tool = {
            "name": f"query_{name}",
            "description": q["description"],
            "input_schema": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
        for param in q.get("params", []):
            tool["input_schema"]["properties"][param] = {
                "type": "string",
                "description": f"The {param} (use lowercase for person names: oz, ali, cem)"
            }
            tool["input_schema"]["required"].append(param)
        tools.append(tool)
    
    # Direct response tool
    tools.append({
        "name": "respond_directly",
        "description": "Respond directly without querying. Use for greetings, explaining how Egregore works, or when no data query is needed.",
        "input_schema": {
            "type": "object",
            "properties": {
                "message": {"type": "string", "description": "The response message"}
            },
            "required": ["message"]
        }
    })
    
    return tools


async def agent_decide(question: str, conversation_context: str = "", sender_name: str = None) -> dict:
    """LLM agent with tool use decides what to do.

    Returns dict with:
        action: "respond" or "query"
        message: (if respond) the response text
        query: (if query) the query name
        params: (if query) the query parameters
        usage: {"input_tokens": int, "output_tokens": int}
        latency_ms: float
    """
    if not ANTHROPIC_API_KEY:
        return {"action": "respond", "message": "API not configured.", "usage": {}, "latency_ms": 0}

    tools = build_tools_schema()

    context_info = ""
    if conversation_context:
        context_info = f"\n\nPrevious context:\n{conversation_context}\n\nUse this to understand follow-ups like 'which ones', 'tell me more', etc."

    # Identity context for "my" / "I" questions
    sender_info = ""
    if sender_name:
        sender_info = f"""
SENDER IDENTITY: The person asking this question is "{sender_name}".
When they say "my", "I", "me", or ask about themselves, use name="{sender_name}" in queries.
Examples for {sender_name}:
- "What am I working on?" -> query_person_sessions(name="{sender_name}")
- "My activity" -> query_person_sessions(name="{sender_name}")
- "What have I done?" -> query_person_sessions(name="{sender_name}")
- "My quests" -> query_person_quests(name="{sender_name}")
- "What did I write?" -> query_person_artifacts(name="{sender_name}")
"""

    today_str = date.today().isoformat()

    system_prompt = f"""You are Egregore, the shared memory for Curve Labs - an INTERNAL tool for team members.

TODAY'S DATE: {today_str}
When user says "today", use date parameter = "{today_str}"
When user says "yesterday", use date parameter for the day before.

IMPORTANT: Everyone works on the same projects (lace, tristero, infrastructure).
Don't answer "working on" questions with just project names - that's not useful.
Instead, show ACTIVITY: sessions, quests, artifacts.
{sender_info}
QUERY PRIORITY for "what is X working on?" or "what's X doing?":
1. query_person_sessions - shows their recent actual work/activity
2. query_person_quests - shows initiatives they're driving
3. query_person_artifacts - shows what they've created

DO NOT use query_person_projects for "working on" questions - it just shows repo assignments.

DATE-SPECIFIC QUERIES:
- "What happened today?" -> query_activity_on_date(date="{today_str}")
- "What did X do today?" -> query_person_sessions_on_date(name="x", date="{today_str}")
- "What did X handoff to Y?" -> query_handoffs_to_person(recipient="y") then filter by sender

TEAM (lowercase for queries): oz, ali, cem, pali, damla
{context_info}

Examples:
- "What is Cem working on?" -> query_person_sessions(name="cem")
- "What's Oz been up to?" -> query_person_sessions(name="oz")
- "What quests did Cem start?" -> query_person_quests(name="cem")
- "What has Ali written?" -> query_person_artifacts(name="ali")
- "What's happening?" -> query_recent_activity
- "What's happening today?" -> query_activity_on_date(date="{today_str}")
- Single word "cem" -> query_person_sessions(name="cem")
- "Tell me about lace" -> query_project_details(name="lace")
- "What is Egregore?" -> respond_directly (brief explanation)"""

    async with httpx.AsyncClient() as client:
        try:
            start_time = time.perf_counter()
            resp = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "claude-haiku-4-5-20251001",
                    "max_tokens": 400,
                    "system": system_prompt,
                    "tools": tools,
                    "messages": [{"role": "user", "content": question}]
                },
                timeout=15
            )
            latency_ms = (time.perf_counter() - start_time) * 1000
            resp.raise_for_status()
            data = resp.json()

            # Extract token usage
            usage = data.get("usage", {})
            usage_info = {
                "input_tokens": usage.get("input_tokens", 0),
                "output_tokens": usage.get("output_tokens", 0)
            }

            # Check for tool use
            for block in data.get("content", []):
                if block.get("type") == "tool_use":
                    tool_name = block.get("name", "")
                    tool_input = block.get("input", {})
                    logger.info(f"Agent chose: {tool_name} with {tool_input}")

                    if tool_name == "respond_directly":
                        return {"action": "respond", "message": tool_input.get("message", ""), "usage": usage_info, "latency_ms": latency_ms}

                    if tool_name.startswith("query_"):
                        query_name = tool_name[6:]
                        return {"action": "query", "query": query_name, "params": tool_input, "usage": usage_info, "latency_ms": latency_ms}

            # Fallback to text response
            for block in data.get("content", []):
                if block.get("type") == "text":
                    return {"action": "respond", "message": block.get("text", ""), "usage": usage_info, "latency_ms": latency_ms}

            return {"action": "respond", "message": "I'm not sure how to help with that.", "usage": usage_info, "latency_ms": latency_ms}

        except Exception as e:
            logger.error(f"Agent failed: {e}")
            return {"action": "respond", "message": "Something went wrong. Try asking differently?", "usage": {}, "latency_ms": 0}


async def format_response(question: str, query_name: str, results: list, params: dict = None) -> tuple:
    """Use LLM to format query results as conversational text.

    Returns tuple of (response_text, usage_dict, latency_ms)
    """
    if not ANTHROPIC_API_KEY:
        return f"Found {len(results)} results.", {}, 0

    if not results:
        return "No results found.", {}, 0

    system_prompt = """You are Egregore, shared memory for Curve Labs. Internal tool - everyone knows each other.

FORMAT RULES:

FOR EXPLICIT LIST QUERIES ("what quests are active", "who's on the team", "list projects"):
- Use clean list format: one item per line
- Include key info per item

FOR EVERYTHING ELSE (activity, "what's X doing", updates):
- Write naturally like you're catching someone up over coffee
- "Cem's been deep in the evaluation stuff - surveyed 80+ datasets and landed on LLMs4OL Task B. Also wrapped up the Egregore Spec and handed it to Oz."
- NOT log format: "Cem - 4 sessions: Item 1, Item 2..."
- Weave the information into sentences, mention what's interesting
- 2-3 short paragraphs max

TONE:
- Conversational, not structured
- Skip intros - everyone knows each other
- Include specifics (dates, names) but naturally
- End with casual follow-up

BAD (log-like): "Cem - 4 sessions this week: Egregore Spec V2 (Jan 28), Evaluation benchmarks (Jan 26)..."
GOOD (natural): "Cem's been heads-down on evaluation benchmarks - surveyed 80+ datasets and locked in LLMs4OL Task B. The big handoff was the Egregore Spec V2 going to Oz, ready for the blog launch."

NO markdown, NO emojis."""

    async with httpx.AsyncClient() as client:
        try:
            start_time = time.perf_counter()
            resp = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "claude-haiku-4-5-20251001",
                    "max_tokens": 600,
                    "system": system_prompt,
                    "messages": [{
                        "role": "user",
                        "content": f"Question: {question}\nQuery type: {query_name}\nData: {json.dumps(results, default=str)}"
                    }]
                },
                timeout=15
            )
            latency_ms = (time.perf_counter() - start_time) * 1000
            resp.raise_for_status()
            data = resp.json()

            usage = data.get("usage", {})
            usage_info = {
                "input_tokens": usage.get("input_tokens", 0),
                "output_tokens": usage.get("output_tokens", 0)
            }

            return data["content"][0]["text"], usage_info, latency_ms
        except Exception as e:
            logger.error(f"LLM response formatter failed: {e}")
            return f"Found {len(results)} results for {query_name}.", {}, 0


async def generate_no_results_response(question: str, query_name: str, params: dict) -> str:
    """Generate a helpful response when no results are found."""
    if not ANTHROPIC_API_KEY:
        return "Nothing in the graph for that yet. Try a different angle?"

    search_context = f"Query: {query_name}, Params: {params}"
    
    system_prompt = """You are Egregore, shared memory for Curve Labs. Talking to INTERNAL team members.
A search returned no results. Keep it brief and casual:

1. Quick acknowledgment (not apologetic)
2. Suggest what they could try instead
3. One line max

TONE: Like a colleague saying "nothing on that yet, try X"
NO markdown, NO emojis, NO formal language."""

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "claude-haiku-4-5-20251001",
                    "max_tokens": 300,
                    "system": system_prompt,
                    "messages": [{
                        "role": "user",
                        "content": f"User asked: {question}\n{search_context}\n\nNo results were found. Provide a helpful response."
                    }]
                },
                timeout=15
            )
            resp.raise_for_status()
            return resp.json()["content"][0]["text"]
        except Exception as e:
            logger.error(f"No results response failed: {e}")
            return "No results found for that search. Try asking about team members (oz, ali, cem), projects (lace, tristero), or recent activity."


# =============================================================================
# EGREGORE CONTEXT (for general questions)
# =============================================================================

EGREGORE_CONTEXT = """Egregore = our shared memory + async coordination system.

The concept: collective intelligence that emerges from shared focus (thoughtform/group mind).
The system: Neo4j graph connecting people, projects, quests, artifacts. This bot queries it.

Quick reference:
- Quests: ongoing explorations (NLNet grant, evaluation benchmark, etc.)
- Artifacts: content we create (blog posts, decisions, findings)
- Sessions: daily work logs

To add stuff: /add in Claude Code, then /save"""


# Team info - kept brief for internal use
TEAM_INFO = {
    "oz": "lace, tristero, infrastructure - architecture side",
    "ali": "infrastructure, deployment, this bot",
    "cem": "research - emergent ontologies, evaluation frameworks",
    "pali": "operations, coordination",
    "damla": "design, product, user experience"
}


async def answer_general(question: str) -> str:
    """Answer general questions about Egregore (not data queries)."""
    if not ANTHROPIC_API_KEY:
        return "I can answer questions about Egregore activity. Try: What's happening?"

    system_prompt = f"""You are Egregore, a living organization where humans and AI collaborate.

{EGREGORE_CONTEXT}

Answer the user's question concisely. If it's about how Egregore works, explain briefly.
If it seems like a data question but you couldn't match it, suggest rephrasing.
Don't use emojis."""

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "claude-haiku-4-5-20251001",
                    "max_tokens": 300,
                    "system": system_prompt,
                    "messages": [{"role": "user", "content": question}]
                },
                timeout=15
            )
            resp.raise_for_status()
            return resp.json()["content"][0]["text"]
        except Exception as e:
            logger.error(f"General answer failed: {e}")
            return "I can help with: activity, quests, projects, artifacts, people. Try asking 'What's happening?'"


# =============================================================================
# CONVERSATION CONTEXT
# =============================================================================

MAX_HISTORY = 5

def get_conversation_context(context) -> str:
    """Get recent conversation history for follow-ups."""
    history = context.chat_data.get("history", [])
    if not history:
        return ""
    
    lines = []
    for entry in history[-3:]:  # Last 3 exchanges
        lines.append(f"Q: {entry['question']}")
        lines.append(f"A: {entry['summary']}")
    return "\n".join(lines)


def store_in_context(context, question: str, query_name: str, result_summary: str):
    """Store exchange in conversation context."""
    if "history" not in context.chat_data:
        context.chat_data["history"] = []
    
    context.chat_data["history"].append({
        "question": question,
        "query": query_name,
        "summary": result_summary
    })
    
    # Trim old entries
    if len(context.chat_data["history"]) > MAX_HISTORY:
        context.chat_data["history"] = context.chat_data["history"][-MAX_HISTORY:]


# =============================================================================
# MAIN HANDLER
# =============================================================================

def is_allowed(update: Update) -> bool:
    """Check if chat/user is allowed."""
    chat_id = update.effective_chat.id
    user_id = update.effective_user.id if update.effective_user else None
    return chat_id in ALLOWED_CHAT_IDS or user_id in ALLOWED_CHAT_IDS


async def handle_question(update: Update, context, question: str) -> None:
    """Main question handler - agent decides what to do."""

    # Get org config for this chat
    chat_id = update.effective_chat.id
    org_config = ORG_CONFIG.get(chat_id)
    if not org_config:
        # Fallback to default org
        org_config = ORG_CONFIG.get(-1003081443167)

    org_name = org_config.get("name", "default") if org_config else "default"
    logger.info(f"handle_question: chat_id={chat_id}, org={org_name}")

    # Check if Neo4j is configured for this org
    if not org_config or not org_config.get("neo4j_uri"):
        if not NEO4J_URI:
            await update.message.reply_text("Knowledge graph not configured.")
            return

    # Track user info for analytics
    user_id = None
    sender_name = None
    if update.effective_user:
        user_id = update.effective_user.id
        first_name = update.effective_user.first_name

        # Try lookup first, then auto-register if not found
        sender_name = lookup_person_by_telegram_id(user_id)
        if not sender_name:
            sender_name = auto_register_telegram_id(user_id, first_name)

        if sender_name:
            logger.info(f"Identified sender: {sender_name} (Telegram ID: {user_id})")

    # Get conversation context for follow-ups
    conv_context = get_conversation_context(context)

    # Agent decides (tool use) - now returns usage and latency
    decision = await agent_decide(question, conv_context, sender_name)

    action = decision.get("action")
    decision_usage = decision.get("usage", {})
    decision_latency = decision.get("latency_ms", 0)

    if action == "respond":
        # Direct response from agent
        response = decision.get("message", "")
        await update.message.reply_text(response)
        store_in_context(context, question, "direct", response[:100])

        # Log analytics for direct response
        log_query_event(
            query_type="direct",
            tokens_in=decision_usage.get("input_tokens", 0),
            tokens_out=decision_usage.get("output_tokens", 0),
            latency_ms=decision_latency,
            results_count=0,
            success=True,
            user_id=user_id,
            user_name=sender_name,
            question=question,
            decision_tokens_in=decision_usage.get("input_tokens", 0),
            decision_tokens_out=decision_usage.get("output_tokens", 0),
            decision_latency_ms=decision_latency,
        )
        return

    if action == "query":
        query_name = decision.get("query")
        params = decision.get("params", {})

        if query_name not in QUERIES:
            await update.message.reply_text("I couldn't find that information.")
            return

        # Run the query with timing (org-specific Neo4j)
        cypher = QUERIES[query_name]["cypher"]
        logger.info(f"Running query: {query_name} with params: {params} (org: {org_name})")

        neo4j_start = time.perf_counter()
        results = run_org_query(cypher, params, org_config)
        neo4j_latency = (time.perf_counter() - neo4j_start) * 1000

        if not results:
            # Give helpful response based on what was searched
            helpful_msg = await generate_no_results_response(question, query_name, params)
            await update.message.reply_text(helpful_msg)

            # Log analytics for empty results
            log_query_event(
                query_type=query_name,
                tokens_in=decision_usage.get("input_tokens", 0),
                tokens_out=decision_usage.get("output_tokens", 0),
                latency_ms=decision_latency + neo4j_latency,
                results_count=0,
                success=True,  # Query worked, just no results
                user_id=user_id,
                user_name=sender_name,
                question=question,
                decision_tokens_in=decision_usage.get("input_tokens", 0),
                decision_tokens_out=decision_usage.get("output_tokens", 0),
                decision_latency_ms=decision_latency,
                neo4j_latency_ms=neo4j_latency,
            )
            return

        # Format and send response (pass params for person context)
        response, format_usage, format_latency = await format_response(question, query_name, results, params)
        await update.message.reply_text(response)

        # Store in context
        summary = f"{query_name}: {len(results)} results"
        store_in_context(context, question, query_name, summary)

        # Calculate totals for analytics
        total_tokens_in = decision_usage.get("input_tokens", 0) + format_usage.get("input_tokens", 0)
        total_tokens_out = decision_usage.get("output_tokens", 0) + format_usage.get("output_tokens", 0)
        total_latency = decision_latency + neo4j_latency + format_latency

        # Log analytics
        log_query_event(
            query_type=query_name,
            tokens_in=total_tokens_in,
            tokens_out=total_tokens_out,
            latency_ms=total_latency,
            results_count=len(results),
            success=True,
            user_id=user_id,
            user_name=sender_name,
            question=question,
            decision_tokens_in=decision_usage.get("input_tokens", 0),
            decision_tokens_out=decision_usage.get("output_tokens", 0),
            decision_latency_ms=decision_latency,
            format_tokens_in=format_usage.get("input_tokens", 0),
            format_tokens_out=format_usage.get("output_tokens", 0),
            format_latency_ms=format_latency,
            neo4j_latency_ms=neo4j_latency,
        )
        return

    # Fallback
    await update.message.reply_text("I'm not sure how to help with that.")


# =============================================================================
# TELEGRAM HANDLERS
# =============================================================================

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /start command."""
    user = update.effective_user

    # In private chat, start onboarding flow directly
    if update.effective_chat.type == "private":
        # Determine org (use test org if available)
        org_config = None
        if TESTORG_CHANNEL_ID and TESTORG_CHANNEL_ID in ORG_CONFIG:
            org_config = ORG_CONFIG[TESTORG_CHANNEL_ID]
        else:
            org_config = ORG_CONFIG.get(-1003081443167)

        if org_config:
            ascii_art = """
███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
█████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
"""
            welcome_msg = f"""{ascii_art}
Welcome to Egregore!

I'll help you get set up. What's your GitHub username?

(Just type your username, like: janesmith)"""

            await update.message.reply_text(welcome_msg)
            onboarding_state[user.id] = {
                "step": "awaiting_github",
                "org_config": org_config,
                "first_name": user.first_name
            }
            return

    if not is_allowed(update):
        await update.message.reply_text("This bot is private to Egregore.")
        return

    await update.message.reply_text(
        "I'm Egregore. Ask me anything about our work:\n\n"
        "- What's happening?\n"
        "- What is Oz working on?\n"
        "- What quests are active?\n"
        "- Tell me about the FAMP proposal\n"
        "- Who's on the team?\n\n"
        "Or ask how to use Egregore (commands, adding artifacts, etc.)"
    )


async def activity_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /activity command."""
    if not is_allowed(update):
        return
    await handle_question(update, context, "What's been happening recently?")


async def debug_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /debug command - show deployment info."""
    if not is_allowed(update):
        return

    from pathlib import Path
    import os

    cwd = os.getcwd()
    file_loc = Path(__file__).parent

    # List files in likely locations
    locations = {
        "cwd": Path(cwd),
        "__file__.parent": file_loc,
        "/app": Path("/app"),
        "/app/telegram-bot": Path("/app/telegram-bot"),
    }

    lines = [f"CWD: {cwd}", f"__file__: {__file__}", ""]

    for name, path in locations.items():
        if path.exists():
            files = list(path.glob("*.zip")) + list(path.glob("*.py"))[:3]
            lines.append(f"{name}: {[f.name for f in files]}")
        else:
            lines.append(f"{name}: (not found)")

    await update.message.reply_text("\n".join(lines))


async def onboard_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /onboard command - manually trigger onboarding flow."""
    if not is_allowed(update):
        return

    user = update.effective_user
    chat_id = update.effective_chat.id

    # Determine which org to use
    org_config = None
    if chat_id in ORG_CONFIG:
        org_config = ORG_CONFIG[chat_id]
    elif update.effective_chat.type == "private":
        # In DM, use test org if available, otherwise curvelabs
        if TESTORG_CHANNEL_ID and TESTORG_CHANNEL_ID in ORG_CONFIG:
            org_config = ORG_CONFIG[TESTORG_CHANNEL_ID]
        else:
            org_config = ORG_CONFIG.get(-1003081443167)

    if not org_config:
        await update.message.reply_text(
            f"No org configured for onboarding.\n\n"
            f"Debug: chat_id={chat_id}, TESTORG={TESTORG_CHANNEL_ID}\n"
            f"ORG_CONFIG keys: {list(ORG_CONFIG.keys())}"
        )
        return

    # If in a group, DM the user
    if update.effective_chat.type in ["group", "supergroup"]:
        try:
            ascii_art = """
███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
█████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
"""
            welcome_msg = f"""{ascii_art}
Welcome to Egregore!

I'll help you get set up. What's your GitHub username?

(Just type your username, like: janesmith)"""

            await context.bot.send_message(chat_id=user.id, text=welcome_msg)
            onboarding_state[user.id] = {
                "step": "awaiting_github",
                "org_config": org_config,
                "first_name": user.first_name
            }
            await update.message.reply_text("Check your DMs! I've sent you onboarding instructions.")
        except Exception as e:
            logger.error(f"Failed to DM user {user.id}: {e}")
            bot_username = context.bot.username
            await update.message.reply_text(
                f"Click here to start: t.me/{bot_username}\n\n"
                "Then just click 'Start' — I'll take it from there."
            )
    else:
        # Already in DM, start directly
        ascii_art = """
███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
█████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
"""
        welcome_msg = f"""{ascii_art}
Welcome to Egregore!

I'll help you get set up. What's your GitHub username?

(Just type your username, like: janesmith)"""

        await update.message.reply_text(welcome_msg)
        onboarding_state[user.id] = {
            "step": "awaiting_github",
            "org_config": org_config,
            "first_name": user.first_name
        }


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle any text message."""
    if not update.message or not update.message.text:
        return

    # Check for onboarding DM first
    if update.effective_chat.type == "private":
        if await handle_onboarding_dm(update, context):
            return

    if not is_allowed(update):
        return

    text = update.message.text.strip()

    # In groups, only respond if mentioned or replied to
    chat_type = update.effective_chat.type
    if chat_type in ["group", "supergroup"]:
        bot_username = context.bot.username
        if f"@{bot_username}" not in text:
            if not (update.message.reply_to_message and
                    update.message.reply_to_message.from_user.id == context.bot.id):
                return
        text = text.replace(f"@{bot_username}", "").strip()

    if not text:
        return

    await handle_question(update, context, text)


# =============================================================================
# NOTIFICATIONS
# =============================================================================

def get_telegram_id(name: str) -> Optional[int]:
    """Look up Telegram ID by person name from Neo4j.

    Matches against name, fullName, or aliases (case-insensitive).
    Examples: 'oz', 'oguzhan', 'Oz Broccoli' all resolve to oz's telegramId.
    """
    name_lower = name.lower().strip()

    # Try exact match on name first (fastest)
    results = run_query(
        "MATCH (p:Person {name: $name}) WHERE p.telegramId IS NOT NULL RETURN p.telegramId AS telegramId",
        {"name": name_lower}
    )
    if results and results[0].get("telegramId"):
        return int(results[0]["telegramId"])

    # Try fuzzy match on fullName or aliases
    results = run_query(
        """MATCH (p:Person)
           WHERE p.telegramId IS NOT NULL AND (
               toLower(p.fullName) CONTAINS $name
               OR $name IN [x IN coalesce(p.aliases, []) | toLower(x)]
           )
           RETURN p.telegramId AS telegramId
           LIMIT 1""",
        {"name": name_lower}
    )
    if results and results[0].get("telegramId"):
        return int(results[0]["telegramId"])

    return None


async def send_notification(bot, recipient: str, message: str, notification_type: str = "mention") -> bool:
    """Send a notification to a team member."""
    telegram_id = get_telegram_id(recipient)
    if not telegram_id:
        logger.warning(f"No Telegram ID found for {recipient}")
        return False

    try:
        await bot.send_message(chat_id=telegram_id, text=message)
        logger.info(f"Notification sent to {recipient} ({telegram_id})")
        return True
    except Exception as e:
        logger.error(f"Failed to send notification to {recipient}: {e}")
        return False


# Global reference to bot for HTTP handler
telegram_bot = None


async def handle_notify_request(request: Request) -> JSONResponse:
    """HTTP endpoint for sending notifications.

    POST /notify
    {
        "recipient": "oz",           # Person name (lowercase)
        "message": "...",            # Notification message
        "type": "handoff|quest|mention"  # Optional
    }
    """
    global telegram_bot

    if not telegram_bot:
        return JSONResponse({"error": "Bot not initialized"}, status_code=503)

    try:
        data = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)

    recipient = data.get("recipient")
    message = data.get("message")
    notification_type = data.get("type", "mention")

    if not recipient or not message:
        return JSONResponse({"error": "Missing recipient or message"}, status_code=400)

    success = await send_notification(telegram_bot, recipient, message, notification_type)

    if success:
        return JSONResponse({"status": "sent", "recipient": recipient})
    else:
        return JSONResponse({"error": f"Could not notify {recipient}"}, status_code=404)


# =============================================================================
# NEW MEMBER ONBOARDING
# =============================================================================

async def add_github_collaborator(github_username: str, repo: str) -> bool:
    """Add a user as collaborator to a GitHub repo."""
    if not GITHUB_TOKEN:
        logger.warning("No GITHUB_TOKEN configured")
        return False

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.put(
                f"https://api.github.com/repos/{repo}/collaborators/{github_username}",
                headers={
                    "Authorization": f"Bearer {GITHUB_TOKEN}",
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28"
                },
                json={"permission": "push"},
                timeout=10
            )
            if resp.status_code in [201, 204]:
                logger.info(f"Added {github_username} as collaborator to {repo}")
                return True
            else:
                logger.error(f"Failed to add collaborator: {resp.status_code} {resp.text}")
                return False
        except Exception as e:
            logger.error(f"GitHub API error: {e}")
            return False


async def create_person_node(name: str, github: str, telegram_id: int, org_config: dict) -> bool:
    """Create a Person node in Neo4j for new member."""
    try:
        driver = get_neo4j_driver_for_org(org_config)
        if not driver:
            return False
        with driver.session() as session:
            session.run(
                """MERGE (p:Person {telegramId: $tid})
                   ON CREATE SET p.name = $name, p.github = $github, p.joined = date()
                   ON MATCH SET p.github = $github""",
                {"name": name.lower(), "github": github, "tid": telegram_id}
            )
        return True
    except Exception as e:
        logger.error(f"Failed to create Person node: {e}")
        return False


def get_neo4j_driver_for_org(org_config: dict):
    """Get Neo4j driver for a specific org."""
    uri = org_config.get("neo4j_uri", "")
    if not uri:
        return None
    return GraphDatabase.driver(
        uri,
        auth=(org_config.get("neo4j_user", "neo4j"), org_config.get("neo4j_password", ""))
    )


async def handle_new_member(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle new members joining a group."""
    if not update.chat_member:
        return

    old_status = update.chat_member.old_chat_member.status
    new_status = update.chat_member.new_chat_member.status

    if new_status not in ["member", "administrator"] or old_status in ["member", "administrator"]:
        return

    new_member = update.chat_member.new_chat_member.user
    chat_id = update.effective_chat.id

    if chat_id not in ORG_CONFIG:
        return

    org_config = ORG_CONFIG[chat_id]
    logger.info(f"New member {new_member.first_name} ({new_member.id}) joined {org_config['name']}")

    try:
        ascii_art = """
███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
█████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
"""
        welcome_msg = f"""{ascii_art}
Welcome to Egregore!

I'll help you get set up. What's your GitHub username?

(Just type your username, like: janesmith)"""

        await context.bot.send_message(chat_id=new_member.id, text=welcome_msg)
        onboarding_state[new_member.id] = {
            "step": "awaiting_github",
            "org_config": org_config,
            "first_name": new_member.first_name
        }
    except Exception as e:
        logger.error(f"Failed to DM new member {new_member.id}: {e}")
        # Post in group with link to start chat
        bot_username = context.bot.username
        await context.bot.send_message(
            chat_id=chat_id,
            text=f"Hey {new_member.first_name}! Click here to get set up: t.me/{bot_username}"
        )


async def handle_onboarding_dm(update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
    """Handle DM responses during onboarding. Returns True if handled."""
    if not update.message or not update.effective_user:
        return False

    user_id = update.effective_user.id
    if user_id not in onboarding_state:
        return False

    state = onboarding_state[user_id]
    text = update.message.text.strip()

    if state["step"] == "awaiting_github":
        github_username = text.replace("@", "").strip()
        await update.message.reply_text(f"Got it! Adding {github_username} to the Egregore repos...")

        success = True
        for repo in ONBOARDING_REPOS:
            if not await add_github_collaborator(github_username, repo):
                success = False

        await create_person_node(
            name=state["first_name"],
            github=github_username,
            telegram_id=user_id,
            org_config=state["org_config"]
        )

        if success:
            complete_msg = f"""You're all set!

I've added you as a collaborator.

Download the zip I'm sending, then:

1. Unzip it (creates 'egregore' folder)
2. cd egregore
3. Type: claude
4. When prompted:
   • "Trust this folder?" → Yes, proceed
   • "Use this API key?" → No (use your subscription)
5. Say: "set me up"

Claude will create everything else automatically."""

            await update.message.reply_text(complete_msg)

            # Generate .mcp.json with org-specific API key
            import io
            import zipfile
            org_config = state["org_config"]
            mcp_api_key = org_config.get("mcp_api_key", "ek_default_key")

            mcp_json_content = json.dumps({
                "$schema": "https://raw.githubusercontent.com/anthropics/claude-code/main/schemas/mcp.json",
                "mcpServers": {
                    "egregore": {
                        "type": "http",
                        "url": "https://curve-labs-core-production.up.railway.app/mcp",
                        "headers": {
                            "Authorization": f"Bearer {mcp_api_key}"
                        }
                    }
                }
            }, indent=2)

            # Bootstrap CLAUDE.md - MCP-based onboarding (no GitHub needed)
            bootstrap_claude_md = """# Egregore Bootstrap

## When user says "set me up"

**Everything comes from MCP. No GitHub, no cloning, no auth needed.**

Show this progress (user sees ONLY these lines):
```
Setting up Egregore...

✓ Downloading configuration
✓ Setting up workspace
✓ Registering you

Welcome to Egregore, [name]!
```

---

## Steps (execute silently)

### Step 1: Call egregore_init MCP tool

Call the MCP tool:
```
mcp__egregore__egregore_init
```

This returns a JSON with:
- `files`: dict of {path: content} to write
- `directories`: list of dirs to create
- `instructions`: ignore this

### Step 2: Write all files

For each file in the response, write it using the Write tool.
The files include CLAUDE.md, settings, and all commands.

**IMPORTANT**: Preserve the .mcp.json that already exists (it has the API key).

### Step 3: Create directories

Create these directories if they don't exist:
- memory/conversations
- memory/artifacts
- memory/quests

### Step 4: Register user

Get user's name:
```bash
git config user.name 2>/dev/null || echo ""
```

Ask ONCE: "What should we call you? (short name like 'oz')"

Register in Neo4j:
```
mcp__egregore__neo4j_query with:
  query: "MERGE (p:Person {name: $shortName}) ON CREATE SET p.fullName = $fullName, p.joined = date() RETURN p.name"
  params: {shortName: "<user answer>", fullName: "<from git config or user answer>"}
```

### Step 5: Show welcome

```
███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
█████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

Welcome, [name]!

/activity  — See what's happening
/handoff   — Leave notes for others
/quest     — Explore open questions
/add       — Capture thoughts & findings

Just start talking, or try a command.
```

---

## Error handling

If MCP call fails: "Setup failed. Check your internet connection and try again."
If Neo4j fails: Continue anyway, show welcome. User can register later.
"""

            # Pre-approved permissions - enumerate all commands for smooth onboarding
            # Bash(*) doesn't work - must specify each command prefix
            settings_json = json.dumps({
                "permissions": {
                    "allow": [
                        "Bash(which:*)", "Bash(brew:*)", "Bash(gh:*)",
                        "Bash(cp:*)", "Bash(rm:*)", "Bash(mv:*)", "Bash(mkdir:*)",
                        "Bash(echo:*)", "Bash(git:*)", "Bash(ls:*)", "Bash(cat:*)",
                        "Bash(cd:*)", "Bash(pwd:*)", "Bash(touch:*)",
                        "Read(**)", "Write(**)", "Edit(**)",
                        "mcp__egregore__neo4j_query",
                        "mcp__egregore__egregore_init"
                    ],
                    "deny": []
                }
            }, indent=2)

            # Minimal zip - just bootstrap, real files come from egregore-core repo
            zip_buffer = io.BytesIO()
            with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
                zf.writestr('egregore/.mcp.json', mcp_json_content)
                zf.writestr('egregore/CLAUDE.md', bootstrap_claude_md)
                zf.writestr('egregore/.claude/settings.json', settings_json)
            zip_buffer.seek(0)

            await context.bot.send_document(
                chat_id=update.effective_chat.id,
                document=zip_buffer,
                filename="egregore-setup.zip",
                caption="Unzip, cd egregore, run 'claude', say 'set me up'"
            )
        else:
            await update.message.reply_text(
                "There was an issue adding you to GitHub. Please check your username and try again."
            )

        del onboarding_state[user_id]
        return True

    return False


# =============================================================================
# SPIRIT ADAPTER ENDPOINTS
# =============================================================================

async def handle_spirit_init(request: Request) -> JSONResponse:
    """Initialize a Spirit node in the bot's database.

    POST /spirit/init
    Headers: X-Admin-Secret: <SPIRIT_ADMIN_SECRET>
    {
        "spirit_id": "spirit-openclaw-cem-alter",
        "name": "Alter",
        "vessel": "cem",
        "platform": "openclaw",
        "trust_level": "elevated"
    }
    """
    # Require admin secret
    if not SPIRIT_ADMIN_SECRET:
        return JSONResponse({"error": "Spirit init not configured"}, status_code=503)

    admin_secret = request.headers.get("X-Admin-Secret", "")
    if not secrets.compare_digest(admin_secret, SPIRIT_ADMIN_SECRET):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)

    try:
        data = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)

    spirit_id = data.get("spirit_id")
    name = data.get("name")
    vessel = data.get("vessel")
    platform = data.get("platform", "unknown")
    trust_level = data.get("trust_level", "standard")

    if not all([spirit_id, name, vessel]):
        return JSONResponse({"error": "Missing required fields"}, status_code=400)

    # Create Spirit node with registration token
    reg_token = f"reg-{uuid.uuid4()}"

    result = run_query("""
        MATCH (p:Person {name: $vessel})
        CREATE (s:Spirit {
            id: $spiritId,
            name: $name,
            platform: $platform,
            status: "pending",
            trustLevel: $trustLevel,
            registrationToken: $regToken,
            tokenExpiresAt: datetime() + duration('PT2H'),
            created: datetime()
        })
        CREATE (s)-[:INVOKED_BY]->(p)
        RETURN s.id AS id, s.registrationToken AS token, s.tokenExpiresAt AS expires
    """, {
        "spiritId": spirit_id,
        "name": name,
        "vessel": vessel,
        "platform": platform,
        "trustLevel": trust_level,
        "regToken": reg_token
    })

    if not result:
        return JSONResponse({"error": "Failed to create Spirit (vessel not found?)"}, status_code=404)

    return JSONResponse({
        "status": "created",
        "spirit_id": result[0]["id"],
        "registration_token": result[0]["token"],
        "expires": str(result[0]["expires"])
    })


async def handle_spirit_activate(request: Request) -> JSONResponse:
    """Activate a pending external Spirit.

    POST /spirit/activate
    {
        "registration_token": "reg-...",
        "platform": {"name": "openclaw", "version": "2026.2.2"},
        "endpoint": "http://localhost:8765",
        "capabilities": ["shell", "web", "fs"]
    }

    Returns API key (one-time) on success.
    """
    try:
        data = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)

    registration_token = data.get("registration_token")
    platform_info = data.get("platform", {})
    endpoint = data.get("endpoint")
    capabilities = data.get("capabilities", [])

    if not registration_token:
        return JSONResponse({"error": "Missing registration_token"}, status_code=400)

    logger.info(f"Spirit activation attempt with token: {registration_token[:20]}...")

    # Find pending Spirit with this token (not expired)
    result = run_query("""
        MATCH (s:Spirit {registrationToken: $token, status: "pending"})
        WHERE s.tokenExpiresAt > datetime()
        RETURN s.id AS id, s.name AS name, s.trustLevel AS trustLevel
    """, {"token": registration_token})

    logger.info(f"Spirit query result: {result}")

    if not result:
        # Debug: check if Spirit exists at all
        debug_result = run_query("""
            MATCH (s:Spirit {registrationToken: $token})
            RETURN s.status AS status, s.tokenExpiresAt AS expires, datetime() AS now
        """, {"token": registration_token})
        # Count ALL Spirits and ALL nodes
        count_result = run_query("MATCH (s:Spirit) RETURN count(s) AS spirit_count")
        all_labels = run_query("CALL db.labels() YIELD label RETURN collect(label) AS labels")
        logger.info(f"Spirit debug query: {debug_result}, counts: {count_result}, labels: {all_labels}")
        return JSONResponse({
            "error": "Invalid or expired token",
            "debug_token_match": debug_result,
            "spirit_count": count_result,
            "db_labels": all_labels
        }, status_code=404)

    spirit = result[0]
    spirit_id = spirit["id"]
    spirit_name = spirit["name"]

    # Generate API key: sk_egregore_[short_id]_[random]
    short_id = spirit_id.replace("spirit-", "")[:15].replace("-", "_")
    api_key = f"sk_egregore_{short_id}_{secrets.token_hex(12)}"
    api_key_hash = hashlib.sha256(api_key.encode()).hexdigest()

    # Activate the Spirit
    run_query("""
        MATCH (s:Spirit {registrationToken: $token})
        SET s.status = "manifest",
            s.apiKeyHash = $apiKeyHash,
            s.endpoint = $endpoint,
            s.platformVersion = $version,
            s.capabilities = $capabilities,
            s.activatedAt = datetime(),
            s.lastHeartbeat = datetime()
        REMOVE s.registrationToken, s.tokenExpiresAt
    """, {
        "token": registration_token,
        "apiKeyHash": api_key_hash,
        "endpoint": endpoint,
        "version": platform_info.get("version", "unknown"),
        "capabilities": capabilities
    })

    # Log the activation
    log_event(
        component="spirit",
        operation="activate",
        success=True,
        metadata={
            "spirit_id": spirit_id,
            "spirit_name": spirit_name,
            "platform": platform_info.get("name", "unknown"),
            "platform_version": platform_info.get("version", "unknown"),
            "capabilities": capabilities
        }
    )

    logger.info(f"Spirit activated: {spirit_id} ({spirit_name})")

    return JSONResponse({
        "status": "activated",
        "spirit_id": spirit_id,
        "spirit_name": spirit_name,
        "api_key": api_key  # One-time return - store this!
    })


async def handle_spirit_heartbeat(request: Request) -> JSONResponse:
    """Heartbeat from an active Spirit.

    POST /spirit/heartbeat
    Headers: Authorization: Bearer sk_egregore_...
    {
        "status": "idle" | "working" | "completing",
        "task_id": "..." (optional)
    }
    """
    # Validate API key
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer sk_egregore_"):
        return JSONResponse({"error": "Invalid authorization"}, status_code=401)

    api_key = auth_header.replace("Bearer ", "")
    api_key_hash = hashlib.sha256(api_key.encode()).hexdigest()

    # Find Spirit by API key hash
    result = run_query("""
        MATCH (s:Spirit {apiKeyHash: $hash, status: "manifest"})
        SET s.lastHeartbeat = datetime()
        RETURN s.id AS id, s.name AS name
    """, {"hash": api_key_hash})

    if not result:
        return JSONResponse({"error": "Spirit not found or not active"}, status_code=404)

    spirit = result[0]

    try:
        data = await request.json()
        status = data.get("status", "idle")
    except Exception:
        status = "idle"

    logger.debug(f"Heartbeat from {spirit['name']}: {status}")

    return JSONResponse({
        "status": "ok",
        "spirit_id": spirit["id"]
    })


async def handle_spirit_callback(request: Request) -> JSONResponse:
    """Callback when a Spirit completes a task.

    POST /spirit/callback
    Headers: Authorization: Bearer sk_egregore_...
    {
        "task_id": "...",
        "status": "fulfilled" | "failed" | "timeout",
        "outputs": [...],
        "essence": {"tokens_in": N, "tokens_out": N, "model": "...", "cost_usd": N}
    }
    """
    # Validate API key
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer sk_egregore_"):
        return JSONResponse({"error": "Invalid authorization"}, status_code=401)

    api_key = auth_header.replace("Bearer ", "")
    api_key_hash = hashlib.sha256(api_key.encode()).hexdigest()

    # Find Spirit by API key hash
    result = run_query("""
        MATCH (s:Spirit {apiKeyHash: $hash, status: "manifest"})-[:INVOKED_BY]->(p:Person)
        RETURN s.id AS spirit_id, s.name AS spirit_name, p.name AS vessel_name
    """, {"hash": api_key_hash})

    if not result:
        return JSONResponse({"error": "Spirit not found or not active"}, status_code=404)

    spirit_info = result[0]

    try:
        data = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)

    task_id = data.get("task_id", "unknown")
    status = data.get("status", "fulfilled")
    outputs = data.get("outputs", [])
    essence = data.get("essence", {})

    # Log the task completion
    log_event(
        component="spirit",
        operation=f"task:{status}",
        tokens_in=essence.get("tokens_in", 0),
        tokens_out=essence.get("tokens_out", 0),
        model=essence.get("model", "unknown"),
        success=(status == "fulfilled"),
        user_name=spirit_info["vessel_name"],
        metadata={
            "spirit_id": spirit_info["spirit_id"],
            "spirit_name": spirit_info["spirit_name"],
            "task_id": task_id,
            "outputs_count": len(outputs),
            "cost_usd": essence.get("cost_usd", 0)
        }
    )

    # Update Spirit heartbeat
    run_query("""
        MATCH (s:Spirit {id: $id})
        SET s.lastHeartbeat = datetime()
    """, {"id": spirit_info["spirit_id"]})

    logger.info(f"Task callback from {spirit_info['spirit_name']}: {task_id} -> {status}")

    # TODO: Process outputs (create artifacts, sessions, etc.) based on trust level
    # For now, just acknowledge

    return JSONResponse({
        "status": "received",
        "task_id": task_id,
        "outputs_processed": len(outputs)
    })


# =============================================================================
# MAIN
# =============================================================================

def main() -> None:
    """Start the bot."""
    global telegram_bot

    ptb_app = Application.builder().token(BOT_TOKEN).build()
    telegram_bot = ptb_app.bot

    ptb_app.add_handler(CommandHandler("start", start_command))
    ptb_app.add_handler(CommandHandler("activity", activity_command))
    ptb_app.add_handler(CommandHandler("debug", debug_command))
    ptb_app.add_handler(CommandHandler("onboard", onboard_command))
    ptb_app.add_handler(ChatMemberHandler(handle_new_member, ChatMemberHandler.CHAT_MEMBER))
    ptb_app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    if WEBHOOK_URL:
        logger.info(f"Starting webhook + notification API on port {PORT}")
        import asyncio

        async def handle_telegram_webhook(request: Request) -> PlainTextResponse:
            """Handle incoming Telegram webhook updates."""
            data = await request.json()
            update = Update.de_json(data, ptb_app.bot)
            await ptb_app.process_update(update)
            return PlainTextResponse("ok")

        async def health_check(request: Request) -> PlainTextResponse:
            """Health check endpoint."""
            return PlainTextResponse("ok")

        # Single Starlette app with all endpoints
        # Use token as webhook path for security (only Telegram knows it)
        webhook_path = f"/{BOT_TOKEN}"
        starlette_app = Starlette(
            routes=[
                Route(webhook_path, handle_telegram_webhook, methods=["POST"]),
                Route("/notify", handle_notify_request, methods=["POST"]),
                Route("/health", health_check, methods=["GET"]),
                # Spirit adapter endpoints
                Route("/spirit/init", handle_spirit_init, methods=["POST"]),
                Route("/spirit/activate", handle_spirit_activate, methods=["POST"]),
                Route("/spirit/heartbeat", handle_spirit_heartbeat, methods=["POST"]),
                Route("/spirit/callback", handle_spirit_callback, methods=["POST"]),
            ] + get_mcp_routes()  # MCP server endpoints
        )

        async def run_server():
            # Initialize PTB app
            await ptb_app.initialize()
            await ptb_app.start()

            # Set webhook (use token as path for security)
            webhook_url = f"https://{WEBHOOK_URL}/{BOT_TOKEN}"
            await ptb_app.bot.set_webhook(url=webhook_url)
            logger.info(f"Webhook set to https://{WEBHOOK_URL}/[TOKEN]")

            # Run uvicorn
            config = uvicorn.Config(starlette_app, host="0.0.0.0", port=PORT, log_level="info")
            server = uvicorn.Server(config)
            await server.serve()

        asyncio.run(run_server())
    else:
        logger.info("Starting polling mode...")
        # In polling mode, use simple run_polling
        ptb_app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
