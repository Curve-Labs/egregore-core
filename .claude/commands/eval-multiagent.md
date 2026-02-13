Multi-agent pipeline evaluation. Run configs, tournament-compare outputs, generate reports.

Arguments: $ARGUMENTS

## Agent Completion Handling

All eval sub-agents run in background mode (`run_in_background: true`). Poll for completion via `TaskOutput` with `block: true`. This prevents agent completions from injecting into the conversation as stale notifications.

If you receive late notifications from previously completed agents, **ignore them silently**. Do NOT respond to stale notifications. Do NOT ask about /save after each one. The eval pipeline handles save as a single step at the end — after the final TUI display, never mid-pipeline.

## Routing

Parse `$ARGUMENTS` to extract subcommand, pipeline-id, and flags:
- `run <pipeline-id> [--configs A,B,C] [--quick]` → Run subcommand
- `tournament <pipeline-id> [--consistency-check] [--tournament-only] [--judge-model opus|sonnet] [--quick]` → Tournament subcommand
- `report <pipeline-id>` → Report subcommand

Flags:
- `--quick` — Use only the `quick_configs` subset from the eval spec (fewer configs, ~85% cost reduction)
- `--tournament-only` — Skip the run phase; reuse existing config outputs and go straight to match generation + judging
- `--judge-model <model>` — Override judge model (default: opus). Use `sonnet` for cheaper iteration.

If no subcommand or unrecognized: show usage:
```
Usage:
  /eval multiagent run <pipeline-id> [--configs A,B,C] [--quick]
  /eval multiagent tournament <pipeline-id> [--consistency-check] [--tournament-only] [--judge-model opus|sonnet]
  /eval multiagent report <pipeline-id>
```

---

## Subcommand: `run`

Execute each config against each input. Store outputs + cost data.

### Step 0: Parse and load spec

Read the eval spec from `eval-specs/{pipeline-id}.md`. Parse frontmatter (YAML between `---` lines) and body.

Extract:
- **Slots**: Parse the `## Slots` table — slot name, role, options, default
- **Input Resolution**: Parse the `## Input Resolution` table — type → shell command with `{id}` placeholder
- **Configs**: Parse each `### <config-name>` under `## Configs` — extract per-slot assignments. Each slot value is either `null` (skip agent) or `{model, prompt_variant?, params?}`. Only `model` is required. If the spec uses the short form (`slot: model_name`), treat it as `{model: model_name}`.
- **Prompt Variants**: Parse `## Prompt Variants` if present — named prompt overrides per slot. Configs reference these by name.
- **Input corpus**: Parse `## Input Corpus` — each line is `<type>:<id>`
- **Dimensions**: Parse `## Eval Dimensions` — numbered list with `**name**`: description

If `--configs` flag is provided, filter to only those config names (comma-separated). If `--quick` flag is provided, use only the configs listed in the spec's `quick_configs` field. Otherwise use all configs.

### Step 1: Resolve inputs

For each input in the corpus, look up the input type in the spec's `## Input Resolution` table to find the shell command. Substitute `{id}` with the actual input ID.

```bash
# Example: for "meeting:7df47eba-..." with resolution "bash bin/granola.sh get {id}"
bash bin/granola.sh get 7df47eba-...
```

If no Input Resolution table exists in the spec, fall back to type-based defaults:
- `meeting` → `bash bin/granola.sh get {id}`
- `document` → read the file at `{id}`
- `query` → use `{id}` as inline text

Parse the output. Extract the fields needed for each slot based on the pipeline architecture.

### Step 2: Execute configs

Create output directory:
```bash
mkdir -p .egregore/eval-runs/{pipeline-id}/run-$(date +%Y-%m-%d)-{seq}
```

Where `{seq}` is a 3-digit zero-padded sequence number (001, 002, ...) based on existing run directories for today.

For each **config × input** combination:

Create config output directory:
```bash
mkdir -p .egregore/eval-runs/{pipeline-id}/run-{date}-{seq}/config-{config-name}
```

