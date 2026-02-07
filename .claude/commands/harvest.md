Harvest context — extracting structured insights from self, others, or the organization.

Arguments: $ARGUMENTS (Optional: [person] about [topic], or empty to answer pending)

## Usage

- `/harvest` — Answer pending harvests (if any), or start reflection
- `/harvest me about [topic]` — Self-reflection with AI-generated questions
- `/harvest [person] about [topic]` — Queue questions for another person (no @ needed)
- `/harvest about [topic]` — Exploratory questions about a topic/project

## How It Works

**Harvest** = extracting structured context to enable something. Not just Q&A — it's about unlocking workflows or insights.

The AI analyzes context to dynamically generate questions. No hardcoded templates — questions are generated based on:

1. **The topic** — What are we harvesting about?
2. **The target** — Self, specific person, or broad exploration?
3. **Available context** — Neo4j data about sessions, quests, artifacts
4. **Question scope** — Narrow (decision-focused) vs wide (exploratory)

## Step 1: Parse Arguments

Parse `$ARGUMENTS` to extract:
- **target**: person name, `me`, or none (broad)
- **topic**: Everything after "about" (if present)

Examples:
- `/harvest` → target: none, topic: none (answer pending or start fresh)
- `/harvest me about priorities` → target: self, topic: "priorities"
- `/harvest oz about evaluation criteria` → target: "oz", topic: "evaluation criteria"
- `/harvest about tristero` → target: none, topic: "tristero"
- `/harvest about where egregore is heading` → target: none, topic: "where egregore is heading"

**Note:** No @ symbol required for person names.

## Step 2: Get Current User

```bash
git config user.name
```

Map to short name: "Oguzhan Yayla" → oz, "Cem Dagdelen" → cem, "Ali" → ali

## Step 3: Detect Target Type

**First, get all person names from Neo4j:**

```cypher
MATCH (p:Person) RETURN p.name AS name
```

**Then determine target type:**

1. If no arguments → check for pending harvests (Step 4)
2. If first word is "me" or "myself" → **SELF** target
3. If first word matches a person name (case-insensitive) → **PERSON** target
4. Otherwise → **EXPLORATORY** (no specific target)

## Step 4: Check for Pending Harvests (if no args)

If `/harvest` called with no arguments, first check for pending harvests:

```cypher
MATCH (qs:QuestionSet {status: 'pending'})-[:ASKED_TO]->(p:Person {name: $me})
MATCH (qs)-[:ASKED_BY]->(asker:Person)
RETURN qs.id AS setId, qs.topic AS topic, qs.created AS created, asker.name AS from
ORDER BY qs.created DESC
```

**If pending harvests exist:**
```
You have 2 pending harvest requests:

1. From cem about "evaluation criteria" (12 hours ago)
2. From ali about "MCP transport" (2 days ago)

Which would you like to respond to?
```

Use AskUserQuestion to let them select which set, then load and present those questions (see Step 8).

**If no pending harvests:** Proceed with self-reflection about general priorities (or ask what they want to explore).

## Step 5: Gather Context from Neo4j

Run queries in parallel based on target type:

**For SELF (`me`) or EXPLORATORY (no target):**
```cypher
// My recent sessions
MATCH (s:Session)-[:BY]->(p:Person {name: $me})
RETURN s.topic AS topic, s.summary AS summary, s.date AS date
ORDER BY s.date DESC LIMIT 5

// My active quests
MATCH (q:Quest {status: 'active'})-[:STARTED_BY|:CONTRIBUTED_BY*]->(p:Person {name: $me})
RETURN q.id AS quest, q.title AS title

// Recent artifacts I contributed
MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p:Person {name: $me})
RETURN a.title AS title, a.type AS type
ORDER BY a.created DESC LIMIT 5
```

**For PERSON target:**
```cypher
// Their recent sessions
MATCH (s:Session)-[:BY]->(p:Person {name: $target})
RETURN s.topic AS topic, s.summary AS summary, s.date AS date
ORDER BY s.date DESC LIMIT 5

// Their contributions
MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p:Person {name: $target})
RETURN a.title AS title, a.type AS type
ORDER BY a.created DESC LIMIT 5

// Quests they work on
MATCH (q:Quest {status: 'active'})-[:STARTED_BY|:CONTRIBUTED_BY*]->(p:Person {name: $target})
RETURN q.id AS quest, q.title AS title
```

