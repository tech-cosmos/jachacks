# Continuity Walker

**Finds plot holes in movies and TV.** Ingests a script scene by scene, accumulates a
persistent canon graph, and finds the exact chain that makes a later scene impossible.

**Scope for today: scripts only.** The schema is deliberately domain-neutral so the engine
can extend to other document types later (see Future Work), but nothing else gets built or
demoed today.

JacHacks SF — July 26, 2026. Target track: Agentic AI (fallback: Open).

---

## The core mechanic, in one sentence

**Every scene both *establishes* facts and *requires* facts.** A plot hole is a scene
requiring something the accumulated canon doesn't support.

That's the whole product. Everything else is plumbing.

---

## What we detect, and what we don't

**State contradictions — our product.** An object, person, or system is established in
state X; a later scene requires state Y; no transition exists in between. Objective and
provable.

**Logic holes — not our product.** "Why didn't they just fly the eagles to Mordor?"
Subjective, arguable, unsolvable by state tracking. Most *famous* plot holes are this
kind, so a judge will ask.

The answer: logic holes are matters of opinion, state contradictions are provable — and
provability is exactly what separates our output from a model that confidently invents
five plot holes and a different five if you ask again.

---

## Why this is a Jac project

- **The traversal is the reasoning.** Proving a contradiction means proving *no* path of
  legal transitions reconciles two states. That's a path search, not a lookup. A hashmap
  of entity states can't do it.
- **The graph is the memory.** Canon accumulates across episodes via Jac's built-in
  persistence. Episode 4 is checked against a graph built from episodes 1–3. No database
  code.
- **The path is the explanation.** What the walker traversed is what we print as proof.
  Output is auditable, which is the entire trust argument versus a raw LLM.
- **byLLM does the genuinely hard part** — turning prose into typed structured facts —
  and nothing else.

### The flat-list attack, and why it fails

Paste a 40-scene screenplay into a frontier model and ask for plot holes: you get five
confident answers, three hallucinated, and a different five on the next run. That's a
**capability** failure, not a fairness failure — which is what makes it survive judge
skepticism.

**This is also the demo.** Run it live, side by side.

---

## Schema

Named domain-neutrally on purpose — costs nothing today, preserves the extension path.
Nothing in the schema knows it's a story.

### Nodes

| Node | Holds |
|---|---|
| `Document` | title, kind, version |
| `Segment` | **order** (scene index), prose |
| `Entity` | character, object, place |
| `State` | a claim: subject, predicate, value (`phone / status / down`) |
| `Violation` | the contradiction + its proof path |

### Edges

| Edge | Meaning |
|---|---|
| `Establishes` (Segment → State) | this scene makes it true |
| `Requires` (Segment → State) | this scene presupposes it |
| `Transition` (State → State) | a legal change — possession moved, repaired, someone learned something |
| `Supersedes` (State → State) | later fact overrides earlier |

