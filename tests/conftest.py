"""
Pytest configuration and fixtures for Egregore tests.

Provides fixtures for:
- Neo4j driver (session-scoped)
- Memory path
- Filesystem artifacts, sessions, quests
"""

import os
import pytest
from pathlib import Path
from dotenv import load_dotenv

from utils.neo4j_helpers import create_driver

# Load environment from telegram-bot
_env_path = Path(__file__).parent.parent / "telegram-bot" / ".env"
if _env_path.exists():
    load_dotenv(_env_path)


# =============================================================================
# PATH FIXTURES
# =============================================================================


@pytest.fixture(scope="session")
def memory_path() -> Path:
    """Path to the memory directory (via symlink)."""
    path = Path(__file__).parent.parent / "memory"
    if not path.exists():
        pytest.skip("Memory symlink not configured")
    return path


@pytest.fixture(scope="session")
def artifacts_path(memory_path: Path) -> Path:
    """Path to artifacts directory."""
    return memory_path / "artifacts"


@pytest.fixture(scope="session")
def conversations_path(memory_path: Path) -> Path:
    """Path to conversations directory."""
    return memory_path / "conversations"


@pytest.fixture(scope="session")
def quests_path(memory_path: Path) -> Path:
    """Path to quests directory."""
    return memory_path / "quests"


# =============================================================================
# FILESYSTEM FIXTURES
# =============================================================================


@pytest.fixture(scope="session")
def filesystem_artifacts(artifacts_path: Path) -> list[dict]:
    """All artifact files from filesystem."""
    if not artifacts_path.exists():
        return []

    artifacts = []
    for f in artifacts_path.glob("*.md"):
        if f.name.startswith("_") or f.name == "README.md":
            continue
        artifacts.append(
            {
                "filename": f.name,
                "path": f,
                "size": f.stat().st_size,
                "content": f.read_text(),
            }
        )
    return artifacts


@pytest.fixture(scope="session")
def filesystem_sessions(conversations_path: Path) -> list[dict]:
    """All session/conversation files from filesystem."""
    if not conversations_path.exists():
        return []

    sessions = []
    for f in conversations_path.rglob("*.md"):
        if f.name in ["index.md", "_template.md"]:
            continue
        sessions.append(
            {
                "filename": f.name,
                "path": f,
                "folder": f.parent.name,
                "size": f.stat().st_size,
                "content": f.read_text(),
            }
        )
    return sessions


@pytest.fixture(scope="session")
def filesystem_quests(quests_path: Path) -> list[dict]:
    """All quest files from filesystem."""
    if not quests_path.exists():
        return []

    quests = []
    for f in quests_path.glob("*.md"):
        if f.name in ["index.md", "_template.md"]:
            continue
        quests.append(
            {
                "filename": f.name,
                "id": f.stem,
                "path": f,
                "content": f.read_text(),
            }
        )
    return quests


# =============================================================================
# NEO4J FIXTURES
# =============================================================================


@pytest.fixture(scope="session")
def neo4j_driver():
    """Neo4j driver (session-scoped for efficiency)."""
    uri = os.environ.get("NEO4J_URI")
    if not uri:
        pytest.skip("NEO4J_URI not configured")

    driver = create_driver()

    # Verify connection
    try:
        with driver.session() as session:
            session.run("RETURN 1")
    except Exception as e:
        pytest.skip(f"Neo4j connection failed: {e}")

    yield driver

    driver.close()


# =============================================================================
# METRICS COLLECTION
# =============================================================================


class TestMetrics:
    """Collector for test metrics (for unit economics dashboard)."""

    def __init__(self):
        self.results = {}

    def record(self, category: str, metric: str, value: float, threshold: float):
        """Record a metric result."""
        if category not in self.results:
            self.results[category] = {}
        self.results[category][metric] = {
            "value": value,
            "threshold": threshold,
            "passed": value >= threshold,
        }

    def summary(self) -> dict:
        """Get summary of all metrics."""
        return self.results


@pytest.fixture(scope="session")
def metrics() -> TestMetrics:
    """Session-scoped metrics collector."""
    return TestMetrics()


# =============================================================================
# REPORT HOOKS
# =============================================================================


def pytest_html_report_title(report):
    """Set custom report title."""
    report.title = "Egregore Reliability Report"


def pytest_configure(config):
    """Add custom markers."""
    config.addinivalue_line("markers", "capture: Capture reliability tests")
    config.addinivalue_line("markers", "sync: Sync accuracy tests")
    config.addinivalue_line("markers", "retrieval: Retrieval stability tests")
    config.addinivalue_line("markers", "quality: Data quality tests")
    config.addinivalue_line("markers", "security: Security tests")
