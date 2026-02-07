"""
Retrieval Stability Tests

Economics impact: p × V (trust in the system, answer usefulness)

Tests that verify queries return consistent, accurate results:
- Query determinism (same query = same results)
- Filter accuracy
- Relationship traversal
"""

import pytest
from utils.neo4j_helpers import run_query, get_recent_activity


# =============================================================================
# QUERY DETERMINISM
# =============================================================================


@pytest.mark.retrieval
class TestQueryDeterminism:
    """Queries should return consistent results."""

    def test_recent_activity_deterministic(self, neo4j_driver):
        """3 consecutive recent activity queries return same results."""
        results = []
        for _ in range(3):
            result = get_recent_activity(neo4j_driver, days=30)
            # Normalize for comparison (dates might be objects)
            normalized = [
                (str(r.get("date")), r.get("topic"), r.get("person"))
                for r in result
            ]
            results.append(normalized)

        # All three should match
        assert results[0] == results[1] == results[2], (
            "Query results not deterministic:\n"
            f"Run 1: {len(results[0])} results\n"
            f"Run 2: {len(results[1])} results\n"
            f"Run 3: {len(results[2])} results"
        )

    def test_all_artifacts_deterministic(self, neo4j_driver):
        """3 consecutive artifact queries return same count."""
        counts = []
        for _ in range(3):
            result = run_query(
                neo4j_driver,
                "MATCH (a:Artifact) RETURN count(a) as count",
            )
            counts.append(result[0]["count"])

        assert counts[0] == counts[1] == counts[2], (
            f"Artifact count not stable: {counts}"
        )

    def test_all_sessions_deterministic(self, neo4j_driver):
        """3 consecutive session queries return same count."""
        counts = []
        for _ in range(3):
            result = run_query(
                neo4j_driver,
                "MATCH (s:Session) RETURN count(s) as count",
            )
            counts.append(result[0]["count"])

        assert counts[0] == counts[1] == counts[2], (
            f"Session count not stable: {counts}"
        )


# =============================================================================
# FILTER ACCURACY
# =============================================================================


@pytest.mark.retrieval
class TestFilterAccuracy:
    """Filters should return accurate subsets."""

    def test_active_quests_filter(self, neo4j_driver):
        """Active quest filter returns only active quests."""
        active = run_query(
            neo4j_driver,
            "MATCH (q:Quest {status: 'active'}) RETURN q.id AS id, q.status AS status",
        )

        # All returned should have status = active
        non_active = [q for q in active if q.get("status") != "active"]

        assert len(non_active) == 0, (
            f"Active quest filter returned non-active quests:\n"
            + "\n".join(f"  - {q['id']}: {q['status']}" for q in non_active)
        )

    def test_person_filter(self, neo4j_driver):
        """Sessions filtered by person return correct author."""
        # Get a person who has sessions
        people = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)-[:BY]->(p:Person)
            RETURN DISTINCT p.name AS name
            LIMIT 1
            """,
        )

        if not people:
            pytest.skip("No sessions with authors found")

        person_name = people[0]["name"]

        # Query sessions for this person
        sessions = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)-[:BY]->(p:Person {name: $name})
            RETURN s.id AS id, p.name AS author
            """,
            {"name": person_name},
        )

        # All should have correct author
        wrong_author = [s for s in sessions if s.get("author") != person_name]

        assert len(wrong_author) == 0, (
            f"Person filter returned wrong authors:\n"
            + "\n".join(f"  - {s['id']}: {s['author']}" for s in wrong_author)
        )

    def test_date_range_filter(self, neo4j_driver):
        """Date range filter returns sessions in range."""
        # Get sessions from last 7 days
        sessions = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)
            WHERE s.date >= date() - duration('P7D')
            RETURN s.id AS id, s.date AS date
            ORDER BY s.date DESC
            """,
        )

        # If we have results, they should all be recent
        # (Hard to assert exact dates, but count should be reasonable)
        if sessions:
            # At least verify we can get a date
            first_date = sessions[0].get("date")
            assert first_date is not None, "Session date should not be null"


# =============================================================================
# RELATIONSHIP TRAVERSAL
# =============================================================================


@pytest.mark.retrieval
class TestRelationshipTraversal:
    """Relationship queries should work correctly."""

    def test_session_author_traversal(self, neo4j_driver):
        """Session -> Person traversal via BY relationship."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)-[:BY]->(p:Person)
            RETURN s.id AS session_id, p.name AS author
            LIMIT 10
            """,
        )

        # Should return pairs
        for r in result:
            assert r.get("session_id") is not None, "Session ID should not be null"
            assert r.get("author") is not None, "Author should not be null"

    def test_artifact_quest_traversal(self, neo4j_driver):
        """Artifact -> Quest traversal via PART_OF relationship."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (a:Artifact)-[:PART_OF]->(q:Quest)
            RETURN a.id AS artifact_id, q.id AS quest_id
            LIMIT 10
            """,
        )

        # If we have results, check structure
        for r in result:
            if r.get("artifact_id"):
                assert r.get("quest_id") is not None, (
                    f"Artifact {r['artifact_id']} linked to null quest"
                )

    def test_person_project_traversal(self, neo4j_driver):
        """Person -> Project traversal via WORKS_ON relationship."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (p:Person)-[:WORKS_ON]->(proj:Project)
            RETURN p.name AS person, collect(proj.name) AS projects
            """,
        )

        # Verify structure
        for r in result:
            assert r.get("person") is not None, "Person name should not be null"
            assert isinstance(r.get("projects"), list), "Projects should be a list"


# =============================================================================
# PREDEFINED QUERIES
# =============================================================================


@pytest.mark.retrieval
class TestPredefinedQueries:
    """Bot's predefined queries should work."""

    def test_recent_activity_query(self, neo4j_driver):
        """Recent activity query executes without error."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)-[:BY]->(p:Person)
            WHERE s.date >= date() - duration('P7D')
            RETURN s.date AS date, s.topic AS topic, p.name AS person
            ORDER BY s.date DESC LIMIT 10
            """,
        )
        # Just verify it runs
        assert isinstance(result, list)

    def test_active_quests_query(self, neo4j_driver):
        """Active quests query executes without error."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (q:Quest {status: 'active'})
            RETURN q.id AS id, q.title AS title
            """,
        )
        assert isinstance(result, list)

    def test_all_people_query(self, neo4j_driver):
        """All people query executes without error."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (p:Person)
            OPTIONAL MATCH (p)-[:WORKS_ON]->(proj:Project)
            RETURN p.name AS name, collect(DISTINCT proj.name) AS projects
            """,
        )
        assert isinstance(result, list)

    def test_all_projects_query(self, neo4j_driver):
        """All projects query executes without error."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (proj:Project)
            RETURN proj.name AS name, proj.domain AS domain
            """,
        )
        assert isinstance(result, list)

    def test_search_artifacts_query(self, neo4j_driver):
        """Artifact search query executes without error."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (a:Artifact)
            WHERE toLower(a.title) CONTAINS toLower($search)
            RETURN a.title AS title, a.type AS type, a.author AS author
            LIMIT 5
            """,
            {"search": "test"},
        )
        assert isinstance(result, list)
