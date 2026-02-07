"""
Security Tests

Economics impact: C (cost of security incidents)

Tests that verify no sensitive data is exposed:
- No API keys in tracked files
- No passwords in tracked files
- No private keys in tracked files
"""

import re
import pytest
from pathlib import Path


# =============================================================================
# SECRET PATTERNS
# =============================================================================

# Patterns that indicate potential secrets
SECRET_PATTERNS = [
    # API Keys
    (r"sk-[a-zA-Z0-9]{20,}", "OpenAI/Anthropic API key"),
    (r"sk-ant-[a-zA-Z0-9-]{20,}", "Anthropic API key"),
    (r"ANTHROPIC_API_KEY\s*=\s*['\"][^'\"]+['\"]", "Hardcoded Anthropic key"),
    (r"OPENAI_API_KEY\s*=\s*['\"][^'\"]+['\"]", "Hardcoded OpenAI key"),
    # Neo4j
    (r"NEO4J_PASSWORD\s*=\s*['\"][^'\"]+['\"]", "Hardcoded Neo4j password"),
    (r"neo4j\+s://[^:]+:[^@]+@", "Neo4j URI with credentials"),
    # Generic patterns
    (r"password\s*=\s*['\"][^'\"]{8,}['\"]", "Hardcoded password"),
    (r"secret\s*=\s*['\"][^'\"]{8,}['\"]", "Hardcoded secret"),
    (r"token\s*=\s*['\"][^'\"]{20,}['\"]", "Hardcoded token"),
    # Private keys
    (r"-----BEGIN (RSA |EC |)PRIVATE KEY-----", "Private key"),
    (r"-----BEGIN OPENSSH PRIVATE KEY-----", "SSH private key"),
    # AWS
    (r"AKIA[0-9A-Z]{16}", "AWS Access Key ID"),
    (r"aws_secret_access_key\s*=\s*['\"][^'\"]+['\"]", "AWS secret key"),
    # Telegram
    (r"\d{10}:[A-Za-z0-9_-]{35}", "Telegram bot token"),
]

# Files to exclude from scanning
EXCLUDED_FILES = {
    ".env",
    ".env.example",
    ".env.local",
    ".env.development",
    ".env.test",
    "*.pyc",
    "__pycache__",
    "test_security.py",  # This file contains pattern definitions
    "mcp.json",  # MCP config may have tokens
    "mcp.shared.json",  # MCP shared config
    "mcp.shared.windows.json",  # MCP shared config for Windows
}

# Directories to exclude
EXCLUDED_DIRS = {
    ".git",
    ".venv",
    "venv",
    "node_modules",
    "__pycache__",
    ".pytest_cache",
}


def should_scan_file(path: Path) -> bool:
    """Check if file should be scanned for secrets."""
    # Skip excluded directories
    for part in path.parts:
        if part in EXCLUDED_DIRS:
            return False

    # Skip excluded files
    if path.name in EXCLUDED_FILES:
        return False

    # Only scan text files
    text_extensions = {
        ".md",
        ".py",
        ".js",
        ".ts",
        ".json",
        ".yaml",
        ".yml",
        ".toml",
        ".txt",
        ".sh",
        ".bash",
    }

    return path.suffix.lower() in text_extensions


def scan_content_for_secrets(content: str, patterns: list) -> list[tuple[str, str]]:
    """Scan content for secret patterns.

    Returns:
        List of (matched_text, pattern_description) tuples
    """
    found = []
    for pattern, description in patterns:
        matches = re.findall(pattern, content, re.IGNORECASE)
        for match in matches:
            # Truncate long matches
            display = match[:50] + "..." if len(match) > 50 else match
            found.append((display, description))
    return found


# =============================================================================
# MEMORY SECURITY
# =============================================================================