<!-- ═══ PIPELINE-SPECIFIC: Execution logic ═══ -->
<!-- This section is specific to the multiagent eval type (fan-out/fan-in topology). -->
<!-- When adding new eval types (eval-prompt, eval-retrieval), this is what differs. -->
<!-- The tournament engine, Elo computation, and reporting below are SHARED infrastructure. -->

**Decompose pipeline into sub-agents.** Every slot from the spec becomes a spawned Task agent with the config's model (and optional prompt_variant/params). This ensures fair comparison — model tier and prompt strategy actually vary per slot.

Read slot names, roles, and config assignments dynamically from the eval spec. Do NOT hardcode slot names — the spec defines them.

For slots set to `null` in a config, skip the sub-agent entirely. Pass an empty object (`{}`) to downstream slots that depend on its output.

**Sub-agent spawning**: Use the Task tool with:
- `subagent_type: "general-purpose"`
- `model`: from the config's slot assignment (e.g., `{model: haiku}` → `"haiku"`)
- `run_in_background: true` — ALL eval agents run in background mode

Determine execution order from the `## Architecture` line in the spec. Slots listed with `→` between them run sequentially (each feeds the next). Slots at the same level can run in parallel. The last slot (typically a compositor/synthesis) waits for all others.

**Poll for completion**: After spawning background agents, use `TaskOutput` with `block: true` to wait for each agent. Parse the result from the output.

**Show progress inline** as each agent completes:
```
Running config {config-name} on {input-id}...
  [{n}/{total}] {slot_name} ({model}) ✓ ({latency}s, {tokens} tokens, ${cost})
  [{n}/{total}] {slot_name} ({model}) ... (running)
```

**Parallel synthesis**: Since analyst outputs are deduplicated across configs, all synthesis runs for a given input set are independent. Spawn synthesis agents for multiple configs in parallel (batch up to 7 at a time to stay within reasonable parallelism limits). Show cumulative cost:
```
Running synthesis (14 agents)...
  [{n}/14] config-{name} ✓ · ${cumulative_cost} spent so far
```

**For each slot sub-agent**, use this prompt template (substitute actual data):

```
You are the {slot_name} agent in a {pipeline_title} pipeline.

## Your Role
{slot_role_description from Slots table — OR prompt_variant text if config specifies one}

## Input
{actual input data for this slot — determined by pipeline architecture}

## Instructions
Analyze the input according to your role. Return TWO sections:

### Structured Output
A JSON object with your analysis. Include all relevant fields for your role.

### Raw Notes
Free-form reasoning, observations, and analysis that didn't fit the structured output.
These notes are valuable — they capture nuance that structured fields miss.

Return the structured JSON first (wrapped in ```json blocks), then the raw notes.
```

If the config specifies a `prompt_variant` for this slot, use the variant text from the spec's `## Prompt Variants` section instead of the default role description.

**Capture metrics** for each sub-agent:
- Token counts (input + output) from the Task tool response (actual, not estimated)
- Wall-clock latency (timestamp before and after Task call)
- Actual cost computed from token counts using model pricing:
  - Opus: $15/M input, $75/M output
  - Sonnet: $3/M input, $15/M output
  - Haiku: $0.80/M input, $4/M output

**Write outputs** for each config:

`output.json` — slot keys come from the spec, not hardcoded:
```json
{
  "pipeline_id": "{pipeline-id}",
  "config": "{config-name}",
  "input": "{input-id}",
  "run_date": "{ISO datetime}",
  "slots": {
    "{slot_name}": {"output": {...}, "model": "...", "prompt_variant": "default", "tokens_in": N, "tokens_out": N, "cost_usd": N, "latency_ms": N},
    "...": "one entry per slot from the spec"
  },
  "total_tokens": N,
  "total_cost_usd": N,
  "total_latency_ms": N
}
```

`_raw_notes.md` — one section per slot, dynamically from spec:
```markdown
# Raw Notes — {config-name} on {input-id}

## {Slot Name} Agent ({model})
{raw notes from this agent}

(repeat for each slot in the spec)
```

