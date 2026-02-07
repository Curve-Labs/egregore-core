"""
Egregore Neo4j Backfill Script

Syncs filesystem artifacts and sessions to Neo4j.
Run after audit to fix sync gaps.

Run: cd tests && source .venv/bin/activate && python backfill_neo4j.py
"""

import os
import re
import yaml
from pathlib import Path
from datetime import datetime

from dotenv import load_dotenv
from neo4j import GraphDatabase

# Load env from telegram-bot
load_dotenv(Path(__file__).parent.parent / "telegram-bot" / ".env")

NEO4J_URI = os.environ.get("NEO4J_URI", "")
NEO4J_USER = os.environ.get("NEO4J_USER", "")
NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD", "")

MEMORY_PATH = Path(__file__).parent.parent / "memory"


def get_driver():
    return GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))


def parse_frontmatter(content: str) -> tuple[dict, str]:
    """Parse YAML frontmatter from markdown file."""
    if not content.startswith("---"):
        return {}, content

    parts = content.split("---", 2)
    if len(parts) < 3:
        return {}, content

    try:
        frontmatter = yaml.safe_load(parts[1])
        body = parts[2].strip()
        return frontmatter or {}, body
    except yaml.YAMLError:
        return {}, content


def extract_date_author_from_filename(filename: str) -> tuple[str, str, str]:
    """Extract date, author, and title from filename.

    Handles formats:
    - 2026-01-27-oz-famp-proposal.md (full date)
    - 27-oz-bot-deploy.md (day only, used in conversations/2026-01/)
    """
    name = filename.replace(".md", "")
    parts = name.split("-")

    # Full date format: 2026-01-27-oz-title
    if len(parts) >= 4 and parts[0].isdigit() and len(parts[0]) == 4:
        date = f"{parts[0]}-{parts[1]}-{parts[2]}"
        author = parts[3]
        title = "-".join(parts[4:]) if len(parts) > 4 else parts[3]
        return date, author, title

    # Day-only format: 27-oz-title (common in conversations/)
    if len(parts) >= 2 and parts[0].isdigit() and len(parts[0]) <= 2:
        day = parts[0]
        author = parts[1]
        title = "-".join(parts[2:]) if len(parts) > 2 else author
        return day, author, title

    return "", "", name


def backfill_artifacts(driver):
    """Sync all filesystem artifacts to Neo4j."""
    print("\n=== Backfilling Artifacts ===")

    artifacts_path = MEMORY_PATH / "artifacts"
    if not artifacts_path.exists():
        print("  No artifacts directory found")
        return

    created = 0
    updated = 0

    for f in artifacts_path.glob("*.md"):
        if f.name.startswith("_") or f.name == "README.md":
            continue

        content = f.read_text()
        frontmatter, body = parse_frontmatter(content)

        # Get metadata from frontmatter or filename
        date_str, author_from_file, title_slug = extract_date_author_from_filename(f.name)

        artifact_id = frontmatter.get("id") or f.stem
        title = frontmatter.get("title") or title_slug.replace("-", " ").title()
        artifact_type = frontmatter.get("type", "thought")
        author = frontmatter.get("author") or author_from_file
        created_date = frontmatter.get("date") or frontmatter.get("created") or date_str
        quests = frontmatter.get("quests", [])
        summary = frontmatter.get("summary", "")

        # Ensure quests is a list
        if isinstance(quests, str):
            quests = [quests]

        with driver.session() as session:
            # Create or update artifact
            result = session.run("""
                MERGE (a:Artifact {id: $id})
                ON CREATE SET
                    a.title = $title,
                    a.type = $type,
                    a.author = $author,
                    a.created = $created,
                    a.summary = $summary,
                    a.filePath = $filePath,
                    a._synced = datetime()
                ON MATCH SET
                    a.title = $title,
                    a.type = $type,
                    a.author = $author,
                    a.summary = $summary,
                    a.filePath = $filePath,
                    a._synced = datetime()
                RETURN a.id AS id,
                       CASE WHEN a._synced = datetime() THEN 'created' ELSE 'updated' END AS action
            """, {
                "id": artifact_id,
                "title": title,
                "type": artifact_type,
                "author": author,
                "created": created_date,
                "summary": summary,
                "filePath": str(f.relative_to(MEMORY_PATH.parent))
            })

            record = result.single()
            if record:
                print(f"  {record['action']}: {title[:40]}...")
                if record['action'] == 'created':
                    created += 1
                else:
                    updated += 1

            # Link to author (Person)
            if author:
                session.run("""
                    MATCH (a:Artifact {id: $artifact_id})
                    MERGE (p:Person {name: $author})
                    MERGE (a)-[:CONTRIBUTED_BY]->(p)
                """, {"artifact_id": artifact_id, "author": author.lower()})

            # Link to quests
            for quest_id in quests:
                if quest_id:
                    session.run("""
                        MATCH (a:Artifact {id: $artifact_id})
                        MERGE (q:Quest {id: $quest_id})
                        MERGE (a)-[:PART_OF]->(q)
                    """, {"artifact_id": artifact_id, "quest_id": quest_id})

    print(f"\n  Created: {created}, Updated: {updated}")


