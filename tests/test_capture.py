"""
Capture Reliability Tests

Economics impact: p (probability items enter system correctly)

Tests that verify content is captured with valid structure:
- Frontmatter validity (parseable YAML)
- Required fields present
- Naming conventions followed
"""

import pytest
from utils.frontmatter import (
    parse_frontmatter,
    validate_artifact_fields,
    validate_quest_fields,
    validate_session_fields,
)


# =============================================================================
# FRONTMATTER VALIDITY
# =============================================================================


@pytest.mark.capture
class TestFrontmatterValidity:
    """All files should have parseable YAML frontmatter."""

    def test_artifact_frontmatter_valid(self, filesystem_artifacts):
        """All artifacts have parseable YAML frontmatter."""
        if not filesystem_artifacts:
            pytest.skip("No artifacts found")

        invalid = []
        for artifact in filesystem_artifacts:
            result = parse_frontmatter(artifact["content"])
            if not result.valid:
                invalid.append(
                    {"file": artifact["filename"], "error": result.error}
                )

        # Threshold: 100% must be valid
        valid_rate = (len(filesystem_artifacts) - len(invalid)) / len(
            filesystem_artifacts
        )

        assert valid_rate == 1.0, (
            f"Frontmatter parse rate: {valid_rate:.1%} (threshold: 100%)\n"
            f"Invalid files:\n"
            + "\n".join(f"  - {i['file']}: {i['error']}" for i in invalid[:5])
        )

    def test_session_frontmatter_valid(self, filesystem_sessions):
        """All sessions have parseable YAML frontmatter."""
        if not filesystem_sessions:
            pytest.skip("No sessions found")

        invalid = []
        for session in filesystem_sessions:
            result = parse_frontmatter(session["content"])
            if not result.valid:
                invalid.append({"file": session["filename"], "error": result.error})

        valid_rate = (len(filesystem_sessions) - len(invalid)) / len(
            filesystem_sessions
        )

        assert valid_rate == 1.0, (
            f"Frontmatter parse rate: {valid_rate:.1%} (threshold: 100%)\n"
            f"Invalid files:\n"
            + "\n".join(f"  - {i['file']}: {i['error']}" for i in invalid[:5])
        )

    def test_quest_frontmatter_valid(self, filesystem_quests):
        """All quests have parseable YAML frontmatter."""
        if not filesystem_quests:
            pytest.skip("No quests found")

        invalid = []
        for quest in filesystem_quests:
            result = parse_frontmatter(quest["content"])
            if not result.valid:
                invalid.append({"file": quest["filename"], "error": result.error})

        valid_rate = (len(filesystem_quests) - len(invalid)) / len(filesystem_quests)

        assert valid_rate == 1.0, (
            f"Frontmatter parse rate: {valid_rate:.1%} (threshold: 100%)\n"
            f"Invalid files:\n"
            + "\n".join(f"  - {i['file']}: {i['error']}" for i in invalid[:5])
        )


# =============================================================================
# REQUIRED FIELDS
# =============================================================================


