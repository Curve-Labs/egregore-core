"""
Egregore Analytics - System-wide Unit Economics Tracking

Tracks costs (tokens, latency, infrastructure) across all Egregore components.
Uses the existing events.db with component-specific event types.

Components tracked:
    - bot: Telegram bot queries (egregore_bot events)
    - sync: Neo4j sync operations (egregore_sync events) [future]
    - mcp: MCP server calls (egregore_mcp events) [future]

Usage:
    # Log an event from any component
    from analytics import log_event
    log_event(
        component="bot",
        operation="query",
        tokens_in=2000,
        tokens_out=165,
        ...
    )

    # Legacy bot-specific function (wraps log_event)
    from analytics import log_query_event
    log_query_event(query_type="person_sessions", ...)

    # Generate cost report
    python -m analytics           # Last 7 days
    python -m analytics --days 30 # Last 30 days
"""

import sqlite3
import json
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional
import argparse

# Database path - same as existing events.db
DB_PATH = Path(__file__).parent.parent / "data" / "events.db"

# Anthropic pricing (as of 2026)
# https://www.anthropic.com/pricing
MODEL_PRICING = {
    "claude-haiku-4-5-20251001": {
        "input": 0.80,   # $0.80 per 1M input tokens
        "output": 4.00,  # $4.00 per 1M output tokens
    },
    "claude-sonnet-4-20250514": {
        "input": 3.00,
        "output": 15.00,
    },
    "claude-opus-4-5-20251101": {
        "input": 15.00,
        "output": 75.00,
    },
    # Default fallback (Haiku pricing)
    "default": {
        "input": 0.80,
        "output": 4.00,
    },
}

# Infrastructure costs (monthly estimates)
# Update these based on your actual billing
INFRA_COSTS = {
    "railway": 5.00,       # Railway Hobby plan ~$5/month
    "neo4j_aura": 0.00,    # Free tier (or $65/month for dedicated)
    "telegram": 0.00,      # Free
    "github": 0.00,        # Free tier
    "mcp_servers": 0.00,   # Self-hosted or free tiers
}
MONTHLY_INFRA_COST = sum(INFRA_COSTS.values())


def calculate_cost(tokens_in: int, tokens_out: int, model: str = "default") -> float:
    """Calculate USD cost from token counts and model."""
    pricing = MODEL_PRICING.get(model, MODEL_PRICING["default"])
    input_cost = (tokens_in / 1_000_000) * pricing["input"]
    output_cost = (tokens_out / 1_000_000) * pricing["output"]
    return input_cost + output_cost


def log_event(
    component: str,
    operation: str,
    tokens_in: int = 0,
    tokens_out: int = 0,
    latency_ms: float = 0,
    success: bool = True,
    model: str = "default",
    user_id: Optional[int] = None,
    user_name: Optional[str] = None,
    metadata: Optional[dict] = None,
) -> None:
    """
    Log an Egregore system event for cost tracking.

    Args:
        component: Which component (bot, sync, mcp, etc.)
        operation: What operation was performed
        tokens_in: Input tokens consumed
        tokens_out: Output tokens consumed
        latency_ms: Total latency in milliseconds
        success: Whether the operation succeeded
        model: LLM model used (for accurate pricing)
        user_id: User identifier if applicable
        user_name: User name if applicable
        metadata: Additional component-specific data
    """
    cost_usd = calculate_cost(tokens_in, tokens_out, model)

    event_data = {
        "component": component,
        "operation": operation,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "cost_usd": round(cost_usd, 6),
        "latency_ms": round(latency_ms, 1),
        "success": success,
        "model": model,
    }

    if user_id:
        event_data["user_id"] = user_id
    if user_name:
        event_data["user_name"] = user_name
    if metadata:
        event_data["metadata"] = metadata

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """INSERT INTO events (event_id, event_type, timestamp, tenant_id, data)
               VALUES (?, ?, ?, ?, ?)""",
            (
                str(uuid.uuid4()),
                f"egregore_{component}",
                datetime.utcnow().isoformat(),
                "default",
                json.dumps(event_data)
            )
        )

        conn.commit()
        conn.close()
    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"Failed to log event: {e}")


def log_query_event(
    query_type: str,
    tokens_in: int,
    tokens_out: int,
    latency_ms: float,
    results_count: int,
    success: bool,
    user_id: Optional[int] = None,
    user_name: Optional[str] = None,
    question: Optional[str] = None,
    decision_tokens_in: int = 0,
    decision_tokens_out: int = 0,
    decision_latency_ms: float = 0,
    format_tokens_in: int = 0,
    format_tokens_out: int = 0,
    format_latency_ms: float = 0,
    neo4j_latency_ms: float = 0,
) -> None:
    """
    Log a bot query event. Wrapper around log_event for backward compatibility.
    """
    metadata = {
        "query_type": query_type,
        "results_count": results_count,
        "decision_tokens_in": decision_tokens_in,
        "decision_tokens_out": decision_tokens_out,
        "decision_latency_ms": round(decision_latency_ms, 1),
        "format_tokens_in": format_tokens_in,
        "format_tokens_out": format_tokens_out,
        "format_latency_ms": round(format_latency_ms, 1),
        "neo4j_latency_ms": round(neo4j_latency_ms, 1),
    }

    if question:
        metadata["question"] = question[:500] if len(question) > 500 else question

    log_event(
        component="bot",
        operation=query_type,
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        latency_ms=latency_ms,
        success=success,
        model="claude-haiku-4-5-20251001",
        user_id=user_id,
        user_name=user_name,
        metadata=metadata,
    )


