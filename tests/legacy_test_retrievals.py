"""
Egregore Retrieval Tests

Tests for knowledge graph retrieval quality:
1. Neo4j connection and basic queries
2. Filesystem vs Neo4j sync comparison
3. Data completeness checks

Run: cd tests && uv run python test_retrievals.py
"""

import os
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict

from dotenv import load_dotenv

# Load env from telegram-bot (has Neo4j creds)
load_dotenv(Path(__file__).parent.parent / "telegram-bot" / ".env")

from neo4j import GraphDatabase

# =============================================================================
# CONFIG
# =============================================================================

NEO4J_URI = os.environ.get("NEO4J_URI", "")
NEO4J_USER = os.environ.get("NEO4J_USER", "")
NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD", "")

MEMORY_PATH = Path(__file__).parent.parent / "memory"

# =============================================================================
# NEO4J HELPERS
# =============================================================================

def get_driver():
    """Create Neo4j driver."""
    if not NEO4J_URI:
        print("ERROR: NEO4J_URI not set")
        sys.exit(1)
    return GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))


def run_query(driver, query: str, params: dict = None) -> list:
    """Run Cypher query and return results."""
    with driver.session() as session:
        result = session.run(query, params or {})
        return [dict(record) for record in result]


# =============================================================================
# FILESYSTEM HELPERS
# =============================================================================

def get_filesystem_artifacts() -> list:
    """Get all artifacts from filesystem."""
    artifacts_path = MEMORY_PATH / "artifacts"
    if not artifacts_path.exists():
        return []

    artifacts = []
    for f in artifacts_path.glob("*.md"):
        if f.name.startswith("_"):
            continue
        artifacts.append({
            "filename": f.name,
            "path": str(f),
            "size": f.stat().st_size,
        })
    return artifacts


def get_filesystem_sessions() -> list:
    """Get all session/conversation files from filesystem."""
    conversations_path = MEMORY_PATH / "conversations"
    if not conversations_path.exists():
        return []

    sessions = []
    for f in conversations_path.rglob("*.md"):
        if f.name in ["index.md", "_template.md"]:
            continue
        sessions.append({
            "filename": f.name,
            "path": str(f),
            "size": f.stat().st_size,
        })
    return sessions


def get_filesystem_quests() -> list:
    """Get all quests from filesystem."""
    quests_path = MEMORY_PATH / "quests"
    if not quests_path.exists():
        return []

    quests = []
    for f in quests_path.glob("*.md"):
        if f.name in ["index.md", "_template.md"]:
            continue
        quests.append({
            "filename": f.name,
            "id": f.stem,
            "path": str(f),
        })
    return quests


# =============================================================================
# TESTS
# =============================================================================

def test_neo4j_connection(driver) -> bool:
    """Test basic Neo4j connectivity."""
    print("\n=== Test: Neo4j Connection ===")
    try:
        result = run_query(driver, "RETURN 1 as n")
        assert result[0]["n"] == 1
        print("PASS: Connected to Neo4j")
        return True
    except Exception as e:
        print(f"FAIL: {e}")
        return False


def test_node_counts(driver) -> dict:
    """Count nodes by type."""
    print("\n=== Test: Node Counts ===")

    counts = {}
    for label in ["Person", "Project", "Quest", "Artifact", "Session"]:
        result = run_query(driver, f"MATCH (n:{label}) RETURN count(n) as count")
        counts[label] = result[0]["count"]
        print(f"  {label}: {counts[label]}")

    return counts


def test_query_results(driver) -> dict:
    """Test each predefined query returns results."""
    print("\n=== Test: Query Results ===")

    queries = {
        "recent_activity": """
            MATCH (s:Session)-[:BY]->(p:Person)
            WHERE s.date >= date() - duration('P7D')
            RETURN s.date AS date, s.topic AS topic, p.name AS person
            ORDER BY s.date DESC LIMIT 10
        """,
        "active_quests": """
            MATCH (q:Quest {status: 'active'})
            RETURN q.id AS id, q.title AS title
        """,
        "all_people": """
            MATCH (p:Person)
            OPTIONAL MATCH (p)-[:WORKS_ON]->(proj:Project)
            RETURN p.name AS name, collect(DISTINCT proj.name) AS projects
        """,
        "all_projects": """
            MATCH (proj:Project)
            RETURN proj.name AS name, proj.domain AS domain
        """,
        "all_artifacts": """
            MATCH (a:Artifact)
            RETURN a.title AS title, a.type AS type, a.author AS author
        """,
        "all_sessions": """
            MATCH (s:Session)
            OPTIONAL MATCH (s)-[:BY]->(p:Person)
            RETURN s.id AS id, s.topic AS topic, s.date AS date,
                   s.file AS file, s.filePath AS filePath, p.name AS person
        """,
    }

    results = {}
    for name, cypher in queries.items():
        try:
            result = run_query(driver, cypher)
            results[name] = result
            status = "PASS" if result else "WARN (empty)"
            print(f"  {name}: {len(result)} results - {status}")
        except Exception as e:
            results[name] = []
            print(f"  {name}: FAIL - {e}")

    return results


