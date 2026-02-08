Ask questions — AI-generated, context-aware, routed to self or others. Harvest-first for person-targeted: check the graph before bothering people.

Arguments: $ARGUMENTS (Optional: [person] about [topic], or empty to answer pending)

## Usage

- `/ask` — Answer pending questions (if any), or start reflection
- `/ask me about [topic]` — Self-reflection with AI-generated questions
- `/ask [person] about [topic]` — Harvest context first, then queue questions if needed
- `/ask about [topic]` — Exploratory questions about a topic/project

## How It Works

The AI analyzes context to dynamically generate questions. No hardcoded templates — questions are generated based on:

1. **The topic** — What are we asking about?
2. **The target** — Self, specific person, or broad exploration?
3. **Available context** — Neo4j data about sessions, quests, artifacts
4. **Question scope** — Narrow (decision-focused) vs wide (exploratory)

**Key principle for person-targeted:** Don't immediately generate questions for the target. First harvest the graph to see if existing context already answers the sender's question. Only queue async questions when the graph can't answer.

## Step 1: Parse Arguments

Parse `$ARGUMENTS` to extract:
- **target**: person name, `me`, or none (broad)
- **topic**: Everything after "about" (if present)

Both `@person` and `person` work — strip the `@` if present.

Examples:
- `/ask` → target: none, topic: none (answer pending or start fresh)
- `/ask me about priorities` → target: self, topic: "priorities"
- `/ask oz about evaluation criteria` → target: "oz", topic: "evaluation criteria"
- `/ask @oz about evaluation criteria` → target: "oz", topic: "evaluation criteria"
- `/ask about tristero` → target: none, topic: "tristero"
- `/ask about where egregore is heading` → target: none, topic: "where egregore is heading"

## Step 2: Get Current User

```bash
git config user.name
```

Map to short name: "Oguzhan Yayla" → oz, "Cem Dagdelen" → cem, "Ali" → ali

## Step 3: Detect Target Type

**First, get all person names from Neo4j:**

```bash
bash bin/graph.sh query "MATCH (p:Person) RETURN p.name AS name"
```

**Then determine target type:**

1. If no arguments → check for pending questions (Step 4)
2. If first word is "me" or "myself" → **SELF** target
3. If first word (with `@` stripped) matches a person name (case-insensitive) → **PERSON** target
4. Otherwise → **EXPLORATORY** (no specific target)

---

## Step 4: Check for Pending Questions (if no args)

If `/ask` called with no arguments, first check for pending questions:

```bash
bash bin/graph.sh query "MATCH (qs:QuestionSet {status: 'pending'})-[:ASKED_TO]->(p:Person {name: '$me'}) MATCH (qs)-[:ASKED_BY]->(asker:Person) RETURN qs.id AS setId, qs.topic AS topic, qs.created AS created, asker.name AS from ORDER BY qs.created DESC"
```

**If pending questions exist:**
```
You have 2 pending question sets:

1. From cem about "evaluation criteria" (12 hours ago)
2. From ali about "MCP transport" (2 days ago)

Which would you like to respond to?
```

Use AskUserQuestion to let them select which set, then load and present those questions (see Step 9).

**If no pending questions:** Proceed with self-reflection about general priorities (or ask what they want to explore).

---

## Step 5: Gather Context from Neo4j

Run queries via `bash bin/graph.sh query "..."` based on target type.

### For SELF or EXPLORATORY:

```bash
# My recent sessions
bash bin/graph.sh query "MATCH (s:Session)-[:BY]->(p:Person {name: '$me'}) RETURN s.topic AS topic, s.summary AS summary, s.date AS date ORDER BY s.date DESC LIMIT 5"

# My active quests
bash bin/graph.sh query "MATCH (q:Quest {status: 'active'})-[:STARTED_BY|:CONTRIBUTED_BY*]->(p:Person {name: '$me'}) RETURN q.id AS quest, q.title AS title"

# Recent artifacts I contributed
bash bin/graph.sh query "MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p:Person {name: '$me'}) RETURN a.title AS title, a.type AS type ORDER BY a.created DESC LIMIT 5"
```

