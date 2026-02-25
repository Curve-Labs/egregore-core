Welcome a new user to this Egregore.

Deterministic joiner state machine. Every state has explicit entry conditions, actions, exit conditions, and API calls. Execute states literally — no improvisation, no skipping, no reordering.

## Output discipline — CRITICAL

This is a conversation with a new user, not a CI pipeline. The user should see a smooth, friendly flow — not a stream of tool calls and logs.

**Rules:**
- **Suppress ALL output.** Every bash call must redirect both stdout and stderr: `>/dev/null 2>&1` or capture to a variable. The user must NEVER see raw JSON, curl responses, jq output, or git logs. If you need data from a command, capture it: `RESULT=$(command 2>/dev/null)`.
- **No narration of internal steps.** Never say "Let me check..." or "Saving..." or "Calling the API." Just do it silently between user-facing messages.
- **Minimize tool calls.** Every tool call is a visible UI element (a bullet point the user sees). Combine bash commands with `&&`. Combine state saves + API calls into ONE bash call. Read multiple files in one parallel Read call.
- **No intermediate state saves between user messages.** Only save state AFTER the user has answered a question and BEFORE showing the next question. Combine the save with any API call into one Bash call.
- **VERIFY should be invisible.** One Bash call + one Read call. If everything passes, say nothing — go straight to WELCOME text.
- **COMPLETE should be ONE Bash call.** All 7 sub-steps in a single script. User sees one bullet, then "You're in."

**Ideal tool call sequence (what the user sees as bullet points):**
1. `Bash` — VERIFY checks (silent)
2. `Reading 2 files...` — egregore.md + egregore.json (silent)
3. Welcome text (no tool call)
4. `AskUserQuestion` — name + role
5. `Bash` — save state + API call (silent, ONE call)
6. `AskUserQuestion` — interest + style
7. `AskUserQuestion` — privacy
8. `Bash` — save all state + graph queries (silent, ONE call)
9. Activity text (no tool call)
10. `AskUserQuestion` — how to start
11. `Bash` — COMPLETE all steps (silent, ONE call)
12. "You're in." text (no tool call)

That's 4 Bash + 1 Read + 4 AskUserQuestion = **9 tool call bullets total**. Anything more means you're doing it wrong.

**State machine:**
```
VERIFY → WELCOME → HARVEST_IDENTITY → HARVEST_CONNECTION → CONSENT → ORIENT → COMPLETE
```

## Resumption

Read `.egregore-state.json`. If `onboarding.phase` exists and `onboarding_complete` is false, resume from that phase. Do NOT restart from VERIFY — jump directly to the saved phase and use any data already in state.

If `onboarding_complete` is true, say: "You're already set up. Run `/me` to update your profile, or just start working." Then stop.

---

## State: VERIFY

**Entry:** `onboarding_complete` is false (or missing) in `.egregore-state.json`

**Actions — exactly 2 tool calls:**

**Tool call 1 (Bash):** Run all checks in a single bash call:
```bash
TOKEN=$(grep '^GITHUB_TOKEN=' .env 2>/dev/null | cut -d'=' -f2-) && \
APIKEY=$(grep '^EGREGORE_API_KEY=' .env 2>/dev/null | cut -d'=' -f2-) && \
SYMLINK=$(test -L memory && echo "ok" || echo "") && \
ORG=$(jq -r '.org_name' egregore.json 2>/dev/null) && \
echo "token:${TOKEN:+ok} apikey:${APIKEY:+ok} memory:${SYMLINK} org:${ORG}"
```

**Tool call 2 (Read, parallel):** Read `egregore.json` AND `egregore.md` in one parallel Read call. These are needed for WELCOME and all subsequent states. Do NOT read them again later.

**Exit conditions:**
- IF all three checks pass → WELCOME (no text output, go straight to welcome message)
- IF `GITHUB_TOKEN` missing → run `bash bin/github-auth.sh`, re-check. IF still missing → HALT: "GitHub auth failed. Run `bash bin/github-auth.sh` manually."
- IF `EGREGORE_API_KEY` missing → HALT: "Missing API key. Ask your team admin for it, then add `EGREGORE_API_KEY=ek_...` to `.env`."
- IF `memory/` missing → run workspace setup (clone + symlink). IF fails → HALT with git error.

