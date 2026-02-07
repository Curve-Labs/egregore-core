"""
Neo4j query helpers for testing.

Extracted from test_retrievals.py for reuse.
"""

import os
from pathlib import Path
from neo4j import GraphDatabase
from dotenv import load_dotenv

# Load env from telegram-bot (has Neo4j creds)
_env_path = Path(__file__).parent.parent.parent / "telegram-bot" / ".env"
if _env_path.exists():
    load_dotenv(_env_path)


def get_neo4j_config() -> dict:
    """Get Neo4j connection config from environment."""
    return {
        "uri": os.environ.get("NEO4J_URI", ""),
        "user": os.environ.get("NEO4J_USER", ""),
        "password": os.environ.get("NEO4J_PASSWORD", ""),
    }


def create_driver():
    """Create Neo4j driver from environment config."""
    config = get_neo4j_config()
    if not config["uri"]:
        raise ValueError("NEO4J_URI not set in environment")
    return GraphDatabase.driver(
        config["uri"], auth=(config["user"], config["password"])
    )


def run_query(driver, query: str, params: dict | None = None) -> list[dict]:
    """Run Cypher query and return results as list of dicts."""
    with driver.session() as session:
        result = session.run(query, params or {})
        return [dict(record) for record in result]


def get_node_count(driver, label: str) -> int:
    """Get count of nodes with given label."""
    result = run_query(driver, f"MATCH (n:{label}) RETURN count(n) as count")
    return result[0]["count"] if result else 0


def get_all_artifacts(driver) -> list[dict]:
    """Get all artifacts from Neo4j."""
    return run_query(
        driver,
        """
        MATCH (a:Artifact)
        RETURN a.id AS id, a.title AS title, a.type AS type,
               a.author AS author, a.filePath AS filePath
        """,
    )


def get_all_sessions(driver) -> list[dict]:
    """Get all sessions from Neo4j."""
    return run_query(
        driver,
        """
        MATCH (s:Session)
        OPTIONAL MATCH (s)-[:BY]->(p:Person)
        RETURN s.id AS id, s.topic AS topic, s.date AS date,
               s.filePath AS filePath, p.name AS author
        """,
    )


def get_all_quests(driver) -> list[dict]:
    """Get all quests from Neo4j."""
    return run_query(
        driver,
        """
        MATCH (q:Quest)
        RETURN q.id AS id, q.title AS title, q.status AS status,
               q.filePath AS filePath
        """,
    )


def get_recent_activity(driver, days: int = 7) -> list[dict]:
    """Get recent sessions from last N days."""
    return run_query(
        driver,
        """
        MATCH (s:Session)-[:BY]->(p:Person)
        WHERE s.date >= date() - duration('P' + $days + 'D')
        RETURN s.date AS date, s.topic AS topic, p.name AS person
        ORDER BY s.date DESC
        """,
        {"days": str(days)},
    )
