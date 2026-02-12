Eval framework — pipeline evaluation and comparison. Routes to subcommands or shows overview.

Arguments: $ARGUMENTS

## Routing

Parse `$ARGUMENTS`:
- **Empty** → List mode (below)
- **`multiagent <subcommand> [args]`** → Route to `/eval-multiagent` with the remaining args

## List Mode (no arguments)

Scan available pipelines and display overview.

### Step 1: Discover pipelines

Read all `eval-specs/*.md` files (skip `_template.md`). For each file, extract frontmatter:

```bash
# For each spec file
head -20 eval-specs/<file>.md
```

Parse: `pipeline_id`, `title`, `version`, `status`.

Count configs by scanning `### <name>` headers under `## Configs`.

Count dimensions by scanning numbered items under `## Eval Dimensions`.

### Step 2: Query graph for recent activity

Run in parallel:

```bash
# Recent runs per pipeline
bash bin/eval-op.sh get-runs <pipeline-id>

# Latest report per pipeline
bash bin/eval-op.sh get-latest-report <pipeline-id>
```

If Neo4j is unavailable, skip — show file-based data only.

### Step 3: Display TUI

Read the user's name from `.egregore-state.json` (`jq -r '.name // "user"'`).
Get today's date formatted as `Mon DD`.

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⊕ EVAL                                          {user} · {date}    │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  PIPELINES                                                           │
│  {pipeline-id}    {N} configs · {M} dimensions                       │
│    Last run: {date} — {best_config} Elo: {rating}                    │
│                                                                      │
│  (repeat for each pipeline with status: active)                      │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  /eval multiagent run {pipeline-id}                                  │
│  /eval multiagent tournament {pipeline-id}                           │
│  /eval multiagent report {pipeline-id}                               │
└──────────────────────────────────────────────────────────────────────┘
```

If no runs exist yet for a pipeline, show:
```
│  {pipeline-id}    {N} configs · {M} dimensions                       │
│    No runs yet                                                       │
```

If no pipelines exist (no files in eval-specs/ besides _template.md):
```
│  No eval specs found.                                                │
│  Create one in eval-specs/ using _template.md                        │
```

## Notes

- The `/eval` command is a router. All real work happens in subcommands.
- Future subcommand namespaces: `retrieval`, `character`, `economics` — they will share the same list mode and graph infrastructure.
