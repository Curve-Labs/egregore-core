Egregore is being prepared for an open-source release. The OSS
version must work when Neo4j, Supabase, and the Egregore API
are NOT configured (no API key in .env). The connected version
(with API key) continues to use all services as before.

Both modes live in the same codebase (CL/egregore-core).
Changes are developed and tested here on the develop branch.
OSS-ready changes will later be cherry-picked to a separate
public repo (egregore-ai/egregore). The connected/paid code
paths must never break — OSS changes are additive fallbacks.

When EGREGORE_API_KEY is present → full behavior, graph,
notifications, dashboard, everything works as it does today.

When EGREGORE_API_KEY is absent → local mode. Commands degrade
gracefully: return empty results from graph.sh, skip notifications,
write markdown to memory/, use filesystem for all reads.

Rules:
- NEVER remove existing graph/API/Supabase code paths.
- ADD fallback behavior when API key is missing.
- Commands must be useful in local mode OR show "/connect to enable."
- Files = truth, graph = query layer on top.
- Tag command specs with tier: 1 (local), 2 (free API), 3 (paid).
- All changes must pass the existing test suite — connected mode
  must work exactly as before.
