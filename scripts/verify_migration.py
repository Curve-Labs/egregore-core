#!/usr/bin/env python3
"""Verify Neo4j → Supabase migration.

Uses httpx + Supabase REST API directly (no supabase Python library needed).
"""

import os
import sys
import json
import hashlib
import base64
import logging

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


def sb_get(url, key, table, select="*", filters=None, count=False):
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    if count:
        headers["Prefer"] = "count=exact"
    endpoint = f"{url}/rest/v1/{table}?select={select}"
    if filters:
        for k, v in filters.items():
            endpoint += f"&{k}={v}"
    resp = httpx.get(endpoint, headers=headers, timeout=15.0)
    if count:
        content_range = resp.headers.get("content-range", "")
        # Format: "0-9/10" or "*/0"
        if "/" in content_range:
            total = content_range.split("/")[1]
            return int(total) if total != "*" else 0
        return len(resp.json()) if resp.status_code == 200 else 0
    return resp.json() if resp.status_code == 200 else []


def main():
    neo4j_host = os.environ.get("EGREGORE_NEO4J_HOST", "")
    neo4j_user = os.environ.get("EGREGORE_NEO4J_USER", "neo4j")
    neo4j_password = os.environ.get("EGREGORE_NEO4J_PASSWORD", "")
    supabase_url = os.environ.get("SUPABASE_URL", "")
    supabase_key = os.environ.get("SUPABASE_SERVICE_KEY", "")

    if not all([neo4j_host, neo4j_password, supabase_url, supabase_key]):
        logger.error("Missing required env vars")
        sys.exit(1)

    org_configs = {}
    raw = os.environ.get("ORG_CONFIGS", "{}")
    try:
        org_configs = json.loads(raw)
    except json.JSONDecodeError:
        pass
    cl_key = os.environ.get("CURVELABS_API_KEY", "")
    if cl_key and "curvelabs" not in org_configs:
        org_configs["curvelabs"] = {"api_key": cl_key}

    passed = 0
    failed = 0

    # Check 1: Org count
    print("\n=== Check 1: Org Count ===")
    neo4j_orgs = neo4j_query(neo4j_host, neo4j_user, neo4j_password,
        "MATCH (o:Org) WHERE o.id IS NOT NULL RETURN count(o) AS cnt")
    neo4j_count = neo4j_orgs.get("values", [[0]])[0][0]
    sb_count = sb_get(supabase_url, supabase_key, "orgs", select="slug", count=True)

    if neo4j_count == sb_count:
        print(f"  PASS: {neo4j_count} orgs in both")
        passed += 1
    else:
        print(f"  FAIL: Neo4j={neo4j_count}, Supabase={sb_count}")
        failed += 1

    # Check 2: API key validation
    print("\n=== Check 2: API Key Validation ===")
    test_key = None
    test_slug = None
    for slug, config in org_configs.items():
        if config.get("api_key"):
            test_key = config["api_key"]
            test_slug = slug
            break

    if test_key:
        # Check if this org exists in Supabase (private orgs like 'curvelabs' won't be there)
        org_exists = sb_get(supabase_url, supabase_key, "orgs", select="slug",
                            filters={"slug": f"eq.{test_slug}"})
        if not org_exists:
            print(f"  SKIP: '{test_slug}' is a private org (not in shared DB), checking a migrated org instead")
            # Pick the first migrated org's key from the api_keys table
            sample = sb_get(supabase_url, supabase_key, "api_keys", select="org_slug,key_prefix,key_hash",
                            filters={"is_active": "eq.true"})
            if sample:
                print(f"  PASS: {len(sample)} active API keys found in Supabase (hash validation requires original key)")
                passed += 1
            else:
                print(f"  FAIL: No active API keys found in Supabase")
                failed += 1
        else:
            key_hash = hashlib.sha256(test_key.encode()).hexdigest()
            parts = test_key.split("_")
            prefix = f"ek_{parts[1]}_{parts[2][:8]}" if len(parts) >= 3 else test_key[:20]

            rows = sb_get(supabase_url, supabase_key, "api_keys", select="org_slug,key_hash",
                          filters={"key_prefix": f"eq.{prefix}", "is_active": "eq.true"})

            found = any(r["key_hash"] == key_hash and r["org_slug"] == test_slug for r in rows)
            if found:
                print(f"  PASS: API key for '{test_slug}' validates via hash")
                passed += 1
            else:
                print(f"  FAIL: API key for '{test_slug}' not found or hash mismatch")
                failed += 1
    else:
        print("  SKIP: No API keys in ORG_CONFIGS to test")

    # Check 3: Telegram chat_ids
    print("\n=== Check 3: Telegram Chat IDs ===")
    neo4j_tg = neo4j_query(neo4j_host, neo4j_user, neo4j_password,
        "MATCH (o:Org) WHERE o.telegram_chat_id IS NOT NULL "
        "RETURN o.id AS slug, o.telegram_chat_id AS chat_id")
    neo4j_map = {}
    for row in neo4j_tg.get("values", []):
        if row[0] and row[1]:
            neo4j_map[row[0]] = row[1]

    sb_tg = sb_get(supabase_url, supabase_key, "orgs", select="slug,telegram_chat_id",
                   filters={"telegram_chat_id": "not.is.null"})
    sb_map = {r["slug"]: r["telegram_chat_id"] for r in sb_tg}

    tg_match = True
    for slug, chat_id in neo4j_map.items():
        if slug not in sb_map:
            print(f"  FAIL: {slug} missing in Supabase")
            tg_match = False
        elif sb_map[slug] != chat_id:
            print(f"  FAIL: {slug} mismatch: Neo4j={chat_id}, Supabase={sb_map[slug]}")
            tg_match = False

    if tg_match and neo4j_map:
        print(f"  PASS: All {len(neo4j_map)} telegram_chat_ids match")
        passed += 1
    elif not neo4j_map:
        print("  SKIP: No Telegram chat_ids")
    else:
        failed += 1

    # Check 4: API key coverage
    print("\n=== Check 4: API Key Coverage ===")
    all_orgs = sb_get(supabase_url, supabase_key, "orgs", select="slug")
    keys = sb_get(supabase_url, supabase_key, "api_keys", select="org_slug",
                  filters={"is_active": "eq.true"})
    orgs_with_keys = set(r["org_slug"] for r in keys)
    missing = [r["slug"] for r in all_orgs if r["slug"] not in orgs_with_keys]

    if not missing:
        print(f"  PASS: All {len(all_orgs)} orgs have active API keys")
        passed += 1
    else:
        print(f"  WARN: {len(missing)} orgs without keys: {missing}")
        failed += 1

    # Check 5: Users & memberships
    print("\n=== Check 5: Users & Memberships ===")
    user_count = sb_get(supabase_url, supabase_key, "users", select="id", count=True)
    mem_count = sb_get(supabase_url, supabase_key, "memberships", select="id", count=True)
    print(f"  INFO: {user_count} users, {mem_count} memberships")
    if user_count > 0:
        passed += 1
    else:
        print("  WARN: No users migrated")

    print(f"\n=== Results: {passed} passed, {failed} failed ===\n")
    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()
