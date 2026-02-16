---
pipeline_id: <unique-id>
title: <Human-readable pipeline name>
version: 1
status: draft
created: <YYYY-MM-DD>
author: <handle>
---

# <Pipeline Title>

## Architecture
Input(<type>) → slot1:Model(role) → slot2:Model(role) → ... → Output

## Slots
| Slot | Role | Options | Default |
|------|------|---------|---------|
| slot1 | What this slot does | opus, sonnet, haiku | sonnet |
| slot2 | What this slot does | opus, sonnet, haiku | haiku |

## Input Resolution
| Type | Command |
|------|---------|
| <input-type> | `<shell command with {id} placeholder>` |

## Configs

Each config maps slots to `{model, prompt_variant, params}`. Only `model` is required — omit `prompt_variant` and `params` to use defaults.

### baseline
slot1: {model: sonnet}, slot2: {model: haiku}
_Current production config._

### <variant-name>
slot1: {model: sonnet, prompt_variant: concise}, slot2: {model: haiku}
_Why this variant is interesting._

## Prompt Variants
Define named prompt variants per slot. Configs reference these by name. If omitted, the slot's default role description is used.

### slot1
- **default**: (uses Role from Slots table)
- **concise**: "Analyze with minimal explanation. Structured output only."

## Eval Dimensions
1. **dimension_name**: Natural language description of what to evaluate.
2. **dimension_name**: Another quality criterion.

## Input Corpus
- <input-type>:<id>
(Expand as inputs are processed)