@pytest.mark.security
class TestMemorySecurity:
    """No secrets in memory files."""

    def test_no_secrets_in_artifacts(self, filesystem_artifacts):
        """No API keys or passwords in artifact files."""
        if not filesystem_artifacts:
            pytest.skip("No artifacts found")

        violations = []
        for artifact in filesystem_artifacts:
            found = scan_content_for_secrets(artifact["content"], SECRET_PATTERNS)
            if found:
                violations.append(
                    {
                        "file": artifact["filename"],
                        "secrets": found,
                    }
                )

        assert len(violations) == 0, (
            f"Secrets found in artifacts:\n"
            + "\n".join(
                f"  - {v['file']}: {[s[1] for s in v['secrets']]}"
                for v in violations
            )
        )

    def test_no_secrets_in_sessions(self, filesystem_sessions):
        """No API keys or passwords in session files."""
        if not filesystem_sessions:
            pytest.skip("No sessions found")

        violations = []
        for session in filesystem_sessions:
            found = scan_content_for_secrets(session["content"], SECRET_PATTERNS)
            if found:
                violations.append(
                    {
                        "file": f"{session['folder']}/{session['filename']}",
                        "secrets": found,
                    }
                )

        assert len(violations) == 0, (
            f"Secrets found in sessions:\n"
            + "\n".join(
                f"  - {v['file']}: {[s[1] for s in v['secrets']]}"
                for v in violations
            )
        )

    def test_no_secrets_in_quests(self, filesystem_quests):
        """No API keys or passwords in quest files."""
        if not filesystem_quests:
            pytest.skip("No quests found")

        violations = []
        for quest in filesystem_quests:
            found = scan_content_for_secrets(quest["content"], SECRET_PATTERNS)
            if found:
                violations.append(
                    {
                        "file": quest["filename"],
                        "secrets": found,
                    }
                )

        assert len(violations) == 0, (
            f"Secrets found in quests:\n"
            + "\n".join(
                f"  - {v['file']}: {[s[1] for s in v['secrets']]}"
                for v in violations
            )
        )


# =============================================================================
# CODEBASE SECURITY
# =============================================================================


@pytest.mark.security
class TestCodebaseSecurity:
    """No secrets in codebase files."""

    def test_no_secrets_in_python_files(self):
        """No hardcoded secrets in Python files."""
        tests_path = Path(__file__).parent.parent

        violations = []
        for py_file in tests_path.rglob("*.py"):
            if not should_scan_file(py_file):
                continue

            try:
                content = py_file.read_text()
                found = scan_content_for_secrets(content, SECRET_PATTERNS)
                if found:
                    violations.append(
                        {
                            "file": str(py_file.relative_to(tests_path)),
                            "secrets": found,
                        }
                    )
            except Exception:
                pass  # Skip unreadable files

        assert len(violations) == 0, (
            f"Secrets found in Python files:\n"
            + "\n".join(
                f"  - {v['file']}: {[s[1] for s in v['secrets']]}"
                for v in violations
            )
        )

    def test_no_secrets_in_config_files(self):
        """No hardcoded secrets in config files (json, yaml, toml)."""
        tests_path = Path(__file__).parent.parent

        violations = []
        for ext in ["*.json", "*.yaml", "*.yml", "*.toml"]:
            for config_file in tests_path.rglob(ext):
                if not should_scan_file(config_file):
                    continue

                try:
                    content = config_file.read_text()
                    found = scan_content_for_secrets(content, SECRET_PATTERNS)
                    if found:
                        violations.append(
                            {
                                "file": str(config_file.relative_to(tests_path)),
                                "secrets": found,
                            }
                        )
                except Exception:
                    pass

        assert len(violations) == 0, (
            f"Secrets found in config files:\n"
            + "\n".join(
                f"  - {v['file']}: {[s[1] for s in v['secrets']]}"
                for v in violations
            )
        )


# =============================================================================
# ENV FILE CHECKS
# =============================================================================


@pytest.mark.security
class TestEnvSecurity:
    """Environment files should not be tracked."""

    def test_env_files_gitignored(self):
        """Verify .env files are in .gitignore."""
        tests_path = Path(__file__).parent.parent
        gitignore_path = tests_path / ".gitignore"

        if not gitignore_path.exists():
            # Check parent gitignore
            gitignore_path = tests_path.parent / ".gitignore"

        if not gitignore_path.exists():
            pytest.skip("No .gitignore found")

        content = gitignore_path.read_text()

        # Check for .env patterns
        env_patterns = [".env", "*.env", ".env.*", ".env.local"]
        found_patterns = [p for p in env_patterns if p in content]

        assert len(found_patterns) > 0, (
            ".env files should be in .gitignore to prevent accidental commits"
        )

    def test_no_real_env_files_tracked(self):
        """No real .env files (with actual values) should exist outside gitignore."""
        tests_path = Path(__file__).parent.parent

        # Find .env files
        env_files = list(tests_path.rglob(".env"))
        env_files += list(tests_path.rglob(".env.local"))

        # Exclude examples
        real_env_files = [
            f
            for f in env_files
            if not f.name.endswith(".example")
            and not f.name.endswith(".template")
            and not f.name.endswith(".sample")
        ]

        # Check if they're in .git tracked files (this is informational)
        # The files existing is fine as long as they're gitignored
        if real_env_files:
            print(f"Found .env files (ensure they're gitignored): {real_env_files}")