`meta.json`:
```json
{
  "config": "{config-name}",
  "input": "{input-id}",
  "run_date": "{ISO datetime}",
  "per_slot": {
    "{slot_name}": {"model": "...", "prompt_variant": "default", "tokens_in": N, "tokens_out": N, "cost_usd": N, "latency_ms": N},
    "...": "one entry per slot"
  },
  "total_tokens": N,
  "total_cost_usd": N,
  "total_latency_ms": N
}
```

### Step 3: Record in graph

For each config × input run:
```bash
bash bin/eval-op.sh create-run "{runId}" "{pipelineId}" "{config}" "{input}" "{outputPath}" "{totalTokens}" "{cost}" "{latency}"
```

Where `runId` is `{pipeline-id}-{config}-{input-short}-{date}-{seq}`.

### Step 4: Summary TUI

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⊕ EVAL RUN                                      {user} · {date}    │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Pipeline: {pipeline-id} · {N} configs × {M} inputs                 │
│                                                                      │
│  CONFIG            TOKENS    COST      LATENCY                       │
│  {config-name}     {N}       ${X.XX}   {N}ms                        │
│  {config-name}     {N}       ${X.XX}   {N}ms                        │
│  ...                                                                 │
│                                                                      │
│  Outputs: .egregore/eval-runs/{pipeline-id}/run-{date}-{seq}/       │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  /eval multiagent tournament {pipeline-id}                           │
└──────────────────────────────────────────────────────────────────────┘
```

---

<!-- ═══ SHARED INFRASTRUCTURE: Tournament, Elo, Reporting ═══ -->
<!-- Everything below this line is eval-type-agnostic. It operates on outputs -->
<!-- (output.json + _raw_notes.md) and dimensions (from the spec). When adding -->
<!-- a new eval type, reuse this logic as-is — only the judge prompt template -->
<!-- is topology-specific (fan-out/fan-in judges compare merged outputs; -->
<!-- sequential chain judges might compare intermediate steps; iterative judges -->
<!-- might evaluate convergence rate). Define judge prompts per eval type. -->

## Subcommand: `tournament`

Blind pairwise comparison with Elo scoring.

**Flags**:
- `--tournament-only` — Skip the run phase. Reuse existing config outputs from the most recent run directory. Go straight to match generation + judging.
- `--judge-model <model>` — Override judge model. Default: `opus`. Use `sonnet` for cheaper iteration.
- `--quick` — Use `quick_configs` from spec to limit which configs enter the tournament.

### Step 0: Load data

```bash
bash bin/eval-op.sh get-runs {pipeline-id}
```

Read the eval spec for dimensions. If the spec has a `dimensions_skip` field, exclude those dimensions from judging.

If `--quick` flag, filter configs to only those in the spec's `quick_configs` list.

Load output files from the most recent run directory:
```bash
ls -d .egregore/eval-runs/{pipeline-id}/run-*/config-*/output.json
```

Group outputs by input — each input should have one output per config.

Read `_raw_notes.md` for each config×input (the judge compares these alongside structured output).

**If `--tournament-only`**: Verify that config output files exist from a previous run. If any are missing, list them and abort:
```
Missing outputs — run /eval multiagent run {pipeline-id} first:
  config-deep/output_m1.json
  config-deep/output_m2.json