**For EXPLORATORY with topic:**
```cypher
// Project context if topic matches a project
MATCH (proj:Project {name: $topic})
OPTIONAL MATCH (q:Quest)-[:RELATES_TO]->(proj)
RETURN proj.name AS project, collect(q.id) AS quests

// Recent org-wide activity
MATCH (s:Session)-[:BY]->(p:Person)
WHERE s.date >= date() - duration('P7D')
RETURN s.topic AS topic, p.name AS by, s.date AS date
ORDER BY s.date DESC LIMIT 5

// Active quests across org
MATCH (q:Quest {status: 'active'})
RETURN q.id AS quest, q.title AS title, q.question AS question
```

## Step 6: Generate Questions

Based on context, generate 1-4 questions.

### Determining Question Scope

**Narrow scope** (1-2 questions, single-select):
- Topic is a specific decision point
- Context shows a clear blocker or choice needed
- Example: "about which transport to use"

**Wide scope** (3-4 questions, some multi-select):
- Topic is exploratory or strategic
- No clear decision point
- Example: "about where egregore is heading"

### Question Generation Guidelines

**Headers** (max 12 chars):
- "Focus" — What to prioritize
- "Tradeoff" — Weighing options
- "Blocker" — What's in the way
- "Priority" — Ordering importance
- "Scope" — Breadth of exploration
- "Gap" — What's missing
- "Direction" — Strategic choices
- "Approach" — How to tackle something

**Options**:
- 2-4 options per question
- Draw from actual context (quest names, project names, recent work)
- "Other" is automatically provided — don't include it

**multiSelect**:
- `true` for brainstorming, scoping, or non-exclusive options
- `false` for decisions, priorities, single-choice

## Step 7: Route Based on Target Type

### CRITICAL: This step determines who sees the questions

---

### If target is SELF (`me`, `myself`) or EXPLORATORY (no target):

**Use AskUserQuestion** to present questions to the CURRENT user.

Show context summary first:
```
Analyzing your context...
- Active quests: benchmark-eval (3 artifacts), research-agent (1 artifact)
- Recent sessions: MCP transport decision, Neo4j setup
- Open threads: evaluation framework design
```

Then call AskUserQuestion with the generated questions. Capture answers immediately.

Optionally offer to save as artifact (see Step 9).

---

### If target is ANOTHER PERSON:

**DO NOT use AskUserQuestion.** The caller should NOT answer these questions.

Instead:

1. **Show context summary as text:**
```
Analyzing {target}'s context...
- Recent work: benchmark-eval quest, HELM framework review
- Contributions: temporal evaluation thought, HELM findings
- Projects: tristero
```

2. **Generate questions internally** (as data, not UI)

3. **Store in Neo4j** (Step 7a below)

4. **Show output as text only:**
```
┌─────────────────────────────────────────────────────────────┐
│ HARVEST QUEUED FOR {TARGET}                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Topic: {topic}                                              │
│                                                             │
│ Questions generated:                                        │
│ 1. "{question 1 text}" [{header}]                           │
│ 2. "{question 2 text}" [{header}]                           │
│ 3. "{question 3 text}" [{header}]                           │
│                                                             │
│ ✓ Stored in knowledge graph                                 │
│ ✓ {target} notified via Telegram                            │
│                                                             │
│ You'll be notified when {target} responds.                  │
└─────────────────────────────────────────────────────────────┘
```

5. **Notify via Telegram** (Step 7b below)

6. **Exit** — do NOT call AskUserQuestion

---

### Step 7a: Store Questions in Neo4j (for PERSON target only)

```cypher
MATCH (asker:Person {name: $me})
MATCH (target:Person {name: $targetPerson})
CREATE (qs:QuestionSet {
  id: $setId,
  topic: $topic,
  contextSummary: $contextSummary,
  created: datetime(),
  status: 'pending'
})
CREATE (qs)-[:ASKED_BY]->(asker)
CREATE (qs)-[:ASKED_TO]->(target)
WITH qs
UNWIND $questions AS q
CREATE (question:Question {
  id: q.id,
  text: q.text,
  header: q.header,
  options: q.optionsJson,
  multiSelect: q.multiSelect,
  answer: null
})
CREATE (question)-[:PART_OF]->(qs)
RETURN qs.id
```

Where:
- `$setId` = `YYYY-MM-DD-asker-to-target-topic-slug`
- `$questions` = array of question objects with id, text, header, options, multiSelect

### Step 7b: Notify via Telegram (for PERSON target only)

```bash
curl -X POST https://curve-labs-core-production.up.railway.app/notify \
  -H "Content-Type: application/json" \
  --data-raw '{"recipient":"$target","message":"...","type":"harvest"}'
```

**Message format:**
```
Hey {Target}, {asker} wants to harvest context about "{topic}"

{n} questions waiting for you. Run /harvest in Claude to respond.
```

