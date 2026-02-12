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

## Configs

### baseline
slot1: <model>, slot2: <model>
_Current production config._

### <variant-name>
slot1: <model>, slot2: <model>
_Why this variant is interesting._

## Eval Dimensions
1. **dimension_name**: Natural language description of what to evaluate.
2. **dimension_name**: Another quality criterion.

## Input Corpus
- <input-type>:<id>
(Expand as inputs are processed)
