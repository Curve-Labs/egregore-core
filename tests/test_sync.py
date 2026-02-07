"""
Sync Accuracy Tests

Economics impact: p (probability items are findable in Neo4j)

Tests that verify filesystem and Neo4j are in sync:
- All filesystem artifacts exist in Neo4j
- All filesystem sessions exist in Neo4j
- All filesystem quests exist in Neo4j
- filePath consistency
"""

import pytest
from utils.neo4j_helpers import get_all_artifacts, get_all_sessions, get_all_quests


# =============================================================================
# ARTIFACT SYNC
# =============================================================================


@pytest.mark.sync
class TestArtifactSync:
    """Filesystem artifacts should be synced to Neo4j."""

    def test_artifacts_synced(self, filesystem_artifacts, neo4j_driver):
        """All filesystem artifacts exist in Neo4j."""
        if not filesystem_artifacts:
            pytest.skip("No artifacts found")

        neo4j_artifacts = get_all_artifacts(neo4j_driver)

        # Build lookup by filePath and id
        neo4j_filepaths = {
            a["filePath"] for a in neo4j_artifacts if a.get("filePath")
        }
        neo4j_ids = {a["id"] for a in neo4j_artifacts if a.get("id")}

        missing = []
        for artifact in filesystem_artifacts:
            # Check by expected filePath or ID (filename stem)
            expected_path = f"memory/artifacts/{artifact['filename']}"
            file_id = artifact["filename"].replace(".md", "")

            if expected_path not in neo4j_filepaths and file_id not in neo4j_ids:
                missing.append(artifact["filename"])

        # Threshold: > 99% synced
        sync_rate = (len(filesystem_artifacts) - len(missing)) / len(
            filesystem_artifacts
        )

        assert sync_rate >= 0.99, (
            f"Artifact sync rate: {sync_rate:.1%} (threshold: 99%)\n"
            f"Missing in Neo4j ({len(missing)}):\n"
            + "\n".join(f"  - {f}" for f in missing[:10])
        )

    def test_artifact_filepath_set(self, neo4j_driver):
        """All Neo4j artifacts have filePath set."""
        neo4j_artifacts = get_all_artifacts(neo4j_driver)
        if not neo4j_artifacts:
            pytest.skip("No artifacts in Neo4j")

        missing_filepath = [
            a["id"] or a["title"]
            for a in neo4j_artifacts
            if not a.get("filePath")
        ]

        complete_rate = (len(neo4j_artifacts) - len(missing_filepath)) / len(
            neo4j_artifacts
        )

        assert complete_rate >= 0.99, (
            f"Artifact filePath rate: {complete_rate:.1%} (threshold: 99%)\n"
            f"Missing filePath ({len(missing_filepath)}):\n"
            + "\n".join(f"  - {f}" for f in missing_filepath[:10])
        )


# =============================================================================
# SESSION SYNC
# =============================================================================


@pytest.mark.sync
class TestSessionSync:
    """Filesystem sessions should be synced to Neo4j."""

    def test_sessions_synced(self, filesystem_sessions, neo4j_driver):
        """All filesystem sessions exist in Neo4j."""
        if not filesystem_sessions:
            pytest.skip("No sessions found")

        neo4j_sessions = get_all_sessions(neo4j_driver)

        # Build lookup by id (filename stem) and filePath
        neo4j_ids = {s["id"] for s in neo4j_sessions if s.get("id")}
        neo4j_filepaths = {
            s["filePath"] for s in neo4j_sessions if s.get("filePath")
        }

        missing = []
        for session in filesystem_sessions:
            session_id = session["filename"].replace(".md", "")
            expected_path = f"memory/conversations/{session['folder']}/{session['filename']}"

            if session_id not in neo4j_ids and expected_path not in neo4j_filepaths:
                missing.append(f"{session['folder']}/{session['filename']}")

        sync_rate = (len(filesystem_sessions) - len(missing)) / len(
            filesystem_sessions
        )

        assert sync_rate >= 0.99, (
            f"Session sync rate: {sync_rate:.1%} (threshold: 99%)\n"
            f"Missing in Neo4j ({len(missing)}):\n"
            + "\n".join(f"  - {f}" for f in missing[:10])
        )

    def test_session_filepath_set(self, neo4j_driver):
        """All Neo4j sessions have filePath set."""
        neo4j_sessions = get_all_sessions(neo4j_driver)
        if not neo4j_sessions:
            pytest.skip("No sessions in Neo4j")

        missing_filepath = [
            s["id"] or s["topic"] or "unknown"
            for s in neo4j_sessions
            if not s.get("filePath")
        ]

        complete_rate = (len(neo4j_sessions) - len(missing_filepath)) / len(
            neo4j_sessions
        )

        assert complete_rate >= 0.95, (
            f"Session filePath rate: {complete_rate:.1%} (threshold: 95%)\n"
            f"Missing filePath ({len(missing_filepath)}):\n"
            + "\n".join(f"  - {f}" for f in missing_filepath[:10])
        )


# =============================================================================
# QUEST SYNC
# =============================================================================


@pytest.mark.sync
class TestQuestSync:
    """Filesystem quests should be synced to Neo4j."""

    def test_quests_synced(self, filesystem_quests, neo4j_driver):
        """All filesystem quests exist in Neo4j."""
        if not filesystem_quests:
            pytest.skip("No quests found")

        neo4j_quests = get_all_quests(neo4j_driver)
        neo4j_ids = {q["id"] for q in neo4j_quests if q.get("id")}

        missing = []
        for quest in filesystem_quests:
            if quest["id"] not in neo4j_ids:
                missing.append(quest["id"])

        sync_rate = (len(filesystem_quests) - len(missing)) / len(filesystem_quests)

        assert sync_rate >= 0.99, (
            f"Quest sync rate: {sync_rate:.1%} (threshold: 99%)\n"
            f"Missing in Neo4j ({len(missing)}):\n"
            + "\n".join(f"  - {f}" for f in missing[:10])
        )


# =============================================================================
# BIDIRECTIONAL SYNC
# =============================================================================


@pytest.mark.sync
class TestBidirectionalSync:
    """Neo4j shouldn't have orphaned nodes without filesystem counterparts."""

    def test_no_orphan_artifacts(self, filesystem_artifacts, neo4j_driver):
        """Neo4j artifacts should have corresponding filesystem files."""
        neo4j_artifacts = get_all_artifacts(neo4j_driver)
        if not neo4j_artifacts:
            pytest.skip("No artifacts in Neo4j")

        # Build filesystem lookup
        fs_stems = {a["filename"].replace(".md", "") for a in filesystem_artifacts}
        fs_paths = {
            f"memory/artifacts/{a['filename']}" for a in filesystem_artifacts
        }

        orphans = []
        for artifact in neo4j_artifacts:
            artifact_id = artifact.get("id", "")
            filepath = artifact.get("filePath", "")

            # Check if exists in filesystem by id or path
            if artifact_id not in fs_stems and filepath not in fs_paths:
                orphans.append(artifact_id or artifact.get("title", "unknown"))

        # Allow some orphans (manual entries, etc.) but flag if too many
        orphan_rate = len(orphans) / len(neo4j_artifacts) if neo4j_artifacts else 0

        assert orphan_rate <= 0.1, (
            f"Orphan artifact rate: {orphan_rate:.1%} (threshold: 10%)\n"
            f"Orphans ({len(orphans)}):\n"
            + "\n".join(f"  - {f}" for f in orphans[:10])
        )
