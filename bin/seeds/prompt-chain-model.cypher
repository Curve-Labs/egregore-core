// ============================================================================
// PROMPT CHAIN GRAPH: "The Egregore Commons"
//
// A sample prompt chain extracted from the conversation of Feb 10, 2026.
// Run against a Neo4j instance. Creates the chain, moves, transitions,
// and emergent concepts as a reusable reasoning pattern.
//
// Usage:  cat prompt-chain-egregore-commons.cypher | cypher-shell -u neo4j -p <pw>
//    or:  paste into Neo4j Browser
// ============================================================================


// --- CHAIN NODE ---
// The top-level container. Named for the reasoning strategy it exemplifies.

CREATE (chain:PromptChain {
  id: 'chain-egregore-commons-2026-02-10',
  name: 'Concrete-to-Abstract Ladder',
  description: 'Start with a specific UX bug, iteratively elevate through architecture, theory, and strategy until a novel synthesis emerges. Each move reframes rather than extends.',
  participants: ['cem', 'claude'],
  date: '2026-02-10',
  duration_minutes: 90,
  outcome: 'From dashboard noise fix to theory of organizational intelligence commons',
  quality_signals: ['produced_spec', 'named_product_concept', 'generated_archival_command_idea']
})


// --- MOVES ---
// Each move is a distinct intervention with a type, trigger, and effect.

CREATE (m1:Move {
  id: 'move-01-grounding',
  type: 'grounding',
  order: 1,
  prompt_summary: 'Screenshot of /activity dashboard showing stale handoff + description of the problem',
  trigger: 'session_start',
  effect: 'Established concrete, specific problem with visual evidence',
  principle: 'Always start with the artifact, not the abstraction'
})

CREATE (m2:Move {
  id: 'move-02-design-critique',
  type: 'calibration',
  order: 2,
  prompt_summary: 'Pointed out that selecting a task as focus should be sufficient signal — the AskUserQuestion was the friction',
  trigger: 'model_proposed_mechanism',
  effect: 'Shifted from additive solution (more states) to subtractive (remove the confirmation prompt)',
  principle: 'The best UX fix is often removing a step, not adding intelligence'
})

CREATE (m3:Move {
  id: 'move-03-implementation-plan',
  type: 'specification',
  order: 3,
  prompt_summary: 'CC produced detailed implementation plan: 4 files, 3-state lifecycle, Q_resolve query',
  trigger: 'design_direction_established',
  effect: 'Concrete, reviewable plan with file paths, line numbers, Cypher queries',
  principle: 'Specification as shared artifact — reviewable by both human and model'
})

CREATE (m4:Move {
  id: 'move-04-visual-reframe',
  type: 'reframing',
  order: 4,
  prompt_summary: 'Proposed status glyphs (● ◐ ○) and separation of dashboard rendering vs Focus menu filtering',
  trigger: 'implementation_plan_felt_over_engineered_for_ux',
  effect: 'Split the problem into two concerns: visual status (always show) and selection logic (filter actionable)',
  principle: 'Rendering and interaction are different design surfaces'
})

CREATE (m5:Move {
  id: 'move-05-scope-expansion',
  type: 'elevation',
  order: 5,
  prompt_summary: 'Noted that task resolution tracking is needed globally across the stack, and quests depend on it',
  trigger: 'local_fix_felt_insufficient',
  effect: 'Elevated from handoff UX fix to organizational visibility problem',
  principle: 'A recurring local problem usually signals a missing systemic abstraction'
})

CREATE (m6:Move {
  id: 'move-06-abstraction-request',
  type: 'inversion',
  order: 6,
  prompt_summary: 'Describe the god mode of this unified model. Even just conceptual, no project context.',
  trigger: 'organizational_visibility_gap_identified',
  effect: 'Freed model from implementation constraints to reason about ideal architecture',
  principle: 'Asking for the ideal before the feasible prevents premature compromise'
})

CREATE (m7:Move {
  id: 'move-07-three-primitives',
  type: 'synthesis',
  order: 7,
  prompt_summary: 'Model produced intent/commitment/contribution ontology with resolution-as-judgment, temporal depth, propagation model',
  trigger: 'unconstrained_design_space',
  effect: 'Unified framework that subsumes all existing tools (quests, handoffs, sessions) as views',
  principle: 'Good abstractions make existing complexity disappear rather than adding new complexity'
})

CREATE (m8:Move {
  id: 'move-08-bitter-lesson',
  type: 'reframing',
  order: 8,
  prompt_summary: 'Observed that the 3-state machine is the wrong instinct — tool provision to models handles this better than rule-following',
  trigger: 'parallel_cc_session_demonstrated_emergent_reasoning',
  effect: 'Shifted design philosophy from encoded heuristics to model-as-orchestrator',
  principle: 'Invest in data quality and tool ergonomics, not decision logic'
})