For EXPLORATORY with a topic, also query:
```bash
# Project context if topic matches a project
bash bin/graph.sh query "MATCH (proj:Project) WHERE toLower(proj.name) CONTAINS toLower('$topic') OPTIONAL MATCH (q:Quest)-[:RELATES_TO]->(proj) RETURN proj.name AS project, collect(q.id) AS quests"

# Recent org-wide activity
bash bin/graph.sh query "MATCH (s:Session)-[:BY]->(p:Person) WHERE s.date >= date() - duration('P7D') RETURN s.topic AS topic, p.name AS by, s.date AS date ORDER BY s.date DESC LIMIT 5"

# Active quests across org
bash bin/graph.sh query "MATCH (q:Quest {status: 'active'}) RETURN q.id AS quest, q.title AS title, q.question AS question"
```

### For PERSON target — harvest broadly:

Gather context about the **topic**, not just the target person. The goal is to see if the graph already has the answer.

```bash
# Everything the graph knows about this topic (sessions mentioning it)
bash bin/graph.sh query "MATCH (s:Session) WHERE toLower(s.topic) CONTAINS toLower('$topic') OR toLower(s.summary) CONTAINS toLower('$topic') MATCH (s)-[:BY]->(p:Person) RETURN s.topic AS topic, s.summary AS summary, s.date AS date, p.name AS by ORDER BY s.date DESC LIMIT 10"

# Artifacts related to the topic
bash bin/graph.sh query "MATCH (a:Artifact) WHERE toLower(a.title) CONTAINS toLower('$topic') OR toLower(a.type) CONTAINS toLower('$topic') OPTIONAL MATCH (a)-[:CONTRIBUTED_BY]->(p:Person) RETURN a.title AS title, a.type AS type, p.name AS by ORDER BY a.created DESC LIMIT 5"

# Quests related to the topic
bash bin/graph.sh query "MATCH (q:Quest) WHERE toLower(q.title) CONTAINS toLower('$topic') OR toLower(q.id) CONTAINS toLower('$topic') RETURN q.id AS quest, q.title AS title, q.question AS question, q.status AS status"

# The target person's recent sessions (for question context later)
bash bin/graph.sh query "MATCH (s:Session)-[:BY]->(p:Person {name: '$target'}) RETURN s.topic AS topic, s.summary AS summary, s.date AS date ORDER BY s.date DESC LIMIT 5"

# The target person's contributions
bash bin/graph.sh query "MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p:Person {name: '$target'}) RETURN a.title AS title, a.type AS type ORDER BY a.created DESC LIMIT 5"
```

---

## Step 6: Route Based on Target Type

### If SELF or EXPLORATORY → go to Step 7
### If PERSON → go to Step 8

---

## Step 7: Self / Exploratory Mode

Use AskUserQuestion to present questions to the CURRENT user.

### Show context summary first:

```
Analyzing your context...
- Active quests: benchmark-eval (3 artifacts), research-agent (1 artifact)
- Recent sessions: MCP transport decision, Neo4j setup
- Open threads: evaluation framework design
```

### Generate 1-4 questions using AskUserQuestion

**Determining scope:**

**Narrow scope** (1-2 questions, single-select):
- Topic is a specific decision point
- Context shows a clear blocker or choice needed
- Example: "about which transport to use"

**Wide scope** (3-4 questions, some multi-select):
- Topic is exploratory or strategic
- No clear decision point
- Example: "about where egregore is heading"

### Question generation guidelines

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

### After answers: offer /reflect

After the user answers self/exploratory questions:

```
Your responses captured.

Save as a reflection? I'll store it in the knowledge graph via /reflect.
```

If yes, route to `/reflect` flow (thought type, linked to relevant quests).

---

## Step 8: Person-Targeted Mode (Harvest-First)

This is the core design change. Do NOT immediately generate questions for the target. Follow this sequence:

### Step 8a: Present harvested context to the SENDER

Analyze what the graph returned in Step 5. Synthesize it into a useful summary for the sender.