def get_events(days: int = 7, component: Optional[str] = None) -> list:
    """Retrieve Egregore events from the last N days."""
    if not DB_PATH.exists():
        return []

    cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    if component:
        cursor.execute(
            """SELECT event_type, data FROM events
               WHERE event_type = ? AND timestamp >= ?
               ORDER BY timestamp DESC""",
            (f"egregore_{component}", cutoff)
        )
    else:
        # Get all egregore events (and legacy bot_query for backward compat)
        cursor.execute(
            """SELECT event_type, data FROM events
               WHERE (event_type LIKE 'egregore_%' OR event_type = 'bot_query')
               AND timestamp >= ?
               ORDER BY timestamp DESC""",
            (cutoff,)
        )

    rows = cursor.fetchall()
    conn.close()

    events = []
    for event_type, data in rows:
        event = json.loads(data)
        # Normalize legacy bot_query events
        if event_type == "bot_query":
            event["component"] = "bot"
            event["operation"] = event.get("query_type", "unknown")
        events.append(event)

    return events


def report(days: int = 7) -> None:
    """Print cost summary for last N days."""
    events = get_events(days)

    if not events:
        print(f"No Egregore events in the last {days} days.")
        print(f"\nInfra costs (monthly): ${MONTHLY_INFRA_COST:.2f}")
        return

    total_events = len(events)
    total_api_cost = sum(e.get("cost_usd", 0) for e in events)
    total_tokens_in = sum(e.get("tokens_in", 0) for e in events)
    total_tokens_out = sum(e.get("tokens_out", 0) for e in events)

    latencies = [e.get("latency_ms", 0) for e in events if e.get("latency_ms", 0) > 0]
    avg_latency = sum(latencies) / len(latencies) if latencies else 0

    success_count = sum(1 for e in events if e.get("success", False))
    success_rate = (success_count / total_events) * 100 if total_events > 0 else 0

    # Calculate prorated infrastructure cost for the period
    infra_cost_period = (MONTHLY_INFRA_COST / 30) * days
    total_cost = total_api_cost + infra_cost_period

    # Project monthly costs based on current usage
    events_per_day = total_events / days
    projected_monthly_api = (total_api_cost / days) * 30
    projected_monthly_total = projected_monthly_api + MONTHLY_INFRA_COST

    print(f"""
EGREGORE UNIT ECONOMICS — Last {days} Days
{'=' * 50}

Events: {total_events} ({events_per_day:.1f}/day)
Success Rate: {success_rate:.1f}%

COSTS (This Period)
  API (tokens):     ${total_api_cost:.4f}
  Infra (prorated): ${infra_cost_period:.2f}
  Total:            ${total_cost:.2f}
  Per Event:        ${total_cost/total_events:.4f}

PROJECTED MONTHLY
  API:    ${projected_monthly_api:.2f}
  Infra:  ${MONTHLY_INFRA_COST:.2f}
  Total:  ${projected_monthly_total:.2f}

Avg Latency: {avg_latency:.0f}ms

Tokens:
  Input:  {total_tokens_in:,}
  Output: {total_tokens_out:,}
""")

    # By component
    components = {}
    for e in events:
        comp = e.get("component", "unknown")
        if comp not in components:
            components[comp] = {"count": 0, "cost": 0, "tokens_in": 0, "tokens_out": 0}
        components[comp]["count"] += 1
        components[comp]["cost"] += e.get("cost_usd", 0)
        components[comp]["tokens_in"] += e.get("tokens_in", 0)
        components[comp]["tokens_out"] += e.get("tokens_out", 0)

    print("By Component:")
    for comp, stats in sorted(components.items(), key=lambda x: x[1]["cost"], reverse=True):
        print(f"  {comp:15} {stats['count']:4} events  ${stats['cost']:.4f}  ({stats['tokens_in']:,} in / {stats['tokens_out']:,} out)")

    # By operation (for bot component)
    bot_events = [e for e in events if e.get("component") == "bot"]
    if bot_events:
        operations = {}
        for e in bot_events:
            op = e.get("operation", e.get("query_type", "unknown"))
            if op not in operations:
                operations[op] = {"count": 0, "cost": 0, "success": 0}
            operations[op]["count"] += 1
            operations[op]["cost"] += e.get("cost_usd", 0)
            if e.get("success", False):
                operations[op]["success"] += 1

        print("\nBot Operations:")
        for op, stats in sorted(operations.items(), key=lambda x: x[1]["count"], reverse=True):
            rate = (stats["success"] / stats["count"]) * 100 if stats["count"] > 0 else 0
            print(f"  {op:25} {stats['count']:4} calls  {rate:5.1f}% success  ${stats['cost']:.4f}")

    # By user
    users = {}
    for e in events:
        user = e.get("user_name", "system")
        if user not in users:
            users[user] = {"count": 0, "cost": 0}
        users[user]["count"] += 1
        users[user]["cost"] += e.get("cost_usd", 0)

    if users and len(users) > 1:  # Only show if multiple users
        print("\nBy User:")
        for user, stats in sorted(users.items(), key=lambda x: x[1]["count"], reverse=True):
            print(f"  {user:15} {stats['count']:4} events  ${stats['cost']:.4f}")

    # Infrastructure breakdown
    print("\nINFRA BREAKDOWN (monthly)")
    for service, cost in INFRA_COSTS.items():
        if cost > 0:
            print(f"  {service:15} ${cost:.2f}")
    print(f"  {'─' * 20}")
    print(f"  {'Total':15} ${MONTHLY_INFRA_COST:.2f}")
    print("\n  (Update INFRA_COSTS in analytics.py to match actual billing)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Egregore Unit Economics Report")
    parser.add_argument("--days", type=int, default=7, help="Number of days to report on")
    parser.add_argument("--component", type=str, help="Filter by component (bot, sync, mcp)")
    args = parser.parse_args()

    report(args.days)