```

### Step 1: Consistency check (if `--consistency-check` flag)

Before the real tournament, verify pipeline variance is low enough to trust results.

1. Pick 1 config (first in spec, typically baseline) and 1 input (first in corpus)
2. Check if two runs exist for this config×input. If not, tell the user:
   ```
   Consistency check needs two runs of the same config on the same input.
   Run: /eval multiagent run {pipeline-id} --configs {config}
   twice on the same input, then re-run the tournament.
   ```
3. Have the judge compare the two outputs (use bundled mode — one call, all dimensions)
4. Count tie rate across dimensions. Report:
   ```
   Consistency check: {tie_rate}% tie rate across {N} dimensions.
   ```
   - If tie rate >= 70%: `✓ Pipeline variance is low. Elo differences are meaningful.`
   - If tie rate < 70%: `⚠ Pipeline variance is high ({tie_rate}% ties). Small Elo differences may be noise.`

Store the result in the tournament output directory. Continue to the real tournament regardless.

### Step 2: Mode selection

Use AskUserQuestion:

```
question: "Tournament mode? Full evaluates each dimension separately (more precise, {N}x more judge calls). Quick bundles all dimensions per comparison (cheaper, faster)."
header: "Mode"
options:
  - label: "Quick (Recommended)"
    description: "One judge call per pair — all {N} dimensions evaluated together. ~{estimate} judge calls total."
  - label: "Full"
    description: "One judge call per pair per dimension. ~{estimate} judge calls total."
  - label: "Custom"
    description: "Select specific dimensions to evaluate individually."
```

If Custom: follow up with a multiSelect AskUserQuestion listing all dimensions.

### Step 3: Generate match pairs

Compute C(N,2) config pairs × inputs. For Quick mode: 1 judge call per pair×input. For Full mode: 1 judge call per pair×input×dimension.

**Randomize A/B assignment** per match. For each pair, randomly assign which config is "Output A" and which is "Output B". Log the assignments for position bias analysis.

Create tournament output directory:
```bash
mkdir -p .egregore/eval-runs/{pipeline-id}/run-{date}-{seq}/tournament
```

### Step 4: Judge each match

For each match, spawn a **judge sub-agent** using the Task tool:
- `subagent_type: "general-purpose"`
- `model`: from `--judge-model` flag, or `"opus"` (default)
- `run_in_background: true` — ALL judge agents run in background mode

**Batch judges**: Spawn up to 6 judge agents in parallel. Poll for completion via `TaskOutput` with `block: true`. Show progress with running cost total:
```
Running tournament judges ({judge_model})...
  [{n}/{total}] {configA} vs {configB} on {input} → {winner} ({confidence}) · ${cumulative_cost}
```

**Quick mode (bundled)** — one call evaluates ALL dimensions:

Sub-agent prompt:
```
You are evaluating two outputs from the same pipeline processing the same input.
You do not know which configuration produced which output.

## Evaluation Dimensions
{for each dimension: "N. dimension_name: dimension_description"}

## Input Summary
{brief summary of the input — meeting title, date, attendees, topic count}

## Output A

### Structured Output
{output_a structured JSON from output.json, slots section}

### Raw Notes
{output_a _raw_notes.md content}

## Output B

### Structured Output
{output_b structured JSON from output.json, slots section}

### Raw Notes
{output_b _raw_notes.md content}

## Instructions
Compare Output A and Output B on EACH dimension listed above.

For each dimension, provide:
- winner: "A", "B", or "tie"
- confidence: "strong", "moderate", or "weak"
- reasoning: one sentence explaining why

Then provide an overall verdict.

Return ONLY this JSON (no other text):
{
  "dimensions": {
    "dimension_name": {"winner": "A"|"B"|"tie", "confidence": "strong"|"moderate"|"weak", "reasoning": "..."},
    ...
  },
  "overall": {"winner": "A"|"B"|"tie", "confidence": "strong"|"moderate"|"weak", "reasoning": "..."}
}
```

**Full mode (per-dimension)** — one call per dimension:

Sub-agent prompt:
```
You are evaluating two outputs from the same pipeline processing the same input.
You do not know which configuration produced which output.

## Evaluation Dimension
{dimension_name}: {dimension_description}

## Input Summary
{brief summary of the input}

## Output A

### Structured Output
{output_a structured JSON}

### Raw Notes
{output_a _raw_notes.md content}

## Output B

### Structured Output
{output_b structured JSON}

### Raw Notes
{output_b _raw_notes.md content}

## Instructions
Compare Output A and Output B on the dimension above.
1. Analyze each output's strengths and weaknesses for this dimension.
2. Declare winner: "A", "B", or "tie".
3. Confidence: "strong", "moderate", or "weak".