def test_filesystem_neo4j_sync(driver) -> dict:
    """Compare filesystem vs Neo4j data."""
    print("\n=== Test: Filesystem vs Neo4j Sync ===")

    gaps = {
        "artifacts_missing_in_neo4j": [],
        "sessions_missing_in_neo4j": [],
        "quests_missing_in_neo4j": [],
        "neo4j_sessions_missing_filepath": [],
    }

    # Artifacts - compare by filePath (most accurate)
    fs_artifacts = get_filesystem_artifacts()
    neo4j_artifacts = run_query(driver, "MATCH (a:Artifact) RETURN a.title AS title, a.id AS id, a.filePath AS filePath")
    neo4j_filepaths = {a["filePath"] for a in neo4j_artifacts if a["filePath"]}
    neo4j_ids = {a["id"] for a in neo4j_artifacts if a["id"]}

    for a in fs_artifacts:
        if a["filename"] == "README.md":
            continue  # Skip README

        # Check by filePath or ID (which is the filename stem)
        expected_path = f"memory/artifacts/{a['filename']}"
        file_id = a["filename"].replace(".md", "")

        if expected_path not in neo4j_filepaths and file_id not in neo4j_ids:
            gaps["artifacts_missing_in_neo4j"].append(a["filename"])

    print(f"  Filesystem artifacts: {len(fs_artifacts)}")
    print(f"  Neo4j artifacts: {len(neo4j_artifacts)}")
    print(f"  Missing in Neo4j: {len(gaps['artifacts_missing_in_neo4j'])}")
    if gaps["artifacts_missing_in_neo4j"]:
        for f in gaps["artifacts_missing_in_neo4j"][:5]:
            print(f"    - {f}")
        if len(gaps["artifacts_missing_in_neo4j"]) > 5:
            print(f"    ... and {len(gaps['artifacts_missing_in_neo4j']) - 5} more")

    # Sessions
    fs_sessions = get_filesystem_sessions()
    neo4j_sessions = run_query(driver, """
        MATCH (s:Session)
        RETURN s.id AS id, s.topic AS topic, s.file AS file, s.filePath AS filePath
    """)

    # Check sessions missing filePath
    for s in neo4j_sessions:
        if not s.get("filePath") and not s.get("file"):
            gaps["neo4j_sessions_missing_filepath"].append(s.get("id") or s.get("topic", "unknown"))

    print(f"\n  Filesystem sessions: {len(fs_sessions)}")
    print(f"  Neo4j sessions: {len(neo4j_sessions)}")
    print(f"  Neo4j sessions missing filePath: {len(gaps['neo4j_sessions_missing_filepath'])}")

    # Quests
    fs_quests = get_filesystem_quests()
    neo4j_quests = run_query(driver, "MATCH (q:Quest) RETURN q.id AS id")
    neo4j_quest_ids = {q["id"] for q in neo4j_quests if q["id"]}

    for q in fs_quests:
        if q["id"] not in neo4j_quest_ids:
            gaps["quests_missing_in_neo4j"].append(q["id"])

    print(f"\n  Filesystem quests: {len(fs_quests)}")
    print(f"  Neo4j quests: {len(neo4j_quests)}")
    print(f"  Missing in Neo4j: {len(gaps['quests_missing_in_neo4j'])}")
    if gaps["quests_missing_in_neo4j"]:
        for q in gaps["quests_missing_in_neo4j"]:
            print(f"    - {q}")

    return gaps