CREATE (m9:Move {
  id: 'move-09-evidence-injection',
  type: 'grounding',
  order: 9,
  prompt_summary: 'Shared CC session transcript showing model producing launch readiness analysis from raw graph/git data',
  trigger: 'bitter_lesson_claim_needed_evidence',
  effect: 'Concrete proof that tool-equipped models outperform structured templates for organizational reasoning',
  principle: 'Demonstrate before theorizing — evidence from practice > argument from principle'
})

CREATE (m10:Move {
  id: 'move-10-pattern-extraction',
  type: 'elevation',
  order: 10,
  prompt_summary: 'What made that CC session work? Can we bottle the prompt pattern?',
  trigger: 'recognized_reusable_reasoning_strategy',
  effect: 'Generated prompt chain concept — moves as typed graph nodes, chains as reusable strategies',
  principle: 'The meta-pattern: recognizing that your process is itself a transferable artifact'
})

CREATE (m11:Move {
  id: 'move-11-feasibility-check',
  type: 'calibration',
  order: 11,
  prompt_summary: 'Is this feasible? Are there analogues? Do we need to invent new frameworks?',
  trigger: 'novel_concept_needs_grounding',
  effect: 'Mapped to dialogue act theory, CBR, game trees, RST — validated concept, identified novel bridge problem',
  principle: 'Check the literature before assuming novelty'
})

CREATE (m12:Move {
  id: 'move-12-automation-question',
  type: 'scoping',
  order: 12,
  prompt_summary: 'Should I archive manually or should it be automated? And what if egregore learned from all organizational morphologies?',
  trigger: 'archival_mechanism_underspecified',
  effect: 'Two breakthroughs: (1) automated extraction > manual archival, (2) cross-org commons as data flywheel',
  principle: 'The question about process often reveals the real product insight'
})

CREATE (m13:Move {
  id: 'move-13-naming',
  type: 'synthesis',
  order: 13,
  prompt_summary: 'Egregore should be the name of the commons graph — and inadvertently the company',
  trigger: 'commons_concept_crystallized',
  effect: 'The name found its true referent: not the tool, but the emergent collective intelligence',
  principle: 'Naming is an act of recognition, not invention'
})


// --- CHAIN STRUCTURE (STEERS edges) ---
// Each move steers the next. The edge carries the transition logic.

CREATE (m1)-[:STEERS {
  transition: 'Problem established → design response invited',
  human_or_model: 'human_initiates'
}]->(m2)

CREATE (m2)-[:STEERS {
  transition: 'Design critique accepted → detailed implementation requested',
  human_or_model: 'collaborative'
}]->(m3)

CREATE (m3)-[:STEERS {
  transition: 'Implementation plan reviewed → UX layer separated',
  human_or_model: 'human_reframes'
}]->(m4)

CREATE (m4)-[:STEERS {
  transition: 'Local UX solved → systemic need identified',
  human_or_model: 'human_elevates'
}]->(m5)

CREATE (m5)-[:STEERS {
  transition: 'Systemic need acknowledged → ideal model requested',
  human_or_model: 'human_inverts'
}]->(m6)

CREATE (m6)-[:STEERS {
  transition: 'Unconstrained prompt → model synthesizes ontology',
  human_or_model: 'model_synthesizes'
}]->(m7)

CREATE (m7)-[:STEERS {
  transition: 'Ontology produced → challenged with bitter lesson',
  human_or_model: 'human_reframes'
}]->(m8)

CREATE (m8)-[:STEERS {
  transition: 'Philosophy shift claimed → evidence provided from parallel session',
  human_or_model: 'human_grounds'
}]->(m9)

CREATE (m9)-[:STEERS {
  transition: 'Evidence validated claim → meta-pattern extracted',
  human_or_model: 'collaborative'
}]->(m10)

CREATE (m10)-[:STEERS {
  transition: 'Novel concept proposed → feasibility and precedent checked',
  human_or_model: 'human_calibrates'
}]->(m11)

CREATE (m11)-[:STEERS {
  transition: 'Feasibility confirmed → scope and automation questioned',
  human_or_model: 'human_scopes'
}]->(m12)

CREATE (m12)-[:STEERS {
  transition: 'Commons concept crystallized → naming act',
  human_or_model: 'human_synthesizes'
}]->(m13)


// --- EMERGENT CONCEPTS ---
// Ideas that emerged from the chain and didn't exist before it.

CREATE (c1:Concept {
  id: 'concept-intent-commitment-contribution',
  name: 'Intent / Commitment / Contribution',
  description: 'Three primitives for unified task lifecycle. Everything else is a composed view.',
  emerged_at_move: 'move-07-three-primitives'
})

CREATE (c2:Concept {
  id: 'concept-resolution-as-judgment',
  name: 'Resolution as Judgment',
  description: 'Done is not a status flag but a function: f(intent, contributions) → {open, satisfied, contested}',
  emerged_at_move: 'move-07-three-primitives'
})