Return ONLY this JSON (no other text):
{"analysis_a": "...", "analysis_b": "...", "winner": "A"|"B"|"tie", "confidence": "strong"|"moderate"|"weak", "reasoning": "..."}
```

**Parse judge response**: Extract JSON from the sub-agent's response. Map "A"/"B" back to actual config names using the randomization log.

**Record each match** in Neo4j:
```bash
bash bin/eval-op.sh create-match "{matchId}" "{pipelineId}" "{configA}" "{configB}" "{input}" "{dimension}" "{winner}" "{confidence}" "{reasoning}" "{judgeModel}"
```

In bundled mode, create one match record per dimension from the single judge response.

Show progress inline:
```
Judging: {configA} vs {configB} on {input}... {dimension} → {winner} ({confidence})
```

### Step 5: Elo calculation

Standard Elo with confidence weighting (K=32):
- All configs start at 1500
- K factor modulated by confidence: strong = K×1.0, moderate = K×0.7, weak = K×0.4
- Ties: both players get 0.5 expected score
- Compute **per-dimension Elo** AND **overall Elo** (from overall verdicts or aggregated dimension results)
- Compute **Elo/$** = elo_rating / avg_cost_per_run for each config

Implementation — process matches sequentially:
```
For each match:
  expected_a = 1 / (1 + 10^((rating_b - rating_a) / 400))
  expected_b = 1 - expected_a

  if winner == configA: score_a = 1, score_b = 0
  if winner == configB: score_a = 0, score_b = 1
  if tie: score_a = 0.5, score_b = 0.5

  k_actual = K × confidence_weight
  rating_a += k_actual × (score_a - expected_a)
  rating_b += k_actual × (score_b - expected_b)
```

### Step 6: Position bias diagnostic

Aggregate A-win-rate across all matches (count of "A" wins / total non-tie matches). Expected: ~50%.

If A-win-rate > 60% or < 40%, flag:
```
⚠ Position bias detected: A won {rate}% of matches.
  Consider averaging both orderings or fixing the judge prompt.
```

Store `positionBiasRate` as a field.

### Step 7: Write results

Write to tournament directory:

**Reference-based match files**: Instead of embedding full outputs in each match file, store references by path. The judge agent prompt still gets full text (assembled at spawn time from the referenced paths), but stored files are compact (~2K each instead of ~60K).

Per-match file `tournament/match-{nn}.json`:
```json
{
  "match_id": "match-01-m1",
  "config_a": "{actual config name}",
  "config_b": "{actual config name}",
  "input": "{input-id}",
  "output_a_path": "../config-{a}/output.json",
  "output_b_path": "../config-{b}/output.json",
  "raw_notes_a_path": "../config-{a}/_raw_notes.md",
  "raw_notes_b_path": "../config-{b}/_raw_notes.md",
  "presented_as": {"config_a_shown_as": "A"|"B"},
  "result": {
    "dimensions": {"dim_name": {"winner": "...", "confidence": "...", "reasoning": "..."}},
    "overall": {"winner": "...", "confidence": "...", "reasoning": "..."}
  }
}
```

`matches_summary.json` — compact file for Elo computation and reporting (~20K):
```json
{
  "pipeline_id": "{pipeline-id}",
  "tournament_date": "{ISO datetime}",
  "mode": "quick"|"full",
  "judge_model": "{model used}",
  "total_matches": N,
  "position_bias_rate": 0.52,
  "consistency_check": {"tie_rate": 0.85, "passed": true},
  "matches": [
    {
      "id": "{matchId}",
      "config_a": "{actual config that was A}",
      "config_b": "{actual config that was B}",
      "input": "{input-id}",
      "dimension": "{dimension}",
      "winner": "{actual config name or tie}",
      "presented_as": "A"|"B",
      "confidence": "strong"|"moderate"|"weak",
      "reasoning": "..."
    }
  ]
}
```

`elo.json`:
```json
{
  "pipeline_id": "{pipeline-id}",
  "tournament_date": "{ISO datetime}",
  "judge_model": "{model used}",
  "overall": {
    "{config-name}": {"elo": 1534, "avg_cost": 1.46, "elo_per_dollar": 1050, "wins": N, "losses": N, "ties": N},
    ...
  },
  "per_dimension": {
    "{dimension}": {
      "{config-name}": {"elo": 1534},
      ...
    },
    ...
  }
}
```

Create EvalReport node:
```bash
bash bin/eval-op.sh create-report "{reportId}" "{pipelineId}" "{filePath}" '{configsJson}' '{eloJson}' "{bestConfig}" "{bestEfficiency}" "{matchCount}"
```

### Step 8: Tournament TUI

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⊕ EVAL TOURNAMENT                               {user} · {date}    │
├──────────────────────────────────────────────────────────────────────┤
│  Pipeline: {pipeline-id} · {N} matches                               │
│                                                                      │
│  OVERALL ELO                                                         │
│  1. {config}        {elo}  (${cost}/run)                             │
│  2. {config}        {elo}  (${cost}/run)  ← current                 │
│  3. {config}        {elo}  (${cost}/run)                             │
│  ...                                                                 │
│                                                                      │
│  BEST ELO/$                                                          │
│  1. {config}        {elo_per_dollar}                                 │
│  2. {config}        {elo_per_dollar}                                 │
│  ...                                                                 │
│                                                                      │
│  DIMENSION LEADERS                                                   │
│  {dimension}:  {config} ({elo})                                      │
│  {dimension}:  {config} ({elo})                                      │
│  ...                                                                 │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  /eval multiagent report {pipeline-id}                               │
└──────────────────────────────────────────────────────────────────────┘
```

