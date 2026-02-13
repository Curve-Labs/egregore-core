-- Egregore Admin Layer: Supabase PostgreSQL Schema
-- Replaces Neo4j Org nodes for platform/admin concerns.
-- Neo4j remains the knowledge graph (Person, Session, Artifact, Quest, Project, Spirit).

-- =============================================================================
-- ORGS
-- =============================================================================

CREATE TABLE IF NOT EXISTS orgs (
    slug TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    github_org TEXT NOT NULL,
    neo4j_host TEXT NOT NULL DEFAULT '',
    neo4j_user TEXT NOT NULL DEFAULT 'neo4j',
    neo4j_password TEXT NOT NULL DEFAULT '',
    telegram_chat_id TEXT UNIQUE,
    telegram_group_title TEXT,
    telegram_group_username TEXT,
    created_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- USERS
-- =============================================================================

CREATE TABLE IF NOT EXISTS users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    github_username TEXT NOT NULL UNIQUE,
    github_name TEXT,
    avatar_url TEXT,
    telegram_username TEXT,
    telegram_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- MEMBERSHIPS
-- =============================================================================

CREATE TABLE IF NOT EXISTS memberships (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_slug TEXT NOT NULL REFERENCES orgs(slug) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'invited', 'removed')),
    invited_by BIGINT REFERENCES users(id),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(org_slug, user_id)
);

CREATE INDEX IF NOT EXISTS idx_memberships_org ON memberships(org_slug);
CREATE INDEX IF NOT EXISTS idx_memberships_user ON memberships(user_id);

-- =============================================================================
-- API KEYS
-- =============================================================================

CREATE TABLE IF NOT EXISTS api_keys (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_slug TEXT NOT NULL REFERENCES orgs(slug) ON DELETE CASCADE,
    key_prefix TEXT NOT NULL,
    key_hash TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_api_keys_prefix ON api_keys(key_prefix) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_api_keys_org ON api_keys(org_slug);

-- =============================================================================
-- SETUP TOKENS
-- =============================================================================

CREATE TABLE IF NOT EXISTS setup_tokens (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    token TEXT NOT NULL UNIQUE,
    token_type TEXT NOT NULL DEFAULT 'setup' CHECK (token_type IN ('setup', 'invite')),
    data JSONB NOT NULL DEFAULT '{}',
    expires_at TIMESTAMPTZ NOT NULL,
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_setup_tokens_token ON setup_tokens(token) WHERE claimed_at IS NULL;

-- =============================================================================
-- WAITLIST
-- =============================================================================

CREATE TABLE IF NOT EXISTS waitlist (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email TEXT,
    github_username TEXT,
    source TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at TIMESTAMPTZ,
    approved_by BIGINT REFERENCES users(id)
);

-- =============================================================================
-- TELEGRAM EVENTS (audit log)
-- =============================================================================

CREATE TABLE IF NOT EXISTS telegram_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_slug TEXT REFERENCES orgs(slug) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    chat_id TEXT,
    group_title TEXT,
    triggered_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_telegram_events_org ON telegram_events(org_slug);

-- =============================================================================
-- HELPER: Auto-cleanup expired tokens (optional — can run via cron or pg_cron)
-- =============================================================================

CREATE OR REPLACE FUNCTION cleanup_expired_tokens()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM setup_tokens
    WHERE expires_at < now() AND claimed_at IS NULL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