## Step 8: Present Pending Harvests

When a user runs `/harvest` and has pending harvests:

1. Load the QuestionSet from Neo4j
2. Convert stored questions to AskUserQuestion format
3. **Present via AskUserQuestion UI** (THIS is where the target answers)
4. Store answers back to Neo4j

```cypher
// Load questions for a set
MATCH (q:Question)-[:PART_OF]->(qs:QuestionSet {id: $setId})
RETURN q.id AS id, q.text AS text, q.header AS header, q.options AS options, q.multiSelect AS multiSelect
ORDER BY q.id
```

After user answers via AskUserQuestion:

```cypher
// Store answers
MATCH (q:Question {id: $questionId})
SET q.answer = $answer, q.answeredAt = datetime()

// Check if all questions answered
MATCH (qs:QuestionSet {id: $setId})
OPTIONAL MATCH (q:Question)-[:PART_OF]->(qs) WHERE q.answer IS NULL
WITH qs, count(q) AS unanswered
SET qs.status = CASE WHEN unanswered = 0 THEN 'answered' ELSE 'partial' END
RETURN qs.status
```

Then notify the asker:

```bash
curl -X POST https://curve-labs-core-production.up.railway.app/notify \
  -H "Content-Type: application/json" \
  --data-raw '{"recipient":"$asker","message":"...","type":"harvest-response"}'
```

**Message format:**
```
Hey {Asker}, {target} responded to your harvest about "{topic}"

Run /activity to see their answers.
```

## Step 9: Self-Reflection Capture

For self-targeted harvests, answers can optionally be saved as artifacts:

After answering self-reflection questions:
```
Your responses captured.

Would you like to save this as an artifact?
```

If yes, create artifact via `/add` flow (thought type, linked to relevant quests).

## Error Handling

**Person not found:**
```
I don't recognize "{name}" as a person in Egregore.

Known people: oz, ali, cem

Check the spelling, or they might need to be added via a session or handoff first.
```

**Neo4j unavailable:**
```
Knowledge graph unavailable. Generating questions without context...

[Generate generic questions about the topic]
```

**No context available for person:**
```
I don't have much context about {name}'s work on "{topic}".

Generating exploratory questions instead...
```

## Output Examples

### Self-harvest (uses AskUserQuestion)
```
> /harvest me about my priorities

Analyzing your context...
- Active quests: benchmark-eval, research-agent
- Recent sessions: Neo4j adoption, MCP transport
- Open: 1 handoff pending

[AskUserQuestion appears with context-aware questions]
```

### Person-targeted harvest (NO AskUserQuestion for caller)
```
> /harvest oz about the benchmark evaluation approach

Analyzing Oz's context...
- Recent work: benchmark-eval quest, HELM review
- Contributions: temporal evaluation thought

Generating questions for Oz...

┌─────────────────────────────────────────────────────────────┐
│ HARVEST QUEUED FOR OZ                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Topic: benchmark evaluation approach                        │
│                                                             │
│ Questions generated:                                        │
│ 1. "What criteria matter most for evaluating dynamic        │
│    ontologies?" [Focus]                                     │
│ 2. "How should we weight temporal vs structural metrics?"   │
│    [Tradeoff]                                               │
│                                                             │
│ ✓ Stored in knowledge graph                                 │
│ ✓ Oz notified via Telegram                                  │
│                                                             │
│ You'll be notified when Oz responds.                        │
└─────────────────────────────────────────────────────────────┘
```

### Answering pending harvest (target sees AskUserQuestion)
```
> /harvest

You have 2 pending harvest requests:

1. From cem about "evaluation criteria" (12 hours ago)
2. From ali about "MCP transport" (2 days ago)

[AskUserQuestion: Which would you like to respond to?]

> evaluation criteria

[AskUserQuestion: Questions from cem appear for YOU to answer]
```

### Wide exploration (uses AskUserQuestion)
```
> /harvest about egregore

Analyzing organizational context...
- 3 active projects, 4 active quests
- Recent decisions: MCP transport, Neo4j

[AskUserQuestion with exploratory questions, multiSelect enabled]
```

## Rules

- **Generate questions dynamically** — Never use hardcoded templates
- **Reference actual context** — Questions should mention real quests, projects, recent work
- **Appropriate scope** — Narrow for decisions, wide for exploration
- **CRITICAL ROUTING** — AskUserQuestion ONLY for self/exploratory harvests, NEVER for person-targeted
- **Person-targeted = async** — Store in Neo4j, notify via Telegram, exit without UI
- **Notify on async** — Telegram for person-targeted questions and answers
- **Link to knowledge graph** — All questions/answers stored in Neo4j
