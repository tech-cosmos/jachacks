# Continuity Walker

**Finds provable plot holes in movie and TV scripts.** Built in
[Jac](https://github.com/jaseci-labs/jac) at JacHacks SF 2026.

## The idea

Every scene both **establishes** facts and **requires** facts. A plot hole is a
scene requiring something the accumulated canon graph doesn't support.

We only claim **state contradictions** — an object/person/system is established
in state X, a later scene requires state Y, and no transition exists in
between. That's objective and provable: the walker's traversal path *is* the
proof. (Subjective "why didn't they just…" logic holes are explicitly out of
scope.)

Paste a screenplay into a raw LLM and ask for plot holes: you get five
confident answers, three hallucinated, and a different five next run. Our
output comes with the exact chain of scenes that makes it true.

## How it works (all in Jac)

1. **Extract** — one byLLM call per scene returns typed
   `establishes[] / requires[]` fact triples (subject, predicate, value).
2. **Accrete** — facts attach to a persistent canon graph (Jac's built-in
   persistence — canon survives across runs and across episodes, zero DB code).
3. **Audit** — the `Auditor` walker checks each requirement against the most
   recent canon state for that subject+predicate, hunting for a reconciling
   transition.
4. **Adjudicate** — only mismatches get a second byLLM call, which kills false
   positives (and powers the live "withdraw the finding" demo).

## Run it

```sh
pip install jaclang byllm         # plus GEMINI_API_KEY in env
jac run main.jac ingest data/home_alone_ep1.txt
jac run main.jac ingest data/home_alone_ep2.txt
jac run main.jac audit            # → the Home Alone phone-line plot hole
jac run main.jac canon            # inspect accumulated canon
jac run main.jac score            # extraction accuracy vs annotated key facts
jac run main.jac ingest data/home_alone_amendment.txt   # the fan defense
jac run main.jac audit            # → watch the finding get withdrawn
```

`CW_NO_LLM=1` runs the graph pipeline on annotated facts only (no API calls);
`CW_MODEL` overrides the default `gemini/gemini-2.5-flash`.

Scene files are plain text: `## SCENE n` headers + prose. Optional `@expect`
lines are *not* shown to the LLM — they're ground truth used to score
extraction accuracy.