@pytest.mark.capture
class TestRequiredFields:
    """Content should have required metadata fields."""

    def test_artifact_required_fields(self, filesystem_artifacts):
        """Artifacts have title, type, author, date (or filename fallback)."""
        if not filesystem_artifacts:
            pytest.skip("No artifacts found")

        incomplete = []
        for artifact in filesystem_artifacts:
            result = parse_frontmatter(artifact["content"])
            if not result.valid:
                continue  # Skip unparseable files

            missing = validate_artifact_fields(result.frontmatter, artifact["filename"])
            if missing:
                incomplete.append(
                    {"file": artifact["filename"], "missing": missing}
                )

        # Threshold: 100% complete
        complete_rate = (len(filesystem_artifacts) - len(incomplete)) / len(
            filesystem_artifacts
        )

        assert complete_rate == 1.0, (
            f"Artifact completeness: {complete_rate:.1%} (threshold: 100%)\n"
            f"Incomplete files:\n"
            + "\n".join(
                f"  - {i['file']}: missing {i['missing']}" for i in incomplete[:5]
            )
        )

    def test_quest_required_fields(self, filesystem_quests):
        """Quests have title and status."""
        if not filesystem_quests:
            pytest.skip("No quests found")

        incomplete = []
        for quest in filesystem_quests:
            result = parse_frontmatter(quest["content"])
            if not result.valid:
                continue

            missing = validate_quest_fields(result.frontmatter)
            if missing:
                incomplete.append({"file": quest["filename"], "missing": missing})

        complete_rate = (len(filesystem_quests) - len(incomplete)) / len(
            filesystem_quests
        )

        assert complete_rate == 1.0, (
            f"Quest completeness: {complete_rate:.1%} (threshold: 100%)\n"
            f"Incomplete files:\n"
            + "\n".join(
                f"  - {i['file']}: missing {i['missing']}" for i in incomplete[:5]
            )
        )

    def test_session_required_fields(self, filesystem_sessions):
        """Sessions have date and author (or filename/folder fallback)."""
        if not filesystem_sessions:
            pytest.skip("No sessions found")

        incomplete = []
        for session in filesystem_sessions:
            result = parse_frontmatter(session["content"])
            if not result.valid:
                continue

            missing = validate_session_fields(
                result.frontmatter, session["filename"], session["folder"]
            )
            if missing:
                incomplete.append({"file": session["filename"], "missing": missing})

        complete_rate = (len(filesystem_sessions) - len(incomplete)) / len(
            filesystem_sessions
        )

        assert complete_rate == 1.0, (
            f"Session completeness: {complete_rate:.1%} (threshold: 100%)\n"
            f"Incomplete files:\n"
            + "\n".join(
                f"  - {i['file']}: missing {i['missing']}" for i in incomplete[:5]
            )
        )


# =============================================================================
# NAMING CONVENTIONS
# =============================================================================


@pytest.mark.capture
class TestNamingConventions:
    """Files should follow naming conventions for extractable metadata."""

    def test_artifact_naming_pattern(self, filesystem_artifacts):
        """Artifacts follow YYYY-MM-DD-author-title.md pattern."""
        if not filesystem_artifacts:
            pytest.skip("No artifacts found")

        import re

        pattern = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z]+-[\w-]+\.md$")

        non_conforming = []
        for artifact in filesystem_artifacts:
            if not pattern.match(artifact["filename"]):
                non_conforming.append(artifact["filename"])

        # Threshold: 95% should follow pattern
        conforming_rate = (len(filesystem_artifacts) - len(non_conforming)) / len(
            filesystem_artifacts
        )

        assert conforming_rate >= 0.95, (
            f"Naming convention rate: {conforming_rate:.1%} (threshold: 95%)\n"
            f"Non-conforming:\n" + "\n".join(f"  - {f}" for f in non_conforming[:5])
        )

    def test_session_naming_pattern(self, filesystem_sessions):
        """Sessions follow DD-author-topic.md or YYYY-MM-DD-author-topic.md pattern."""
        if not filesystem_sessions:
            pytest.skip("No sessions found")

        import re

        # Day-only: 27-oz-topic.md or full date: 2026-01-27-oz-topic.md
        pattern = re.compile(r"^(\d{1,2}|\d{4}-\d{2}-\d{2})-[a-z]+-[\w-]+\.md$")

        non_conforming = []
        for session in filesystem_sessions:
            if not pattern.match(session["filename"]):
                non_conforming.append(session["filename"])

        conforming_rate = (len(filesystem_sessions) - len(non_conforming)) / len(
            filesystem_sessions
        )

        assert conforming_rate >= 0.95, (
            f"Naming convention rate: {conforming_rate:.1%} (threshold: 95%)\n"
            f"Non-conforming:\n" + "\n".join(f"  - {f}" for f in non_conforming[:5])
        )
