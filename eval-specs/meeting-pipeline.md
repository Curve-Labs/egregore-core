---
pipeline_id: meeting-pipeline
title: Meeting Extraction Pipeline
version: 1
status: active
created: 2026-02-12
author: cem
corpus_size: 2
quick_configs:
  - current
  - all-sonnet
  - deep
dimensions_skip: []
---

# Meeting Extraction Pipeline

## Architecture
Input(meeting) → substance:Sonnet(transcript+scaffold+quests) → dynamics:Sonnet(transcript+attendees) → continuity:Sonnet(panel+graph+scaffold) → synthesis:Opus(all+panel+scaffold) → Output

## Slots
| Slot | Role | Options | Default |
|------|------|---------|---------|
| substance | Priorities, dependencies, events, enrichments from transcript | opus, sonnet, haiku | sonnet |
| dynamics | Tone, energy, convictions, interpersonal signals | opus, sonnet, haiku | sonnet |
| continuity | Decision evolution, recurring topics, open threads, meta-patterns | opus, sonnet, haiku | sonnet |
| synthesis | Merge all agent outputs into coherent briefing + enriched artifacts | opus, sonnet | opus |

## Input Resolution
| Type | Command |
|------|---------|
| meeting | `bash bin/granola.sh get {id}` |

## Configs

Each config maps slots to `{model}`. Prompt variants and params can be added per-slot when needed (see template).

### baseline
substance: {model: haiku}, dynamics: {model: haiku}, continuity: {model: haiku}, synthesis: {model: opus}
_Cost floor. Minimum viable quality._

### current
substance: {model: sonnet}, dynamics: {model: sonnet}, continuity: {model: sonnet}, synthesis: {model: opus}
_Current production config._

### deep
substance: {model: sonnet}, dynamics: {model: opus}, continuity: {model: sonnet}, synthesis: {model: opus}
_Quality ceiling for high-stakes meetings._

### all-sonnet
substance: {model: sonnet}, dynamics: {model: sonnet}, continuity: {model: sonnet}, synthesis: {model: sonnet}
_Mid-tier everywhere. Tests whether Opus synthesis is worth it._

### substance-only
substance: {model: sonnet}, dynamics: null, continuity: null, synthesis: {model: opus}
_Ablation: is substance alone sufficient?_

### substance-dynamics
substance: {model: sonnet}, dynamics: {model: sonnet}, continuity: null, synthesis: {model: opus}
_Ablation: what does continuity add?_

### substance-continuity
substance: {model: sonnet}, dynamics: null, continuity: {model: sonnet}, synthesis: {model: opus}
_Ablation: what does dynamics add?_

## Eval Dimensions
1. **extraction_completeness**: Did the config capture all significant insights from the meeting — decisions, findings, patterns, actions?
2. **classification_accuracy**: Are items correctly categorized (decision/finding/pattern/action)? Are confidence signals appropriate?
3. **evidence_quality**: Are quotes well-selected (high signal, not just long)? Do they support the extracted insight?
4. **tradeoff_extraction**: Were tradeoffs, pros/cons, tensions captured? Are they specific rather than generic?
5. **context_richness**: Enough context to understand each item standalone without reading the full transcript?
6. **cross_referencing**: Were connections between extractions identified? Does the synthesis reveal tensions between agents?
7. **noise_filtering**: Was trivia/logistics correctly excluded? Is the signal-to-noise ratio high?

## Input Corpus
- meeting:7df47eba-a155-4a37-93a5-5528f0d8a68d
- meeting:dbca2151-7730-473c-901e-b056abe640b2
(Expand as meetings are processed)

## Corpus Sampling

When the input corpus grows beyond `corpus_size` (frontmatter), randomly sample `corpus_size` inputs per run using a deterministic seed (run date + seq number). This prevents eval cost from growing linearly with meeting history while maintaining reproducibility.