---

## State: WELCOME

**Entry:** VERIFY passed

**Actions — ZERO tool calls:**

All data is already in context from VERIFY. Do NOT re-read any files. Do NOT save state yet (no intermediate saves).

1. Extract `## Identity` and `## Culture` sections from egregore.md (already in context)
2. Use `github_username`, `github_name` from `.egregore-state.json` (already in context from session-start hook)
3. Display welcome message:

```
Welcome to {org_name}.

{First 2 sentences of Identity section from egregore.md}

{First sentence of Culture section from egregore.md}

Let's get you set up — a few quick questions.
```

**Exit:** → HARVEST_IDENTITY immediately. Output the welcome text, then the AskUserQuestion, in the SAME response. No tool calls between them.

---

## State: HARVEST_IDENTITY

**Entry:** WELCOME completed (same response)

**Actions — 1 AskUserQuestion tool call:**

**IF `github_name` exists in state:**

```
questions:
  Q1:
    question: "What should we call you here? Your GitHub name is {github_name}."
    header: "Name"
    options:
      - label: "{github_name}"
        description: "Use my GitHub name"
      - label: "Something else"
        description: "I go by a different name"
  Q2:
    question: "What do you do?"
    header: "Role"
    options:
      - label: "Engineering"
        description: "I write code"
      - label: "Design"
        description: "I design products or experiences"
      - label: "Research"
        description: "I explore ideas and synthesize knowledge"
      - label: "Operations"
        description: "I keep things running and organized"
```

**IF `github_name` NOT in state:**
Same but Q1 says "What's your name?" with `{github_username}` as first option.

**Post-processing (after user answers):**
- IF Q1 = first option → `display_name = github_name` (or `github_username`)
- IF Q1 = freeform → `display_name = freeform text` (validate: 1-30 chars, alphanumeric + spaces + hyphens)
- `role = Q2 answer` (map to: `engineering` | `design` | `research` | `operations` | `other`)

**After user answers — 1 Bash call (state save + API combined):**

```bash
jq '. + {"display_name": "NAME", "name": "NAME", "onboarding": (.onboarding // {} | . + {"phase": "harvest_identity", "type": "joiner", "started_at": "TIMESTAMP", "harvest_rounds": [{"round": 1, "focus": "identity", "questions": ["name", "role"], "answers": {"name": "NAME", "role": "ROLE"}}]})}' .egregore-state.json > /tmp/es.json && mv /tmp/es.json .egregore-state.json && \
API_URL="$(jq -r '.api_url' egregore.json)" && \
API_KEY="$(grep '^EGREGORE_API_KEY=' .env | cut -d'=' -f2-)" && \
curl -sf "${API_URL}/api/user/ensure" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"github_username":"...","github_name":"...","display_name":"..."}' >/dev/null 2>&1 && \
echo "ok"
```

Replace all `"..."` with actual values. This is ONE tool call that saves state AND calls the API.

**Exit:** → HARVEST_CONNECTION. Transition immediately — present the next AskUserQuestion in the SAME response as this Bash call. Do NOT add any text between them.

---

## State: HARVEST_CONNECTION

**Entry:** HARVEST_IDENTITY completed

**Actions — 1 AskUserQuestion tool call:**

Extract `## Collaboration` section from `egregore.md` — already in context from VERIFY. Do NOT re-read.

**Deriving Q1 options:** The first 3 bullet points or comma-separated items from the Collaboration section become option labels. If fewer than 2 items found, use defaults: "Building / Exploring / Participating."

```
questions:
  Q1:
    question: "What brings you to {org_name}?"
    header: "Interest"
    options:
      - label: "{work_area_1}"
        description: "{description from Collaboration section}"
      - label: "{work_area_2}"
        description: "{description from Collaboration section}"
      - label: "{work_area_3}"
        description: "{description from Collaboration section}"
  Q2:
    question: "How do you like to work?"
    header: "Style"
    options:
      - label: "Async"
        description: "Handoffs and artifacts — I work on my own schedule"
      - label: "Collaborative"
        description: "Pairing, discussions, real-time coordination"
      - label: "Both"
        description: "Depends on the task"
```

