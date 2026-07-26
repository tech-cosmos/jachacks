# JacHacks SF — Idea Board (ranked by 3-judge panel)

Scores are /50, averaged across three judge personas (Jaseci engineer / YC partner / hackathon veteran).
Full details for all 22 ideas + judge notes: `ideation_results_full.json`.

## Top picks

### 1. Lazarus — 43.0 (Agentic AI, also strongest JacHammer candidate)
Durable-execution runtime for LLM agents in ~400 lines of Jac. A Planner byLLM-decomposes a goal into a Step DAG (`depends_on` edges); a Queen walker repeatedly finds the frontier (steps whose deps are done) and spawns Worker walkers on them; results persist on nodes.
**Demo beat:** run a 7-step task, `kill -9` the process on stage at step 4, restart — completed steps still green, colony resumes exactly where it died. Closer: "grep the repo for 'db' — nothing."
**Why judges liked it:** the kill -9 beat needs zero extra code and can't flake; "the plan IS the persistent graph" is the best possible language pitch; real market (Temporal-for-agents).
**Cut order if behind:** Medic retry-walker, concurrency, viz polish (terminal DAG printout fallback).

### 2. Chain of Life — 41.0 (Social Impact)
Kidney paired-donation (the real UNOS problem): incompatible donor–patient Pair nodes, CompatibleWith edges, a ChainSeeker walker whose DFS state literally IS the candidate swap chain. Paste a messy referral email → byLLM mints an altruistic donor node → a 6-transplant chain lights up. Hospital advocate agents argue over conflicting chains, an ethics arbiter rules against a written policy, and a mid-demo donor dropout forces a live rescue replan (salvages 4 of 6).
**Why judges liked it:** a real graph algorithm on the domain that invented it; lives-saved counter; clearest impact story of all 22.
**Cut order:** surgery scheduling, 4 hospitals → 2, multi-chain optimization (greedy first-found chain is fine).
*(This one has a full build-ready spec — graph schema, hour-by-hour plan — in the JSON.)*

### 3. Walkers & Wyverns — 39.3 (Agentic AI / JacHammer)
Dungeon crawler where the dungeon IS the graph and the party ARE walkers. Traps and monsters are node abilities (`can spring with Adventurer entry`) — the language's dispatch semantic is the game engine. Party council (byLLM) plans; Scout/Fighter/Wizard split up; beliefs/goals are visible nodes. Ctrl-C on stage, restart, everything survives.
**Caveat all 3 judges raised:** near-zero real-world impact caps it in an impact-scored rubric. Purest Jac flex though.

### 4. Domino — 39.3 (Fintech)
Bank-run sandbox: 15–20 bank interbank exposure graph; judge clicks any bank; ShockWalker cascades failure edge-by-edge (deterministic balance-sheet math), LLM bank agents panic on local info and mutate the graph (pull credit lines = delete edges). Replay the same click with a regulator agent that simulates 3 bailouts and commits the cheapest. "Same click, two futures."
**Why judges liked it:** deterministic core still demos even if every LLM call fails; cascade-as-traversal is the exact walker semantic.

### 5. Patient Zero — 39.0 (Social Impact)
Judges seed a live misinformation outbreak from their phones (QR → POST); rumor text mutates telephone-game style at every hop across a 300-person synthetic social graph; FactChecker walker traverses `heard` edges backwards to announce "patient zero: seat 3," then plants corrections that bend the infection curve.
**Why judges liked it:** best audience-participation moment in the batch. Risk: live QR input — rehearse the presenter-typed fallback.

### 6. Clausewitz — 38.0 (Fintech)
Contract graph where defined terms are first-class nodes. Edit the definition of "Active User" → RippleWalker traverses `uses` edges, gets a typed LLM impact verdict at each clause, and continues **only where impact is material** — LLM judgment gates the traversal frontier (deepest walker+byLLM fusion in the list). Cross-document consequences no lawyer would catch, plus drafted redlines.

### 7. Retcon — 37.7 (Agentic AI, most original)
Live writers' room: character agents with secret goals grow a story; facts and who-knows-what are edges. Audience shouts a twist ("the detective has been blind since chapter one") → continuity walkers flare every scene it breaks → Repairman rewrites exactly those scenes until the graph goes green.

## The rest (8–22)

| # | Score | Track | Idea |
|---|-------|-------|------|
| 8 | 36.7 | Social | **MindTheGap** — tutor walker descends a prerequisite DAG asking micro-questions until it finds the real gap "four grade levels down"; mastery map persists across restarts |
| 9 | 36.7 | Social | **Waterline** — contamination walkers trace a city water-pipe graph downstream to warn exactly who's affected |
| 10 | 35.3 | Agentic | **Cordon** — adversarial LLM pathogen walker vs. containment agents on a contact-tracing graph |
| 11 | 35.3 | Agentic | **Jaccuse!** — procedural murder mystery as an evidence graph; lying suspect agents; detective walker |
| 12 | 35.0 | Fintech | **LineTrace** — your tax return as a dataflow graph; "why did my refund drop $2,143?" answered by a diff-walker |
| 13 | 34.0 | Social | **LandlordLens** — walkers pivot through shell-company registration edges to unmask your landlord's network |
| 14 | 33.7 | Agentic | **Keeper** — maps which knowledge in a git repo lives only in one person's head (bus-factor graph) |
| 15 | 33.3 | Fintech | **Waterfall** — cap-table time machine: SAFEs/term sheets become a live equity graph with exit simulations |
| 16 | 33.3 | Social | **CurbCut** — mark one broken subway elevator, see the blast radius on every wheelchair user's trip graph |
| 17 | 33.0 | Fintech | **X-Ray** — walker tunnels through ETF-of-ETF holdings to show your true portfolio concentration |
| 18 | 32.7 | Agentic | **Aftershock** — scout/medic/logistics agent swarm self-organizes over an earthquake-damaged city graph |
| 19 | 32.0 | Social | **Emberline** — wildfire evacuation drill; fire, households, and dispatcher are all walkers |
| 20 | 31.7 | Agentic | **CrossExam** — prosecutor vs. defender agents duel by growing a live argument graph |
| 21 | 31.3 | Fintech | **The Floor** — port closes; buyer/supplier agents renegotiate broken supply-chain contracts |
| 22 | 30.7 | Fintech | **Tulip Mania** — 15 LLM trader personas on a follow-graph; watch a bubble inflate and pop |

## Round-1 ideas (from earlier, not re-judged)

RootCause (incident RCA over service graph) · Subscription Bloodhound (bank-statement money graph) · SafetyNet Navigator (benefits eligibility graph) · mutual-aid matcher · invoice reconciliation agent · living research knowledge graph.

## Syntax gotchas for jaclang 0.16.x (verified locally)

- Root trigger: `can start with Root entry` (NOT backtick `` `root ``)
- Type filter: `visit [-->[?:NodeType]]` (NOT `(`?Type)`)
- Persistence is automatic in a `.jac/` folder next to your file — delete it for a fresh graph during dev
- byLLM: `import from byllm.llm { Model }`, `glob llm = Model(model_name="gemini/gemini-2.5-flash");`
- Working examples: `jac-demo/money_graph.jac`, `jac-demo/byllm_spin.jac`
