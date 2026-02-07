"""
Frontmatter parsing utilities for YAML-based markdown files.

Extracted from backfill_neo4j.py for reuse in tests.
"""

import re
import yaml
from pathlib import Path
from dataclasses import dataclass


@dataclass
class ParseResult:
    """Result of parsing a markdown file with frontmatter."""

    frontmatter: dict
    body: str
    valid: bool
    error: str | None = None


def parse_frontmatter(content: str) -> ParseResult:
    """Parse YAML frontmatter from markdown file.

    Args:
        content: Full file content

    Returns:
        ParseResult with frontmatter dict, body text, validity status
    """
    if not content.startswith("---"):
        return ParseResult(
            frontmatter={},
            body=content,
            valid=True,  # No frontmatter is valid
            error=None,
        )

    parts = content.split("---", 2)
    if len(parts) < 3:
        return ParseResult(
            frontmatter={},
            body=content,
            valid=False,
            error="Incomplete frontmatter block (missing closing ---)",
        )

    try:
        frontmatter = yaml.safe_load(parts[1])
        body = parts[2].strip()
        return ParseResult(
            frontmatter=frontmatter or {},
            body=body,
            valid=True,
            error=None,
        )
    except yaml.YAMLError as e:
        return ParseResult(
            frontmatter={},
            body=content,
            valid=False,
            error=f"YAML parse error: {e}",
        )


def extract_date_author_from_filename(filename: str) -> tuple[str, str, str]:
    """Extract date, author, and title from filename.

    Handles formats:
    - 2026-01-27-oz-famp-proposal.md (full date)
    - 27-oz-bot-deploy.md (day only, used in conversations/2026-01/)

    Returns:
        Tuple of (date, author, title)
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


def get_full_date_from_path(filepath: Path) -> str:
    """Extract full date from file path.

    Combines folder name (YYYY-MM) with filename day if present.

    Args:
        filepath: Path to markdown file

    Returns:
        Date string in YYYY-MM-DD format
    """
    parent = filepath.parent.name
    filename = filepath.name

    # Default fallback
    full_date = "2026-01-01"

    if parent.startswith("2") and "-" in parent:
        year_month = parent  # e.g., "2026-01"
        # Filename might start with day: "27-oz-something.md"
        day_match = re.match(r"^(\d{1,2})-", filename)
        if day_match:
            day = day_match.group(1).zfill(2)
            full_date = f"{year_month}-{day}"
        else:
            full_date = f"{year_month}-01"

    # Check if filename has full date
    date_str, _, _ = extract_date_author_from_filename(filename)
    if date_str and len(date_str.split("-")) == 3:
        full_date = date_str

    return full_date


# Required fields per content type
ARTIFACT_REQUIRED_FIELDS = ["title", "type", "author", "date"]
SESSION_REQUIRED_FIELDS = ["date", "author"]
QUEST_REQUIRED_FIELDS = ["title", "status"]


def validate_artifact_fields(frontmatter: dict, filename: str) -> list[str]:
    """Check if artifact has required fields.

    Args:
        frontmatter: Parsed frontmatter dict
        filename: Filename for fallback extraction

    Returns:
        List of missing field names
    """
    missing = []

    # Extract fallbacks from filename
    date_str, author_str, _ = extract_date_author_from_filename(filename)

    # Check each required field
    if not frontmatter.get("title"):
        missing.append("title")

    if not frontmatter.get("type"):
        missing.append("type")

    if not frontmatter.get("author") and not author_str:
        missing.append("author")

    if not frontmatter.get("date") and not date_str:
        missing.append("date")

    return missing


def validate_quest_fields(frontmatter: dict) -> list[str]:
    """Check if quest has required fields."""
    missing = []

    if not frontmatter.get("title"):
        missing.append("title")

    if not frontmatter.get("status"):
        missing.append("status")

    return missing


def validate_session_fields(frontmatter: dict, filename: str, folder: str) -> list[str]:
    """Check if session has required fields."""
    missing = []

    date_str, author_str, _ = extract_date_author_from_filename(filename)

    # Date can come from frontmatter, filename, or folder
    has_date = (
        frontmatter.get("date")
        or (date_str and len(date_str.split("-")) == 3)
        or (folder.startswith("2") and "-" in folder)
    )

    if not has_date:
        missing.append("date")

    if not frontmatter.get("author") and not author_str:
        missing.append("author")

    return missing