**Post-processing:**
- `focus = Q1 answer` (map to slug: `building` | `exploring` | `evaluating` | `other`)
- `work_style = Q2 answer` (map to: `async` | `collaborative` | `both`)

**After user answers — do NOT save state yet.** Proceed directly to CONSENT. Present the CONSENT AskUserQuestion in the SAME response. Zero tool calls between HARVEST_CONNECTION answer and CONSENT question.

---

## State: CONSENT

**Entry:** HARVEST_CONNECTION completed (same response)

**Actions — 1 AskUserQuestion tool call:**

```
questions:
  Q1:
    question: "A few privacy choices. These are yours to change anytime via /telemetry and /env."
    header: "Privacy"
    multiSelect: true
    options:
      - label: "Session tracking"
        description: "Powers /dashboard and /handoff. Your sessions appear in /activity."
      - label: "Transcript sharing"
        description: "Session transcripts are stored for team context. Others can see what you worked on."
      - label: "Anonymous telemetry"
        description: "Command names, session durations, error codes. Never code or content."
      - label: "Notifications"
        description: "Receive Telegram DMs when someone hands off to you or @mentions you."
```

**Post-processing:**
- Map selections to boolean flags:
  - "Session tracking" → `session_tracking: true/false`
  - "Transcript sharing" → `transcript_sharing: true/false`
  - "Anonymous telemetry" → `telemetry: true/false`
  - "Notifications" → `contact_preference: "all"/"none"`

**After user answers — 1 Bash call (save connection + consent state + graph queries, ALL combined):**

```bash
# Save harvest_connection + consent state
jq '. + {
  "session_tracking": ST, "transcript_sharing": TS, "telemetry": TEL, "contact_preference": "CP",
  "onboarding": (.onboarding | . + {
    "phase": "consent",
    "harvest_rounds": (.harvest_rounds + [{"round": 2, "focus": "connection", "questions": ["interest", "style"], "answers": {"interest": "FOCUS", "style": "STYLE"}}]),
    "consent": {"session_tracking": ST, "transcript_sharing": TS, "telemetry": TEL, "contact_preference": "CP"}
  })
}' .egregore-state.json > /tmp/es.json && mv /tmp/es.json .egregore-state.json && \
# Query graph for orient
QUESTS=$(bash bin/graph.sh query "MATCH (q:Quest {status: 'active'}) OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q) RETURN q.id AS quest, q.title AS title, count(a) AS artifacts ORDER BY count(a) DESC LIMIT 3" 2>/dev/null) && \
HANDOFFS=$(bash bin/graph.sh query "MATCH (s:Session) WHERE s.date IS NOT NULL MATCH (s)-[:BY]->(author:Person) RETURN s.topic AS topic, author.name AS author ORDER BY s.date DESC LIMIT 3" 2>/dev/null) && \
echo "QUESTS:${QUESTS}|||HANDOFFS:${HANDOFFS}"
```

Replace `ST`, `TS`, `TEL`, `CP`, `FOCUS`, `STYLE` with actual values from user answers.

**Exit:** → ORIENT. Parse the graph query results from the Bash output, then display activity summary + AskUserQuestion in the SAME response.

---

## State: ORIENT

**Entry:** CONSENT completed, graph data already fetched

**Actions — activity text + 1 AskUserQuestion (same response, no extra tool calls):**

Parse the QUESTS and HANDOFFS data from the previous Bash call.

1. Display activity summary:
   - IF quests exist: "Here's what's active:" followed by quest list with artifact counts
   - IF handoffs exist: "Recent sessions:" followed by 2-3 recent sessions with authors
   - IF empty: "It's early — you're one of the first here."

2. AskUserQuestion (in same response as activity text):
```
questions:
  Q1:
    question: "How do you want to start?"
    header: "Start"
    options:
      - label: "Jump in"
        description: "I'll explore on my own. Help me as I go."
      - label: "Show me around"
        description: "5-minute walkthrough of the core commands"
```

3. IF "Jump in":
   Show 1-2 suggestions based on harvest answers:
   - IF focus = `building` AND quests exist: "Check out the {quest_title} quest — `/quest {slug}`"
   - IF focus = `exploring`: "Try `/activity` to see what's happening, or `/reflect` to capture your first thought."
   - IF focus = `evaluating`: "Run `/dashboard` to see the system from your perspective."
   → COMPLETE

