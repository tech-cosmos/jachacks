# Devpost draft — DO NOT SUBMIT YET (user submits manually)

**Project name:** Continuity Walker
**Tracks:** Agentic AI (primary), Best JacHammer
**Elevator:** Finds provable plot holes in movies and TV — with the proof.

## Inspiration

Paste a screenplay into a frontier model and ask for plot holes: you get a
confident numbered list, half of it subjective nitpicks, some hallucinated —
and a *different* list on the next run. We ran that exact experiment on Home
Alone (it's the `naive` command in our repo): 13 "plot holes" on run one, 10
on run two. That's a capability failure, not a prompting failure: consistency
across 40 scenes is a *reasoning-over-accumulated-state* problem, and a flat
context window has no state.

## What it does

Every scene both **establishes** facts and **requires** facts. A plot hole is
a scene requiring something the accumulated canon doesn't support.

Continuity Walker ingests a script scene by scene, extracts typed
(subject, predicate, value) facts with byLLM, and accretes them into a
persistent canon graph. An `Auditor` walker then checks every requirement
against the most recent canon state for that subject, hunting for a legal
transition path that reconciles mismatches. No path → candidate violation →
one more byLLM call adjudicates it against the exact evidence timeline the
walker traversed. The traversal *is* the proof, and we print it.

We only claim **state contradictions** (provable), never "why didn't they
just fly the eagles" logic holes (opinions).

**Scoreboard on real films (verifiable by any judge):**
- ✖ CONFIRMED: Home Alone's phone — established down in the storm, confirmed
  down twice more, never repaired, yet Kevin orders pizza by phone.
- ✖ CONFIRMED: Game of Thrones S8 — Dothraki wiped out at Winterfell (E3),
  charge at King's Landing (E5). Cross-episode: E5 is audited against canon
  persisted from E3. The adjudicator's verdict: "a dead entity relocating is
  not itself a resurrection event."
- · DECLINED (4): wording near-misses (rigged_traps vs trapped, cash vs
  money…) correctly declined — precision, not just recall.
- ↩ WITHDRAWN: the showstopper. The classic fan defense of Home Alone is that
  only long-distance lines were down (a real 1990 distinction, confirmed by an
  AT&T VP). Add that one line of dialogue to canon, re-audit, and the system
  **withdraws its own finding** — because the pizza call is local. Reasoning
  over pattern-matching, live in 15 seconds.
- Extraction accuracy vs annotated ground truth reported as a number by
  `jac run main.jac score` — we measure our weakest link instead of hiding it.

## How we used Jac (≈79% of the code by bytes, 799 of 992 lines)

Everything except one static HTML file is Jac (`main.jac`):
- **Object-spatial schema**: `Document`, `Segment`, `State`, `Violation`
  nodes; `Establishes`, `Requires`, `Transition`, `Supersedes` typed edges.
- **Walkers**: `Ingest`, `Auditor`, `ShowCanon`, `Score`, `Dump`, `Reset` —
  the audit is literally a graph traversal; typed-edge filters like
  `[seg ->:Requires:->]` do the queries.
- **Scale-agnostic persistence**: canon survives across runs and episodes with
  zero database code — ingest E3 today, audit E5 against it tomorrow.
- **byLLM**: `extract_facts() -> SceneFacts` and `adjudicate() -> Verdict` are
  typed LLM functions — no prompt plumbing, no JSON parsing, schema-safe
  returns. The LLM does exactly two things: read prose into typed facts, and
  judge a candidate against the walker's evidence path.

The frontend is one HTML file with Cytoscape polling `graph.json` that the
`Dump` walker writes.

## Schema is domain-neutral (future work, deliberately not built today)

Nothing in the schema knows it's a story: contracts + amendments, policy
handbooks, and versioned specs have the same episode structure. The strongest
extension: retraction contamination in citation graphs — 75.3% of retracted
papers keep being cited; propagation along *load-bearing* citation edges with
attenuation is exactly this walker.

## Submission checklist (manual, at 5:50 PM)

- [ ] GitHub link: https://github.com/tech-cosmos/jachacks (merge PR to main first!)
- [ ] Demo video ≤ 1:30
- [ ] This description
- [ ] Select tracks: Agentic AI, Best JacHammer
- [ ] ⭐ Star https://github.com/jaseci-labs/jac