If position bias was flagged, add before the footer separator:
```
│                                                                      │
│  ⚠ Position bias: A won {rate}% of matches                          │
```

If consistency check ran, add after pipeline line:
```
│  Consistency: {tie_rate}% ties ({"✓ low variance"|"⚠ high variance"})│
```

Mark the config matching "current" (or the first config in the spec) with `← current`.

**Dimension pruning diagnostic**: After the dimension leaders, compute Elo spread (max - min) per dimension. Flag dimensions where spread < 50 Elo points:
```
│                                                                      │
│  LOW-DISCRIMINATION DIMENSIONS (consider dimensions_skip)            │
│  noise_filtering: spread 8 Elo (1496-1504)                          │
│  classification_accuracy: spread 66 Elo (1474-1540)                 │
```

**Judge model used**: Show in the pipeline summary line:
```
│  Pipeline: {pipeline-id} · {N} matches · Judge: {model}             │
```

---

## Subcommand: `report`

Generate comprehensive scorecard from all tournament data.

### Step 0: Load data

```bash
bash bin/eval-op.sh get-runs {pipeline-id}
bash bin/eval-op.sh get-matches {pipeline-id}
bash bin/eval-op.sh get-latest-report {pipeline-id}
```

Also read the latest `elo.json` and `matches_summary.json` from the local tournament directory.

### Step 1: Generate report

Write to `memory/knowledge/evals/{date}-{pipeline-id}-report.md`:

```markdown
# Eval Report: {pipeline title}

**Date**: {YYYY-MM-DD}
**Pipeline**: {pipeline-id} v{version}
**Configs tested**: {list}
**Inputs**: {count} meetings
**Total matches**: {N}
**Judge model**: {model}

## Overall Rankings

| Rank | Config | Elo | Avg Cost | Elo/$ | W/L/T |
|------|--------|-----|----------|-------|-------|
| 1 | {config} | {elo} | ${cost} | {elo/$} | {w}/{l}/{t} |
| 2 | {config} | {elo} | ${cost} | {elo/$} | {w}/{l}/{t} |
| ... | | | | | |

## Per-Dimension Elo

| Dimension | Leader | Elo | Runner-up | Elo |
|-----------|--------|-----|-----------|-----|
| {dim} | {config} | {elo} | {config} | {elo} |
| ... | | | | |

## Cost Comparison

| Config | Tokens | Cost/Run | Latency |
|--------|--------|----------|---------|
| {config} | {N} | ${X.XX} | {N}ms |
| ... | | | |

## Efficiency Rankings

| Rank | Config | Elo/$ | Notes |
|------|--------|-------|-------|
| 1 | {config} | {N} | {e.g., "Best value"} |
| ... | | | |

## Key Findings

{Synthesize from match reasoning. Group by theme:}
- Where configs differed most
- Which dimensions are most sensitive to model tier
- Whether ablation variants reveal dispensable slots
- Cost/quality sweet spots

## Recommendation

{Based on the data:}
- **Production**: {config} — {why}
- **High-stakes**: {config} — {why}
- **Budget**: {config} — {why}

## Diagnostics

- Position bias rate: {rate}% ({"acceptable"|"flagged"})
- Consistency check: {result if available}
```