`State` covers more than objects: entity status (alive/destroyed), system status (phone
working), character biography, and **world rules** (vampires don't breathe).

---

## Pipeline

1. **Extract** — one byLLM call per scene: `extract(text) -> SegmentFacts` returning
   `establishes[]` and `requires[]`. Typed return, so we get structure not prose.
2. **Accrete** — facts attach to the persistent canon graph, surviving across episodes.
3. **Audit** — the `Auditor` walker runs on each new scene's `requires`.
4. **Adjudicate** — only for candidate violations:
   `judge(requirement, evidence_path) -> Verdict`. This is what kills false positives.

### What the `Auditor` walker does

For each requirement in a new scene, walk backward through canon:

- Find the most recent `State` for that subject+predicate.
- **Match?** Supported — stop. (Cheap; most requirements pass here.)
- **Mismatch?** Search for a `Transition` path that could reconcile the two.
- **No path exists?** Candidate violation → send the traversed path to the adjudicator.

---

## Real test cases

Using real films beats synthetic data: judges can verify the results themselves.

### Primary demo — Home Alone (1990), the phone line

| | |
|---|---|
| Scene ~15 | Storm downs a tree branch across the phone line. `Establishes: (mccallister_phone, status, down)` |
| Later | Phone company confirms the outage — reinforces the state |
| Scene ~30 | Kevin orders a pizza by telephone. `Requires: (mccallister_phone, status, working)` |
| Between | **No repair event anywhere in the script** |

Universally known, small enough to feel like a fair catch rather than a takedown, and a
textbook state contradiction.

**The showstopper beat.** The leading fan defense is that only *long-distance* lines were
damaged — an AT&T VP confirmed that was a real 1990 distinction. So on stage: add one
line of dialogue to canon establishing local lines are unaffected, re-run, and **watch
the system withdraw its own finding.** Fifteen seconds, and it proves reasoning over
pattern-matching better than anything else in the demo.

### Cross-episode persistence beat

Need one where canon from earlier episodes is violated later:

- **Game of Thrones — the Dothraki.** Grey Worm explicitly confirms they were wiped out
  at Winterfell; they appear en masse at King's Landing. Entity-population state, recent,
  everybody knows it.
- **Star Trek: DS9 — Sisko's father.** Season 2 implies he's dead; later episodes have him
  alive running a restaurant in New Orleans. The canonical "writers' room forgot."
- **Buffy — vampires don't breathe** (S1), then they smoke, talk, and get strangled.
  A *world rule* node rather than an object — shows schema range.
- **The Golden Girls — Rose** is high school valedictorian in one episode, a dropout who
  later got a GED in another. Character-biography state, very clean.

### Decoys — real near-misses with published explanations

These prove precision. The system should decline to flag them, or flag them as resolvable.

- **Back to the Future** — why don't Marty's parents recognize him? Screenwriter Bob Gale
  explicitly rebutted this: six days, thirty years, no photos. A plausibility complaint,
  not a contradiction.
- **Home Alone long-distance** — as above.
- **Star Wars — Leia remembering her mother.** Return of the Jedi has her recall Padmé,
  who dies minutes after childbirth in Revenge of the Sith. Real cross-film contradiction,
  but arguably resolvable through the Force. Good for a *graded* verdict rather than binary.

**Scoreboard claim:** "3 real contradictions found, 2 documented near-misses correctly
declined." Beats any synthetic accuracy number because judges can check it.

---

## Demo (4 minutes)

1. Canon graph after episodes 1–2.
2. Ingest episode 3 → violations pop with their proof paths.
3. Side by side against a raw frontier-model answer on the same script.
4. The Home Alone withdraw-the-finding interaction.
5. Score card: contradictions found, near-misses declined, extraction accuracy.

Mention the wider applicability in one closing sentence. **Do not demo it.**

---

## Build order

| Time | Work |
|---|---|
| 10:45 | Repo, commit, README — they audit commit history |
| 11:00 | Jac workshop — do not skip |
| 12:00 | Schema in Jac + first script as prose (~12 scenes) |
| 1:00 | Extractor byLLM — eyeball the facts it produces |
| **2:00** | **GO/NO-GO on extraction quality** |
| 2:00–3:30 | Canon builder + `Auditor` walker, exact-match only, no LLM |
| 3:30–4:30 | Load real test cases, measure precision |
| 4:30–5:00 | Episodes 2–3 → the persistence beat |
| 5:00–5:50 | **Freeze. Partial Devpost submit — mandatory to be judged** |
| 5:50–6:45 | Thin viz + side-by-side vs. raw LLM |
| 6:45–7:15 | Record demo video (≤1:30), final submit |

Get the walker working on exact-match contradictions **before** adding the LLM
adjudicator — a rate limit at 6 PM should cost precision, not the demo.

---

## Risks

**Extraction accuracy is the whole project.** At 90% accuracy we emit false positives, and
a plot-hole finder that cries wolf is worse than useless. Don't dodge this by feeding the
system our own structured JSON — extract from real prose and *report the extraction
accuracy as a number*. That turns the biggest weakness into a second metric.

**2 PM go/no-go.** The risk is front-loaded and testable early. If extraction doesn't hold
on one script by 2 PM, fall back to structured scene input: weaker demo, still ships,
still finds the hole.

**Don't chase generality today.** The schema is generic; the build is not. Any hour spent
on a second domain is an hour not spent making the script demo airtight.

**Keep the graph big enough to be impressive.** Nodes are data, not code. A graph a judge
can solve by eye makes the walker look pointless.

**40% Jac ratio.** All logic in Jac — schema, walkers, extraction calls, audit, scoring.
Frontend is one HTML file with Cytoscape from a CDN polling the `jac start` API. GitHub
Linguist may not recognize `.jac`, so be ready to state the ratio ourselves in the
submission.

---

## Future work — not today

Everything here is one extraction prompt away, because the schema is already domain-neutral.
Worth one line on the Devpost; worth zero hours today.

### Other document types

Contracts + amendments, policy handbooks, technical specs, requirements docs. Versioned
document sets preserve the temporal structure exactly — **amendments are episodes**, so
every walker transfers unchanged.

Bad fits: news articles and scientific papers as *sources*. Reconciling contradictions
across independent sources is a truth-seeking problem, not a consistency problem.

### Citation contamination (the strongest extension)

When a paper is retracted, which papers downstream actually break?

The real numbers: **75.3% of retracted articles keep getting cited** a year after
retraction; post-retraction citations persist **over 10 years**; **over 85% of them are
positive**, never mentioning the retraction. Retraction Watch has ~62,000 retracted papers
openly available. Case study: **Lesné et al. 2006, Nature** — the Aβ*56 Alzheimer's paper,
retracted July 2024 after image manipulation, one of the most-cited in its field.

The insight that makes it a graph+AI problem: **not every citation is load-bearing.** A
background citation in an intro survives a retraction; a method that calibrates against the
retracted result does not. Same edge, different consequence — the graph gives reach, the
LLM gives load-bearing-ness. Contamination then propagates **only along load-bearing edges,
and attenuates**: if A cites B only for background, the taint stops at B.

Prior art to know: **scite.ai** already classifies citation intent commercially. The
differentiator is multi-hop propagation with attenuation, which it doesn't do.

Cheap way in, if ever revisited: hand-build a ~15-node citation subgraph around one famous
retraction. Don't integrate an API — nodes are data, not code.

### Visual continuity

Vanishing props, refilling popcorn bowls — errors no script-based system can see. Would
need video understanding (TwelveLabs or similar). Note that plot holes live in *dialogue
and stated facts*, so video is the harder modality for the core problem; its real value is
this separate class of error.

---

## Submission checklist

- [ ] Partial Devpost submission by **5:50 PM** (mandatory to be judged)
- [ ] Final submission by **7:15 PM** sharp
- [ ] Demo video ≤ 1:30
- [ ] Star https://github.com/jaseci-labs/jac (on the official checklist)
- [ ] Commit history shows work starting 10:45 AM, not before
- [ ] Jac ratio ≥ 40%, and we can state the number

---

## Sources

- [Bustle — Home Alone phone plot hole](https://www.bustle.com/entertainment/home-alone-plot-hole-fans-reddit)
- [HuffPost — the long-distance explanation](https://www.huffpost.com/entry/home-alone-plot-hole-has-logical-explanation_n_560be46de4b0dd850309e9bc)
- [CBR — Bob Gale on Back to the Future](https://www.cbr.com/screenwriter-explains-marty-parents-forgetting-him-plot-hole-back-to-the-future/)
- [ScreenRant — Leia and Padmé](https://screenrant.com/star-wars-leia-padme-mother-plot-hole-explained/)
- [Stacker — TV continuity errors](https://stacker.com/stories/tv/glaring-continuity-errors-25-popular-tv-series)
- [CBR — continuity errors in acclaimed TV](https://www.cbr.com/popular-tv-shows-huge-plot-holes/)
- [TV Tropes — Series Continuity Error](https://tvtropes.org/pmwiki/pmwiki.php/SeriesContinuityError)
- [Nature — Retraction Note, Lesné et al.](https://www.nature.com/articles/s41586-024-07691-8)
- [MIT QSS — continued use of retracted papers](https://direct.mit.edu/qss/article/2/4/1144/107356/Continued-use-of-retracted-papers-Temporal-trends)
- [Jac docs](https://docs.jaseci.org/) · [byLLM agentic AI](https://docs.jaseci.org/learn/jac-byllm/agentic_ai/)