```
┌────────────────────────────────────────────────────────────────────────┐
│  ? ASK                                                                │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Topic: evaluation criteria                                            │
│  Target: Oz                                                            │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ WHAT THE GRAPH KNOWS                                           │    │
│  │                                                                │    │
│  │ ◦ Feb 07  oz: Discussed HELM benchmarks in session             │    │
│  │ ◦ Feb 06  cem: Benchmark-eval quest has 3 artifacts            │    │
│  │ ◦ Artifact: "temporal evaluation thought" by oz                │    │
│  │ ◦ Quest: benchmark-eval (active, 2 contributors)              │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  Does this answer your question, or should I ask Oz directly?          │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

If the graph has NO relevant context, skip straight to Step 8c with a note:

```
The graph doesn't have much about "{topic}". Let me ask {target} directly.
```

### Step 8b: Let sender decide

Use AskUserQuestion for the SENDER (current user):

- question: "Does this answer your question, or should I ask {target} directly?"
- header: "Next"
- options:
  - label: "This is enough"
    description: "The graph context answers my question"
  - label: "Ask {target} directly"
    description: "I need their specific input"
- multiSelect: false

**If "This is enough"** → end. Optionally offer to save as reflection.

**If "Ask directly"** → proceed to Step 8c.

### Step 8c: Clarify what specifically to ask

Use AskUserQuestion for the SENDER to sharpen the question. Generate options based on the gap analysis — what does the graph NOT know about this topic?

- question: "What specifically should I ask {target}?"
- header: "Focus"
- options: (generated from gap analysis)
  - Things the graph is silent on
  - Opinions/preferences that only the person would know
  - Decisions that haven't been recorded
- multiSelect: true (sender might want to ask about multiple gaps)

### Step 8d: Generate targeted questions for the target

Based on the sender's clarified intent from Step 8c, generate 1-4 focused questions. These should be much higher quality than generic questions because:
- We know what the graph already has (no redundant questions)
- We know what the sender specifically wants to learn
- We can reference actual context in the question framing

### Step 8e: Store in Neo4j

```bash
bash bin/graph.sh query "MATCH (asker:Person {name: '$me'}) MATCH (target:Person {name: '$target'}) CREATE (qs:QuestionSet {id: '$setId', topic: '$topic', contextSummary: '$contextSummary', created: datetime(), status: 'pending'}) CREATE (qs)-[:ASKED_BY]->(asker) CREATE (qs)-[:ASKED_TO]->(target) WITH qs UNWIND \$questions AS q CREATE (question:Question {id: q.id, text: q.text, header: q.header, options: q.optionsJson, multiSelect: q.multiSelect, answer: null}) CREATE (question)-[:PART_OF]->(qs) RETURN qs.id"
```

Where:
- `$setId` = `YYYY-MM-DD-asker-to-target-topic-slug`
- `$questions` = array of question objects with id, text, header, options, multiSelect

For the UNWIND with parameters, use `bash bin/graph.sh query "..." '{"questions": [...]}'` format.

### Step 8f: Notify via Telegram

```bash
bash bin/notify.sh send "$target" "Hey $Target, $me has questions about \"$topic\"\n\n$n questions waiting for you. Run /ask in Claude to answer."
```

### Step 8g: Show confirmation TUI

```
┌────────────────────────────────────────────────────────────────────────┐
│  ? QUESTIONS QUEUED                                                    │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  To: Oz                                                                │
│  Topic: benchmark evaluation approach                                  │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ 1. "What criteria matter most?" [Focus]                        │    │
│  │ 2. "How should we weight temporal?" [Tradeoff]                 │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  ✓ Stored in knowledge graph                                           │
│  ✓ Oz notified via Telegram                                            │
│                                                                        │
│  You'll be notified when Oz responds.                                  │
└────────────────────────────────────────────────────────────────────────┘
```

**Exit. Do NOT call AskUserQuestion after this point.**

---

## Step 9: Present Pending Questions

When a user runs `/ask` and has pending questions:

1. Load the QuestionSet from Neo4j
2. Convert stored questions to AskUserQuestion format
3. **Present via AskUserQuestion UI** (this is where the target answers)
4. Store answers back to Neo4j

```bash
# Load questions for a set
bash bin/graph.sh query "MATCH (q:Question)-[:PART_OF]->(qs:QuestionSet {id: '$setId'}) RETURN q.id AS id, q.text AS text, q.header AS header, q.options AS options, q.multiSelect AS multiSelect ORDER BY q.id"
```

After user answers via AskUserQuestion:

```bash
# Store each answer
bash bin/graph.sh query "MATCH (q:Question {id: '$questionId'}) SET q.answer = '$answer', q.answeredAt = datetime()"

