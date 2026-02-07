"""
Data Quality Tests

Economics impact: p × V (answer usefulness depends on data quality)

Tests that verify data quality:
- Missing required fields in Neo4j
- Relationship completeness
- Name consistency (canonical names)
"""

import pytest
from utils.neo4j_helpers import run_query


# =============================================================================
# MISSING DATA
# =============================================================================


@pytest.mark.quality
class TestMissingData:
    """Check for missing or empty required fields in Neo4j."""

    def test_sessions_have_topic(self, neo4j_driver):
        """Sessions should have topic field set."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)
            WHERE s.topic IS NULL OR s.topic = ''
            RETURN count(s) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (s:Session) RETURN count(s) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No sessions in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        # Threshold: > 95% should have topic
        assert complete_rate >= 0.95, (
            f"Session topic rate: {complete_rate:.1%} (threshold: 95%)\n"
            f"Missing: {missing} / {total}"
        )

    def test_sessions_have_date(self, neo4j_driver):
        """Sessions should have date field set."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)
            WHERE s.date IS NULL
            RETURN count(s) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (s:Session) RETURN count(s) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No sessions in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        # Threshold: 100% should have date
        assert complete_rate == 1.0, (
            f"Session date rate: {complete_rate:.1%} (threshold: 100%)\n"
            f"Missing: {missing} / {total}"
        )

    def test_artifacts_have_title(self, neo4j_driver):
        """Artifacts should have title field set."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (a:Artifact)
            WHERE a.title IS NULL OR a.title = ''
            RETURN count(a) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (a:Artifact) RETURN count(a) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No artifacts in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        assert complete_rate == 1.0, (
            f"Artifact title rate: {complete_rate:.1%} (threshold: 100%)\n"
            f"Missing: {missing} / {total}"
        )

    def test_quests_have_title(self, neo4j_driver):
        """Quests should have title field set."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (q:Quest)
            WHERE q.title IS NULL OR q.title = ''
            RETURN count(q) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (q:Quest) RETURN count(q) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No quests in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        assert complete_rate == 1.0, (
            f"Quest title rate: {complete_rate:.1%} (threshold: 100%)\n"
            f"Missing: {missing} / {total}"
        )

    def test_quests_have_status(self, neo4j_driver):
        """Quests should have status field set."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (q:Quest)
            WHERE q.status IS NULL OR q.status = ''
            RETURN count(q) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (q:Quest) RETURN count(q) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No quests in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        assert complete_rate == 1.0, (
            f"Quest status rate: {complete_rate:.1%} (threshold: 100%)\n"
            f"Missing: {missing} / {total}"
        )


# =============================================================================
# RELATIONSHIP COMPLETENESS
# =============================================================================


@pytest.mark.quality
class TestRelationshipCompleteness:
    """Check relationship coverage."""

    def test_sessions_have_author(self, neo4j_driver):
        """Sessions should be linked to authors via BY relationship."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (s:Session)
            WHERE NOT (s)-[:BY]->(:Person)
            RETURN count(s) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (s:Session) RETURN count(s) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No sessions in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        # Threshold: > 90% should have author relationship
        assert complete_rate >= 0.90, (
            f"Session author relationship rate: {complete_rate:.1%} (threshold: 90%)\n"
            f"Missing: {missing} / {total}"
        )

    def test_artifacts_have_author(self, neo4j_driver):
        """Artifacts should be linked to authors via CONTRIBUTED_BY relationship."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (a:Artifact)
            WHERE NOT (a)-[:CONTRIBUTED_BY]->(:Person)
            RETURN count(a) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (a:Artifact) RETURN count(a) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No artifacts in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        # Threshold: > 90% should have author relationship
        assert complete_rate >= 0.90, (
            f"Artifact author relationship rate: {complete_rate:.1%} (threshold: 90%)\n"
            f"Missing: {missing} / {total}"
        )

    def test_quests_have_starter(self, neo4j_driver):
        """Quests should be linked to starters via STARTED_BY relationship."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (q:Quest)
            WHERE NOT (q)-[:STARTED_BY]->(:Person)
            RETURN count(q) as count
            """,
        )
        total = run_query(
            neo4j_driver,
            "MATCH (q:Quest) RETURN count(q) as count",
        )[0]["count"]

        if total == 0:
            pytest.skip("No quests in Neo4j")

        missing = result[0]["count"]
        complete_rate = (total - missing) / total

        # Threshold: > 80% (some quests might be community-started)
        assert complete_rate >= 0.80, (
            f"Quest starter relationship rate: {complete_rate:.1%} (threshold: 80%)\n"
            f"Missing: {missing} / {total}"
        )


# =============================================================================
# NAME CONSISTENCY
# =============================================================================


@pytest.mark.quality
class TestNameConsistency:
    """Check for name inconsistencies (duplicates, variants)."""

    def test_person_names_lowercase(self, neo4j_driver):
        """Person names should be lowercase for consistency."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (p:Person)
            WHERE p.name <> toLower(p.name)
            RETURN p.name AS name
            """,
        )

        non_lowercase = [r["name"] for r in result]

        assert len(non_lowercase) == 0, (
            f"Person names should be lowercase:\n"
            + "\n".join(f"  - {n}" for n in non_lowercase)
        )

    def test_project_names_lowercase(self, neo4j_driver):
        """Project names should be lowercase for consistency."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (proj:Project)
            WHERE proj.name <> toLower(proj.name)
            RETURN proj.name AS name
            """,
        )

        non_lowercase = [r["name"] for r in result]

        # Allow some mixed case for display names
        assert len(non_lowercase) <= 5, (
            f"Too many non-lowercase project names:\n"
            + "\n".join(f"  - {n}" for n in non_lowercase)
        )

    def test_no_duplicate_people(self, neo4j_driver):
        """No duplicate Person nodes (same name, different case)."""
        result = run_query(
            neo4j_driver,
            """
            MATCH (p:Person)
            WITH toLower(p.name) AS lower_name, collect(p.name) AS names
            WHERE size(names) > 1
            RETURN lower_name, names
            """,
        )

        duplicates = [(r["lower_name"], r["names"]) for r in result]

        assert len(duplicates) == 0, (
            f"Duplicate person nodes found:\n"
            + "\n".join(f"  - {n}: {names}" for n, names in duplicates)
        )

    def test_valid_quest_status(self, neo4j_driver):
        """Quest status should be one of: active, completed, paused, abandoned."""
        valid_statuses = {"active", "completed", "paused", "abandoned"}

        result = run_query(
            neo4j_driver,
            """
            MATCH (q:Quest)
            WHERE q.status IS NOT NULL
            RETURN DISTINCT q.status AS status
            """,
        )

        statuses = {r["status"] for r in result}
        invalid = statuses - valid_statuses

        assert len(invalid) == 0, (
            f"Invalid quest statuses: {invalid}\n"
            f"Valid: {valid_statuses}"
        )

    def test_valid_artifact_types(self, neo4j_driver):
        """Artifact types should be from known set."""
        known_types = {
            "thought",
            "decision",
            "finding",
            "pattern",
            "source",
            "draft",
            "blog",
            "proposal",
            "analysis",
            "handoff",
            "spec",
            "doc",
        }

        result = run_query(
            neo4j_driver,
            """
            MATCH (a:Artifact)
            WHERE a.type IS NOT NULL
            RETURN DISTINCT a.type AS type
            """,
        )

        types = {r["type"] for r in result}
        unknown = types - known_types

        # Allow unknown types but flag them
        if unknown:
            # This is a warning, not a failure (types can evolve)
            print(f"Warning: Unknown artifact types found: {unknown}")

        # At least verify types are strings
        for t in types:
            assert isinstance(t, str), f"Artifact type should be string: {t}"