CREATE (c3:Concept {
  id: 'concept-prompt-chain-graph',
  name: 'Prompt Chains as Directed Graphs',
  description: 'Reusable reasoning strategies stored as typed move sequences, not text templates',
  emerged_at_move: 'move-10-pattern-extraction'
})

CREATE (c4:Concept {
  id: 'concept-egregore-commons',
  name: 'The Egregore Commons',
  description: 'Cross-organizational meta-graph of anonymized cognitive patterns. The data flywheel.',
  emerged_at_move: 'move-12-automation-question'
})

CREATE (c5:Concept {
  id: 'concept-bitter-lesson-for-orgs',
  name: 'Bitter Lesson for Organizational Tools',
  description: 'Invest in data quality and tool ergonomics, not decision logic. Let models orchestrate.',
  emerged_at_move: 'move-08-bitter-lesson'
})


// --- CONCEPT EDGES ---

CREATE (chain)-[:PRODUCED]->(c1)
CREATE (chain)-[:PRODUCED]->(c2)
CREATE (chain)-[:PRODUCED]->(c3)
CREATE (chain)-[:PRODUCED]->(c4)
CREATE (chain)-[:PRODUCED]->(c5)

CREATE (m7)-[:GENERATED]->(c1)
CREATE (m7)-[:GENERATED]->(c2)
CREATE (m10)-[:GENERATED]->(c3)
CREATE (m12)-[:GENERATED]->(c4)
CREATE (m8)-[:GENERATED]->(c5)

// Concepts build on each other
CREATE (c1)-[:ENABLES {reason: 'Unified lifecycle model requires model-as-orchestrator to avoid rigidity'}]->(c5)
CREATE (c5)-[:ENABLES {reason: 'If models orchestrate, their reasoning patterns become extractable'}]->(c3)
CREATE (c3)-[:ENABLES {reason: 'Extractable patterns across orgs create the commons'}]->(c4)


// --- CHAIN BELONGS TO MOVE TAXONOMY ---
// The move types used, for retrieval and pattern matching.

CREATE (chain)-[:MOVE_ORDER]->(m1)
CREATE (chain)-[:MOVE_ORDER]->(m2)
CREATE (chain)-[:MOVE_ORDER]->(m3)
CREATE (chain)-[:MOVE_ORDER]->(m4)
CREATE (chain)-[:MOVE_ORDER]->(m5)
CREATE (chain)-[:MOVE_ORDER]->(m6)
CREATE (chain)-[:MOVE_ORDER]->(m7)
CREATE (chain)-[:MOVE_ORDER]->(m8)
CREATE (chain)-[:MOVE_ORDER]->(m9)
CREATE (chain)-[:MOVE_ORDER]->(m10)
CREATE (chain)-[:MOVE_ORDER]->(m11)
CREATE (chain)-[:MOVE_ORDER]->(m12)
CREATE (chain)-[:MOVE_ORDER]->(m13)


// --- CHAIN METADATA ---
// Strategy-level annotations for retrieval.

CREATE (strategy:Strategy {
  id: 'strategy-concrete-to-abstract-ladder',
  name: 'Concrete-to-Abstract Ladder',
  signature_moves: ['grounding', 'elevation', 'inversion', 'synthesis'],
  when_to_use: 'When a specific problem might be an instance of a deeper structural issue. Start concrete, test if elevation is warranted at each step, stop when synthesis produces a concept that reframes the original problem.',
  anti_pattern: 'Jumping to abstraction without grounding. The ladder works because each rung is earned by the previous one.',
  typical_length: '10-15 moves',
  human_role: 'Steering via reframing and elevation. The human decides when to climb.',
  model_role: 'Synthesis and specification. The model fills each level with substance.'
})

CREATE (chain)-[:EXEMPLIFIES]->(strategy)


// ============================================================================
// SAMPLE QUERIES
// ============================================================================

// 1. Trace the full chain
// MATCH (c:PromptChain {id: 'chain-egregore-commons-2026-02-10'})-[:MOVE_ORDER]->(m:Move)
// RETURN m.order, m.type, m.prompt_summary, m.principle
// ORDER BY m.order

// 2. What concepts emerged and from which moves?
// MATCH (m:Move)-[:GENERATED]->(c:Concept)
// RETURN m.order, m.type, c.name, c.description
// ORDER BY m.order

// 3. Find the causal chain of concepts
// MATCH path = (c1:Concept)-[:ENABLES*]->(c2:Concept)
// RETURN [n IN nodes(path) | n.name] AS concept_chain,
//        [r IN relationships(path) | r.reason] AS reasons

// 4. What strategy does this chain exemplify?
// MATCH (c:PromptChain)-[:EXEMPLIFIES]->(s:Strategy)
// RETURN s.name, s.when_to_use, s.anti_pattern, s.signature_moves

// 5. Find all moves where the human reframed
// MATCH (m1:Move)-[s:STEERS]->(m2:Move)
// WHERE s.human_or_model = 'human_reframes'
// RETURN m1.type, m1.prompt_summary, '->', m2.type, m2.prompt_summary