def test_relationship_completeness(driver) -> dict:
    """Check relationship completeness."""
    print("\n=== Test: Relationship Completeness ===")

    issues = {}

    # Sessions without BY relationship
    result = run_query(driver, """
        MATCH (s:Session)
        WHERE NOT (s)-[:BY]->(:Person)
        RETURN count(s) as count
    """)
    issues["sessions_without_author"] = result[0]["count"]
    print(f"  Sessions without author (BY): {issues['sessions_without_author']}")

    # Artifacts without CONTRIBUTED_BY
    result = run_query(driver, """
        MATCH (a:Artifact)
        WHERE NOT (a)-[:CONTRIBUTED_BY]->(:Person)
        RETURN count(a) as count
    """)
    issues["artifacts_without_author"] = result[0]["count"]
    print(f"  Artifacts without author (CONTRIBUTED_BY): {issues['artifacts_without_author']}")

    # Quests without STARTED_BY
    result = run_query(driver, """
        MATCH (q:Quest)
        WHERE NOT (q)-[:STARTED_BY]->(:Person)
        RETURN count(q) as count
    """)
    issues["quests_without_starter"] = result[0]["count"]
    print(f"  Quests without starter (STARTED_BY): {issues['quests_without_starter']}")

    # Artifacts without quest link
    result = run_query(driver, """
        MATCH (a:Artifact)
        WHERE NOT (a)-[:PART_OF]->(:Quest)
        RETURN count(a) as count
    """)
    issues["artifacts_without_quest"] = result[0]["count"]
    print(f"  Artifacts without quest (PART_OF): {issues['artifacts_without_quest']}")

    return issues


def test_data_quality(driver) -> dict:
    """Check data quality issues."""
    print("\n=== Test: Data Quality ===")

    issues = {}

    # Sessions with null/empty topic
    result = run_query(driver, """
        MATCH (s:Session)
        WHERE s.topic IS NULL OR s.topic = ''
        RETURN count(s) as count
    """)
    issues["sessions_no_topic"] = result[0]["count"]
    print(f"  Sessions without topic: {issues['sessions_no_topic']}")

    # Sessions with null/empty summary
    result = run_query(driver, """
        MATCH (s:Session)
        WHERE s.summary IS NULL OR s.summary = ''
        RETURN count(s) as count
    """)
    issues["sessions_no_summary"] = result[0]["count"]
    print(f"  Sessions without summary: {issues['sessions_no_summary']}")

    # Artifacts with null/empty title
    result = run_query(driver, """
        MATCH (a:Artifact)
        WHERE a.title IS NULL OR a.title = ''
        RETURN count(a) as count
    """)
    issues["artifacts_no_title"] = result[0]["count"]
    print(f"  Artifacts without title: {issues['artifacts_no_title']}")

    return issues


# =============================================================================
# MAIN
# =============================================================================

def main():
    print("=" * 60)
    print("EGREGORE RETRIEVAL TESTS")
    print("=" * 60)
    print(f"\nMemory path: {MEMORY_PATH}")
    print(f"Memory exists: {MEMORY_PATH.exists()}")

    driver = get_driver()

    try:
        # Run all tests
        test_neo4j_connection(driver)
        counts = test_node_counts(driver)
        query_results = test_query_results(driver)
        sync_gaps = test_filesystem_neo4j_sync(driver)
        relationship_issues = test_relationship_completeness(driver)
        quality_issues = test_data_quality(driver)

        # Summary
        print("\n" + "=" * 60)
        print("SUMMARY")
        print("=" * 60)

        total_issues = (
            len(sync_gaps["artifacts_missing_in_neo4j"]) +
            len(sync_gaps["sessions_missing_in_neo4j"]) +
            len(sync_gaps["quests_missing_in_neo4j"]) +
            len(sync_gaps["neo4j_sessions_missing_filepath"]) +
            relationship_issues["sessions_without_author"] +
            relationship_issues["artifacts_without_author"] +
            relationship_issues["quests_without_starter"] +
            quality_issues["sessions_no_topic"] +
            quality_issues["sessions_no_summary"]
        )

        print(f"\nTotal issues found: {total_issues}")

        if total_issues > 0:
            print("\nTop issues to fix:")
            if sync_gaps["artifacts_missing_in_neo4j"]:
                print(f"  1. {len(sync_gaps['artifacts_missing_in_neo4j'])} artifacts not in Neo4j")
            if sync_gaps["neo4j_sessions_missing_filepath"]:
                print(f"  2. {len(sync_gaps['neo4j_sessions_missing_filepath'])} sessions missing filePath")
            if relationship_issues["artifacts_without_author"]:
                print(f"  3. {relationship_issues['artifacts_without_author']} artifacts without author link")
            if quality_issues["sessions_no_summary"]:
                print(f"  4. {quality_issues['sessions_no_summary']} sessions without summary")

    finally:
        driver.close()


if __name__ == "__main__":
    main()