def backfill_sessions(driver):
    """Sync all filesystem sessions to Neo4j with filePath."""
    print("\n=== Backfilling Sessions ===")

    conversations_path = MEMORY_PATH / "conversations"
    if not conversations_path.exists():
        print("  No conversations directory found")
        return

    created = 0
    updated = 0

    for f in conversations_path.rglob("*.md"):
        if f.name in ["index.md", "_template.md"]:
            continue

        content = f.read_text()
        frontmatter, body = parse_frontmatter(content)

        # Extract from filename: 27-oz-bot-neo4j-deploy-handoff.md
        date_str, author, topic_slug = extract_date_author_from_filename(f.name)

        # Get parent folder for full date (2026-01)
        parent = f.parent.name
        full_date = "2026-01-01"  # Default fallback

        if parent.startswith("2") and "-" in parent:
            year_month = parent  # e.g., "2026-01"
            # Filename might start with day: "27-oz-something.md"
            day_match = re.match(r'^(\d{1,2})-', f.name)
            if day_match:
                day = day_match.group(1).zfill(2)
                full_date = f"{year_month}-{day}"
            elif date_str and len(date_str.split("-")) == 3:
                full_date = date_str
            else:
                full_date = f"{year_month}-01"
        elif date_str and len(date_str.split("-")) == 3:
            full_date = date_str

        # Session ID from filename
        session_id = f.stem

        # Get metadata
        author = frontmatter.get("author") or author
        topic = frontmatter.get("topic") or topic_slug.replace("-", " ").title()
        project = frontmatter.get("project", "")
        summary = frontmatter.get("summary", "")

        # Extract summary from body if not in frontmatter
        if not summary and body:
            # Look for "## Session Summary" or first paragraph
            lines = body.split("\n")
            for i, line in enumerate(lines):
                if line.strip() and not line.startswith("#"):
                    summary = line.strip()[:200]
                    break

        with driver.session() as session:
            # Create or update session
            result = session.run("""
                MERGE (s:Session {id: $id})
                ON CREATE SET
                    s.topic = $topic,
                    s.date = date($date),
                    s.summary = $summary,
                    s.filePath = $filePath,
                    s._synced = datetime()
                ON MATCH SET
                    s.topic = COALESCE(s.topic, $topic),
                    s.summary = COALESCE(s.summary, $summary),
                    s.filePath = $filePath,
                    s._synced = datetime()
                RETURN s.id AS id
            """, {
                "id": session_id,
                "topic": topic,
                "date": full_date if full_date else "2026-01-01",
                "summary": summary,
                "filePath": str(f.relative_to(MEMORY_PATH.parent))
            })

            record = result.single()
            if record:
                print(f"  synced: {session_id[:40]}...")
                created += 1

            # Link to author
            if author:
                session.run("""
                    MATCH (s:Session {id: $session_id})
                    MERGE (p:Person {name: $author})
                    MERGE (s)-[:BY]->(p)
                """, {"session_id": session_id, "author": author.lower()})

            # Link to project
            if project:
                session.run("""
                    MATCH (s:Session {id: $session_id})
                    MERGE (proj:Project {name: $project})
                    MERGE (s)-[:ABOUT]->(proj)
                """, {"session_id": session_id, "project": project.lower()})

    print(f"\n  Synced: {created}")


def backfill_quests(driver):
    """Ensure all filesystem quests are in Neo4j."""
    print("\n=== Backfilling Quests ===")

    quests_path = MEMORY_PATH / "quests"
    if not quests_path.exists():
        print("  No quests directory found")
        return

    created = 0

    for f in quests_path.glob("*.md"):
        if f.name in ["index.md", "_template.md"]:
            continue

        content = f.read_text()
        frontmatter, body = parse_frontmatter(content)

        quest_id = frontmatter.get("id") or f.stem
        title = frontmatter.get("title") or f.stem.replace("-", " ").title()
        status = frontmatter.get("status", "active")
        started_by = frontmatter.get("started_by", "")
        projects = frontmatter.get("projects", [])

        if isinstance(projects, str):
            projects = [projects]

        with driver.session() as session:
            result = session.run("""
                MERGE (q:Quest {id: $id})
                ON CREATE SET
                    q.title = $title,
                    q.status = $status,
                    q.filePath = $filePath,
                    q._synced = datetime()
                ON MATCH SET
                    q.title = COALESCE(q.title, $title),
                    q.filePath = $filePath,
                    q._synced = datetime()
                RETURN q.id AS id
            """, {
                "id": quest_id,
                "title": title,
                "status": status,
                "filePath": str(f.relative_to(MEMORY_PATH.parent))
            })

            record = result.single()
            if record:
                print(f"  synced: {quest_id}")
                created += 1

            # Link to starter
            if started_by:
                session.run("""
                    MATCH (q:Quest {id: $quest_id})
                    MERGE (p:Person {name: $author})
                    MERGE (q)-[:STARTED_BY]->(p)
                """, {"quest_id": quest_id, "author": started_by.lower()})

            # Link to projects
            for proj in projects:
                if proj:
                    session.run("""
                        MATCH (q:Quest {id: $quest_id})
                        MERGE (proj:Project {name: $project})
                        MERGE (q)-[:RELATES_TO]->(proj)
                    """, {"quest_id": quest_id, "project": proj.lower()})

    print(f"\n  Synced: {created}")


def main():
    print("=" * 60)
    print("EGREGORE NEO4J BACKFILL")
    print("=" * 60)

    driver = get_driver()

    try:
        backfill_artifacts(driver)
        backfill_sessions(driver)
        backfill_quests(driver)

        print("\n" + "=" * 60)
        print("BACKFILL COMPLETE")
        print("=" * 60)
        print("\nRun test_retrievals.py again to verify fixes.")

    finally:
        driver.close()


if __name__ == "__main__":
    main()