# Check if all questions answered
bash bin/graph.sh query "MATCH (qs:QuestionSet {id: '$setId'}) OPTIONAL MATCH (q:Question)-[:PART_OF]->(qs) WHERE q.answer IS NULL WITH qs, count(q) AS unanswered SET qs.status = CASE WHEN unanswered = 0 THEN 'answered' ELSE 'partial' END RETURN qs.status"
```

Then notify the asker:

```bash
bash bin/notify.sh send "$asker" "Hey $Asker, $target answered your questions about \"$topic\"\n\nRun /activity to see their answers."
```

---

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

For person-targeted, this just means skip Step 8a/8b and go straight to 8c:
```
The graph doesn't have much about "{topic}". Let me ask {target} directly.
```

---

## Output Examples

### Self-reflection (uses AskUserQuestion)
```
> /ask me about my priorities

Analyzing your context...
- Active quests: benchmark-eval, research-agent
- Recent sessions: Neo4j adoption, MCP transport
- Open: 1 handoff pending

[AskUserQuestion appears with context-aware questions]

[After answers]

Your responses captured.

Save as a reflection? I'll store it in the knowledge graph via /reflect.
```

### Person-targeted with graph context (harvest-first)
```
> /ask oz about the benchmark evaluation approach

┌────────────────────────────────────────────────────────────────────────┐
│  ? ASK                                                                │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Topic: benchmark evaluation approach                                  │
│  Target: Oz                                                            │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ WHAT THE GRAPH KNOWS                                           │    │
│  │                                                                │    │
│  │ ◦ Feb 07  oz: Discussed HELM benchmarks in session             │    │
│  │ ◦ Artifact: "temporal evaluation thought" by oz                │    │
│  │ ◦ Quest: benchmark-eval (active)                               │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  Does this answer your question, or should I ask Oz directly?          │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘

[AskUserQuestion: Does this answer your question?]

> Ask Oz directly

[AskUserQuestion: What specifically should I ask Oz?]

> His opinion on our benchmark choice, Whether he's seen alternatives

Generating targeted questions for Oz...

┌────────────────────────────────────────────────────────────────────────┐
│  ? QUESTIONS QUEUED                                                    │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  To: Oz                                                                │
│  Topic: benchmark evaluation approach                                  │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │ 1. "What's your take on HELM as our primary benchmark?"        │    │
│  │    [Approach]                                                  │    │
│  │ 2. "Are there alternatives to HELM we should consider?"        │    │
│  │    [Gap]                                                       │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  ✓ Stored in knowledge graph                                           │
│  ✓ Oz notified via Telegram                                            │
│                                                                        │
│  You'll be notified when Oz responds.                                  │
└────────────────────────────────────────────────────────────────────────┘
```

### Person-targeted without graph context (skip to clarify)
```
> /ask oz about hiring plans

The graph doesn't have much about "hiring plans". Let me ask Oz directly.

[AskUserQuestion: What specifically should I ask Oz?]
```

### Answering pending (target sees AskUserQuestion)
```
> /ask

You have 2 pending question sets:

1. From cem about "evaluation criteria" (12 hours ago)
2. From ali about "MCP transport" (2 days ago)

[AskUserQuestion: Which would you like to respond to?]

> evaluation criteria

[AskUserQuestion: Questions from cem appear for YOU to answer]
```

### Wide exploration (uses AskUserQuestion)
```
> /ask about egregore

Analyzing organizational context...
- 3 active projects, 4 active quests
- Recent decisions: MCP transport, Neo4j

[AskUserQuestion with exploratory questions, multiSelect enabled]

[After answers]

Your responses captured.

Save as a reflection? I'll store it in the knowledge graph via /reflect.
```

---

## Rules

- **Generate questions dynamically** — Never use hardcoded templates
- **Reference actual context** — Questions should mention real quests, projects, recent work
- **Appropriate scope** — Narrow for decisions, wide for exploration
- **Harvest-first for person-targeted** — Always check the graph before generating async questions
- **AskUserQuestion for sender clarification** — In person-targeted mode, use AskUserQuestion to help the sender clarify (Steps 8b, 8c), never to present questions for the target
- **AskUserQuestion for self/exploratory** — Present generated questions directly to the current user
- **AskUserQuestion for pending answers** — When a target runs `/ask` and has pending questions, present them via AskUserQuestion
- **Person-targeted = async** — Store in Neo4j, notify via Telegram, exit without presenting target's questions
- **All Neo4j via bin/graph.sh** — Never use MCP, never construct curl calls to Neo4j directly
- **All notifications via bin/notify.sh** — Never curl to APIs directly
- **No @ required** — Both `oz` and `@oz` work for person names
- **Offer /reflect after self/exploratory** — Answers are valuable, help the user crystallize them
