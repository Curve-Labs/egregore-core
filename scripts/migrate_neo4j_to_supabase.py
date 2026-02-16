#!/usr/bin/env python3
"""Migrate org data from Neo4j to Supabase.

Uses httpx + Supabase REST API directly (no supabase Python library needed).

Usage:
    # Dry run (default)
    python scripts/migrate_neo4j_to_supabase.py

    # Execute migration
    python scripts/migrate_neo4j_to_supabase.py --execute
"""

import os
import sys
import json
import hashlib
import logging
import base64

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv("api/.env", override=False)

import httpx

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def neo4j_query(host, user, password, statement, params=None):
    url = f"https://{host}/db/neo4j/query/v2"
    auth_str = base64.b64encode(f"{user}:{password}".encode()).decode()
    body = {"statement": statement}
    if params:
        body["parameters"] = params
    resp = httpx.post(url, json=body, headers={
        "Content-Type": "application/json",
        "Authorization": f"Basic {auth_str}",
    }, timeout=30.0)
    resp.raise_for_status()
    data = resp.json()
    if data.get("errors"):
        raise RuntimeError(f"Neo4j error: {data['errors']}")
    return data.get("data", {})


def sb_request(url, key, method, table, data=None, params=None, prefer=None):
    """Make a Supabase REST API request."""
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer

    endpoint = f"{url}/rest/v1/{table}"
    if params:
        endpoint += "?" + "&".join(f"{k}={v}" for k, v in params.items())

    if method == "POST":
        resp = httpx.post(endpoint, json=data, headers=headers, timeout=15.0)
    elif method == "GET":
        resp = httpx.get(endpoint, headers=headers, timeout=15.0)
    elif method == "PATCH":
        resp = httpx.patch(endpoint, json=data, headers=headers, timeout=15.0)
    else:
        raise ValueError(f"Unsupported method: {method}")

    if resp.status_code >= 400:
        logger.error(f"  Supabase {method} {table}: {resp.status_code} {resp.text}")
    return resp


def sb_upsert(url, key, table, data, on_conflict=""):
    """Upsert into Supabase table."""
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
    }
    endpoint = f"{url}/rest/v1/{table}"
    if on_conflict:
        endpoint += f"?on_conflict={on_conflict}"
    resp = httpx.post(endpoint, json=data, headers=headers, timeout=15.0)
    return resp


def sb_select(url, key, table, select="*", filters=None):
    """Select from Supabase table."""
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }
    endpoint = f"{url}/rest/v1/{table}?select={select}"
    if filters:
        for k, v in filters.items():
            endpoint += f"&{k}=eq.{v}"
    resp = httpx.get(endpoint, headers=headers, timeout=15.0)
    if resp.status_code == 200:
        return resp.json()
    return []


def hash_api_key(key):
    return hashlib.sha256(key.encode()).hexdigest()


def key_prefix(api_key):
    parts = api_key.split("_")
    if len(parts) >= 3:
        return f"ek_{parts[1]}_{parts[2][:8]}"
    return api_key[:20]