4. IF "Show me around":
   Invoke `/tutorial` — reads `domain`, `stage`, `usage_type` from state and skips redundant questions.
   → COMPLETE (after tutorial finishes)

**Exit:** → COMPLETE (always)

---

## State: COMPLETE

**Entry:** ORIENT completed

**Actions — 1 Bash call, then done:**

ALL steps in ONE Bash call. Every sub-command must suppress output with `>/dev/null 2>&1`. The script below is a template — fill all values from state before running.

```bash
# 1. Update egregore.md Members section (use Edit tool for this one, in parallel with the Bash)
# 2-7. Everything else in one bash call:
cat > "memory/people/{github_username}.md" << 'PERSONEOF'
# {display_name}
GitHub: {github_username}
Role: {role}
Focus: {focus}
Work style: {work_style}
Joined: {YYYY-MM-DD}
PERSONEOF

# Memory commit + push
cd memory && git add -A && git commit -m "Add {github_username}" && git push >/dev/null 2>&1; cd - >/dev/null

# Neo4j: check name uniqueness then MERGE
TAKEN=$(bash bin/graph.sh query \
  "OPTIONAL MATCH (existing:Person {name: \$name, org: \$org}) WHERE existing.github <> \$github RETURN existing IS NOT NULL AS taken" \
  '{"name":"NAME","org":"ORG","github":"GH"}' 2>/dev/null)

# If name taken, append username
NAME="DISPLAY_NAME"
echo "$TAKEN" | grep -q "true" && NAME="DISPLAY_NAME (GH_USERNAME)"

bash bin/graph.sh query \
  "MERGE (p:Person {github: \$github, org: \$org})
   ON CREATE SET p.name = \$name, p.fullName = \$fullName, p.role = \$role, p.focus = \$focus, p.workStyle = \$workStyle, p.joined = date(), p.sessionTracking = \$st, p.transcriptSharing = \$ts, p.telemetry = \$tel, p.contactPreference = \$cp
   ON MATCH SET p.name = \$name, p.role = \$role, p.focus = \$focus, p.workStyle = \$workStyle, p.sessionTracking = \$st, p.transcriptSharing = \$ts, p.telemetry = \$tel, p.contactPreference = \$cp
   RETURN p.name" \
  '{"github":"GH","org":"ORG","name":"'"$NAME"'","fullName":"FULL","role":"ROLE","focus":"FOCUS","workStyle":"STYLE","st":true,"ts":true,"tel":true,"cp":"all"}' >/dev/null 2>&1

# Supabase sync
API_URL="$(jq -r '.api_url' egregore.json)" && \
API_KEY="$(grep '^EGREGORE_API_KEY=' .env | cut -d'=' -f2-)" && \
curl -sf "${API_URL}/api/user/ensure" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"github_username":"GH","github_name":"FULL","display_name":"'"$NAME"'","member_role":"ROLE","focus":"FOCUS","work_style":"STYLE","consent_session_tracking":true,"consent_transcript_sharing":true,"consent_telemetry":true,"contact_preference":"all"}' >/dev/null 2>&1

# Update state
jq '. + {"onboarding_complete": true, "usage_type": "joiner_group", "onboarding": (.onboarding | . + {"phase": "complete", "completed_at": "TIMESTAMP"})}' .egregore-state.json > /tmp/es.json && mv /tmp/es.json .egregore-state.json

# Shell alias
ALIAS=$(bash bin/ensure-shell-function.sh 2>/dev/null)

# Telemetry
bash bin/telemetry.sh emit "onboarding_complete" '{"type":"joiner","rounds":2}' >/dev/null 2>&1 &

echo "alias:${ALIAS:-egregore}"
```

Use the `Edit` tool to update `egregore.md` Members section IN PARALLEL with the Bash call above. Append after `## Members`:
```markdown
### {display_name}
{role_label}. {focus_label}. Joined {YYYY-MM-DD}.
```

**After both complete, display:**

> You're in. From now on, just type **`{ALIAS_NAME}`** in any terminal to launch.
>
> Type `/activity` to see what's happening, or just start working.