### Step 2: Record in graph

Create an Artifact node for the report:
```bash
bash bin/graph-batch.sh '[
  {
    "statement": "MERGE (a:Artifact {id: $id}) SET a.title = $title, a.type = \"eval-report\", a.filePath = $filePath, a.created = datetime() WITH a OPTIONAL MATCH (p:Person {name: $author}) FOREACH (_ IN CASE WHEN p IS NOT NULL THEN [1] ELSE [] END | MERGE (a)-[:CONTRIBUTED_BY]->(p)) RETURN a.id",
    "parameters": {"id": "{date}-{pipeline-id}-report", "title": "Eval Report: {pipeline title}", "filePath": "knowledge/evals/{date}-{pipeline-id}-report.md", "author": "{user}"}
  }
]'
```

### Step 3: Display TUI

Extended version of tournament TUI with full dimension breakdown:

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⊕ EVAL REPORT                                   {user} · {date}    │
├──────────────────────────────────────────────────────────────────────┤
│  Pipeline: {pipeline-id} · {N} matches · {M} inputs                 │
│                                                                      │
│  OVERALL ELO                                                         │
│  1. {config}        {elo}  (${cost}/run)                             │
│  2. {config}        {elo}  (${cost}/run)  ← current                 │
│  ...                                                                 │
│                                                                      │
│  PER-DIMENSION BREAKDOWN                                             │
│                                                                      │
│  extraction_completeness                                             │
│    1. {config} {elo}  2. {config} {elo}  3. {config} {elo}          │
│                                                                      │
│  classification_accuracy                                             │
│    1. {config} {elo}  2. {config} {elo}  3. {config} {elo}          │
│                                                                      │
│  (repeat for each dimension)                                         │
│                                                                      │
│  RECOMMENDATION                                                      │
│  Production: {config} — {one line why}                               │
│  High-stakes: {config} — {one line why}                              │
│  Budget: {config} — {one line why}                                   │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  ✓ Saved to memory/knowledge/evals/{filename}                        │
│  ✓ Indexed in knowledge graph                                        │
└──────────────────────────────────────────────────────────────────────┘
```

### Step 4: Auto-save (single save at end)

This is the ONLY point in the entire eval pipeline where `/save` runs. Never save mid-pipeline (not after analysts, not after synthesis, not after tournament matches).

Commit and push changes via the `/save` flow:
- Stage the report file in the memory repo
- Commit with message: `Add eval report: {pipeline-id} ({date})`
- Push

---

## Notes

### Model pricing reference (for cost estimation)
- Opus: $15/M input tokens, $75/M output tokens
- Sonnet: $3/M input tokens, $15/M output tokens
- Haiku: $0.80/M input tokens, $4/M output tokens

### Spec version gating
Tournament only compares runs with matching spec version. When the pipeline code changes, bump the version in the eval spec. Old data is preserved for longitudinal tracking but excluded from active tournaments.

### Phase 2 subcommands (deferred)
These build on run + tournament and ship after the core is stable:
1. **`compose --sequence input1,input2,input3`** — Cold/warm/hot context comparison
2. **`calibrate`** — Human-in-the-loop judge calibration (Cohen's kappa)
3. **`isolate --slot <name> --vary models`** — Single-slot ablation study