def main():
    execute = "--execute" in sys.argv

    neo4j_host = os.environ.get("EGREGORE_NEO4J_HOST", "")
    neo4j_user = os.environ.get("EGREGORE_NEO4J_USER", "neo4j")
    neo4j_password = os.environ.get("EGREGORE_NEO4J_PASSWORD", "")
    supabase_url = os.environ.get("SUPABASE_URL", "")
    supabase_key = os.environ.get("SUPABASE_SERVICE_KEY", "")

    if not neo4j_host or not neo4j_password:
        logger.error("Missing EGREGORE_NEO4J_HOST / EGREGORE_NEO4J_PASSWORD")
        sys.exit(1)

    if execute and (not supabase_url or not supabase_key):
        logger.error("Missing SUPABASE_URL / SUPABASE_SERVICE_KEY for --execute mode")
        sys.exit(1)

    # Also load ORG_CONFIGS for API keys not stored in Neo4j
    org_configs = {}
    raw = os.environ.get("ORG_CONFIGS", "{}")
    try:
        org_configs = json.loads(raw)
    except json.JSONDecodeError:
        pass

    # Also check individual env vars for curvelabs
    cl_key = os.environ.get("CURVELABS_API_KEY", "")
    if cl_key and "curvelabs" not in org_configs:
        org_configs["curvelabs"] = {"api_key": cl_key}

    # Step 1: Extract Org nodes
    logger.info("Querying Org nodes from Neo4j...")
    org_data = neo4j_query(
        neo4j_host, neo4j_user, neo4j_password,
        "MATCH (o:Org) RETURN o.id AS slug, o.name AS name, o.github_org AS github_org, "
        "o.api_key AS api_key, o.telegram_chat_id AS telegram_chat_id, "
        "o.telegram_group_title AS telegram_group_title, "
        "o.telegram_group_username AS telegram_group_username, "
        "o.created_by AS created_by",
    )

    orgs = []
    for row in org_data.get("values", []):
        slug, name, github_org, api_key, chat_id, group_title, group_username, created_by = row
        if not slug:
            continue
        if not api_key and slug in org_configs:
            api_key = org_configs[slug].get("api_key", "")
        orgs.append({
            "slug": slug,
            "name": name or slug,
            "github_org": github_org or slug,
            "api_key": api_key or "",
            "telegram_chat_id": chat_id or None,
            "telegram_group_title": group_title or None,
            "telegram_group_username": group_username or None,
            "created_by": created_by or None,
        })

    logger.info(f"Found {len(orgs)} orgs in Neo4j")

    # Step 2: Extract TelegramUser nodes
    logger.info("Querying TelegramUser nodes...")
    tu_data = neo4j_query(
        neo4j_host, neo4j_user, neo4j_password,
        "MATCH (tu:TelegramUser) "
        "OPTIONAL MATCH (tu)-[:IDENTIFIES]->(p) "
        "RETURN tu.username AS username, tu.telegramId AS tid, "
        "COLLECT(DISTINCT p.github) AS github_usernames, "
        "COLLECT(DISTINCT p.org) AS orgs",
    )

    telegram_users = []
    for row in tu_data.get("values", []):
        username, tid, github_usernames, user_orgs = row
        github_username = next((g for g in (github_usernames or []) if g), None)
        telegram_users.append({
            "telegram_username": username,
            "telegram_id": int(tid) if tid else None,
            "github_username": github_username,
            "orgs": [o for o in (user_orgs or []) if o],
        })

    logger.info(f"Found {len(telegram_users)} TelegramUser nodes")

    # Step 3: Extract Person nodes
    logger.info("Querying Person nodes with GitHub info...")
    person_data = neo4j_query(
        neo4j_host, neo4j_user, neo4j_password,
        "MATCH (p:Person) WHERE p.github IS NOT NULL "
        "RETURN p.github AS github, p.name AS name, p.org AS org, "
        "p.telegramUsername AS tg_username",
    )

    persons = []
    for row in person_data.get("values", []):
        github, name, org, tg_username = row
        if github and org:
            persons.append({
                "github_username": github,
                "name": name,
                "org": org,
                "telegram_username": tg_username,
            })

    logger.info(f"Found {len(persons)} Person nodes with GitHub + org")

    # Print summary
    print("\n=== Migration Summary ===\n")
    print(f"Orgs: {len(orgs)}")
    for o in orgs:
        key_status = "has key" if o["api_key"] else "NO KEY"
        tg_status = f"chat={o['telegram_chat_id']}" if o["telegram_chat_id"] else "no telegram"
        print(f"  {o['slug']:30s} {key_status:10s} {tg_status}")

    print(f"\nTelegram Users: {len(telegram_users)}")
    for tu in telegram_users[:10]:
        print(f"  @{tu['telegram_username'] or '?':20s} github={tu['github_username'] or '?'} orgs={tu['orgs']}")
    if len(telegram_users) > 10:
        print(f"  ... and {len(telegram_users) - 10} more")

    print(f"\nPersons (with GitHub): {len(persons)}")
    for p in persons[:10]:
        print(f"  {p['github_username']:20s} org={p['org']}")
    if len(persons) > 10:
        print(f"  ... and {len(persons) - 10} more")

    if not execute:
        print("\nDry run complete. Add --execute to migrate.")
        return

    # Step 4: Write to Supabase
    print("\n=== Executing Migration ===\n")

    default_neo4j_host = neo4j_host
    default_neo4j_user = neo4j_user
    default_neo4j_password = neo4j_password

    # 4a: Insert orgs
    org_count = 0
    for o in orgs:
        org_row = {
            "slug": o["slug"],
            "name": o["name"],
            "github_org": o["github_org"],
            "neo4j_host": default_neo4j_host,
            "neo4j_user": default_neo4j_user,
            "neo4j_password": default_neo4j_password,
            "created_by": o["created_by"],
        }
        if o["telegram_chat_id"]:
            org_row["telegram_chat_id"] = o["telegram_chat_id"]
        if o["telegram_group_title"]:
            org_row["telegram_group_title"] = o["telegram_group_title"]
        if o["telegram_group_username"]:
            org_row["telegram_group_username"] = o["telegram_group_username"]

        resp = sb_upsert(supabase_url, supabase_key, "orgs", org_row, on_conflict="slug")
        if resp.status_code < 300:
            org_count += 1
            logger.info(f"  Upserted org: {o['slug']}")
        else:
            logger.error(f"  Failed org {o['slug']}: {resp.status_code} {resp.text}")

    # 4b: Insert API keys (hashed)
    key_count = 0
    for o in orgs:
        if not o["api_key"]:
            continue
        row = {
            "org_slug": o["slug"],
            "key_prefix": key_prefix(o["api_key"]),
            "key_hash": hash_api_key(o["api_key"]),
            "is_active": True,
        }
        resp = sb_request(supabase_url, supabase_key, "POST", "api_keys", data=row,
                          prefer="resolution=merge-duplicates")
        if resp.status_code < 300:
            key_count += 1
        else:
            logger.error(f"  Failed API key for {o['slug']}: {resp.status_code} {resp.text}")

    # 4c: Insert users
    user_count = 0
    seen_users = set()
    for p in persons:
        gh = p["github_username"]
        if gh in seen_users:
            continue
        seen_users.add(gh)
        user_data = {"github_username": gh}
        if p.get("name"):
            user_data["github_name"] = p["name"]
        if p.get("telegram_username"):
            user_data["telegram_username"] = p["telegram_username"]
        resp = sb_upsert(supabase_url, supabase_key, "users", user_data, on_conflict="github_username")
        if resp.status_code < 300:
            user_count += 1
        else:
            logger.error(f"  Failed user {gh}: {resp.status_code} {resp.text}")

    # 4d: Insert memberships
    membership_count = 0
    for p in persons:
        gh = p["github_username"]
        org_slug = p["org"]

        users = sb_select(supabase_url, supabase_key, "users", select="id", filters={"github_username": gh})
        if not users:
            continue
        user_id = users[0]["id"]

        org_exists = sb_select(supabase_url, supabase_key, "orgs", select="slug", filters={"slug": org_slug})
        if not org_exists:
            continue

        row = {
            "org_slug": org_slug,
            "user_id": user_id,
            "role": "member",
            "status": "active",
        }
        resp = sb_upsert(supabase_url, supabase_key, "memberships", row, on_conflict="org_slug,user_id")
        if resp.status_code < 300:
            membership_count += 1
        else:
            logger.error(f"  Failed membership {gh}→{org_slug}: {resp.status_code} {resp.text}")

    print(f"\n=== Migration Complete ===")
    print(f"Orgs:        {org_count}/{len(orgs)}")
    print(f"API Keys:    {key_count}/{len([o for o in orgs if o['api_key']])}")
    print(f"Users:       {user_count}/{len(seen_users)}")
    print(f"Memberships: {membership_count}/{len(persons)}")
    print(f"\nRun 'python scripts/verify_migration.py' to verify.")


if __name__ == "__main__":
    main()
