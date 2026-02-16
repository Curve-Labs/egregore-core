# Eval: Meeting Analysis Pipeline

Defines the evaluation framework for the multi-dimensional meeting analysis pipeline. Spec only — no tooling yet.

## Slots

| Slot | Model | Input | Output |
|------|-------|-------|--------|
| `substance` | sonnet | transcript + scaffold + open questions + quests | `substance_analysis` — priorities, dependencies, events, enrichments, `_raw_notes` |
| `dynamics` | sonnet | transcript + attendees | `dynamics_analysis` — tone, energy, convictions, interpersonal dynamics, `_raw_notes` |
| `continuity` | sonnet | panel + graph context (Q1-Q4) + scaffold | `continuity_analysis` — decision evolution, recurring topics, open threads, meta-patterns, `_raw_notes` |
| `synthesis` | opus | all agent outputs + panel + scaffold | Meeting Intelligence Briefing + enriched artifact list |

## Variants

| Variant | substance | dynamics | continuity | synthesis |
|---------|-----------|----------|------------|-----------|
| `baseline` | haiku | haiku | haiku | opus |
| `current` | sonnet | sonnet | sonnet | opus |
| `deep` | sonnet | opus | sonnet | opus |

## Ablation Variants

Test whether each agent slot adds value beyond the others.

| Variant | substance | dynamics | continuity | synthesis |
|---------|-----------|----------|------------|-----------|
| `substance_only` | sonnet | null | null | opus |
| `dynamics_only` | null | sonnet | null | opus |
| `continuity_only` | null | null | sonnet | opus |
| `substance+dyn` | sonnet | sonnet | null | opus |
| `substance+cont` | sonnet | null | sonnet | opus |

When a slot is `null`, the synthesis step receives an empty object for that agent's output.

## Test Corpus

Diverse meeting types to test generalization:

| ID | Type | Characteristics |
|----|------|----------------|
| `7df47eba-a155-4a37-93a5-5528f0d8a68d` | Strategy session | Egregore onboarding workflow — 2 attendees, decision-heavy |
| `dbca2151-7730-473c-901e-b056abe640b2` | Strategy session | Egregore workflow + AI strategy — 2 attendees, mixed decisions/findings |
| *(add more as meetings accumulate)* | | |

Target: 5-10 meetings across at least 3 types (strategy, design review, standup/sync).

## Evaluation Criteria

### Per-Slot Criteria

**Substance (`substance_richness`)**:
Does the output capture nuances beyond what the panel says? Specifically:
- Priorities identified with supporting evidence
- Dependencies with blockers and owners
- Events (internal/external) that contextualize decisions
- Enrichments that add context, tradeoffs, and open questions to scaffold items
- `_raw_notes` that contain reasoning not captured in structured fields

**Dynamics (`dynamics_insight`)**:
Does the dynamics analysis reveal interpersonal signals not obvious from text?
- Tone arc that captures emotional evolution through the meeting
- Conviction strength distinctions (assertion vs hypothesis vs exploration)
- Interpersonal dynamics (who drove, alignment/tension, power dynamics)
- `_raw_notes` with observations about what was unsaid or implied

**Continuity (`continuity_value`)**:
Does cross-meeting context add information the other agents miss?
- Decision evolution chains linking to specific previous artifacts
- Topic recurrence with meaningful trajectory analysis (not just counting)
- Open threads from previous meetings addressed or continued
- Meta-patterns that emerge across multiple meetings

**Synthesis (`synthesis_coherence`)**:
Is the final briefing more than the sum of its parts?
- Executive summary captures the "so what" not available from any single agent
- Internal tensions section identifies genuine contradictions between agents
- Artifacts are enriched with dimensional properties from all three agents
- The briefing reads as a coherent intelligence document, not a concatenation

### Cross-Cutting Criteria

**Cost efficiency (`cost_efficiency`)**:
Quality per dollar. Compare variant outputs against their cost:
- baseline (~$0.04): minimum viable quality
- current (~$0.40): target quality level
- deep (~$0.55): maximum quality for high-stakes meetings

**Complementarity (`agent_complementarity`)**:
Do agents produce genuinely different signal? Compare:
- `substance_only` vs `current`: what does dynamics + continuity add?
- `substance+dyn` vs `current`: what does continuity add?
- `substance+cont` vs `current`: what does dynamics add?

If ablation variants score within 10% of `current`, the removed slot isn't adding value.

## Tournament Protocol

1. Pick 2 variants (e.g., `current` vs `baseline`)
2. Run both on the same meeting
3. Present `_raw_notes` from each side-by-side (anonymized: "Output A" vs "Output B")
4. Human picks winner per slot + overall
5. Record result, update Elo rankings
6. Repeat across corpus for statistical significance (minimum 3 meetings per matchup)

### Calibration

Periodically run `/eval:calibrate` to check:
- Present blinded pairs to human alongside automated judge's assessment
- Record agree/disagree
- Produces divergence pattern report — answers "can I trust the automated tournament?"

## Future: Automated Judging

Once calibration data is sufficient (20+ human judgments), test automated judging:
- Use Opus as judge with calibrated rubric
- Compare automated rankings to human rankings
- Only trust automated scores where calibration divergence < 15%
