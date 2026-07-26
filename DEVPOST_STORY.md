# Devpost story — paste into "About the project"

## Inspiration

We pasted Home Alone into a frontier model and asked for plot holes. It gave us 13. We asked again and got a different 10, most of them subjective nitpicks, none with evidence. (That experiment ships in our repo as the `naive` command.) The problem isn't model quality. Checking scene 40 against scenes 1–39 is reasoning over accumulated state, and a context window is not state. Jac's thesis, that state lives in a persistent graph and computation walks to it, supplies the missing half.

## What it does

Every scene **establishes** facts and **requires** facts, each a typed triple $(s, p, v)$. A plot hole is a requirement the accumulated canon can't support:

$$\text{violation}(r) \iff r = (s,p,v) \;\wedge\; \text{latest}_{<t}(s,p) = v' \;\wedge\; v' \neq v \;\wedge\; \nexists\, \text{transition } v' \to v$$

Continuity Walker extracts facts scene by scene with byLLM, accretes them into a persistent canon graph, and an `Auditor` walker checks each requirement against the latest canon state, hunting for a reconciling transition. Survivors get one more byLLM call, judged against the exact timeline the walker traversed. The traversal is the proof, and we print it.

Confirmed on real material: Home Alone's phone (downed in the storm, never repaired, Kevin orders pizza anyway), the Dothraki charging at King's Landing two episodes after being wiped out, and a contract amendment that relies on Net-30 terms an earlier amendment changed to Net-45. Add the classic fan defense (only long-distance lines were down, a real 1990 distinction) and the system withdraws its own finding on re-audit. Wording near-misses get declined, not flagged. Movies, TV seasons, and contract chains coexist under `# CANON:` scopes, and an Amendment Desk files or retracts documents against any world.

## How we built it

One `main.jac` file holds the schema (`Document`, `Segment`, `State`, `Violation` nodes; `Establishes`, `Requires`, `Transition`, `Supersedes` edges), the walkers, the typed byLLM functions, and the HTTP server, subclassed from Python's `BaseHTTPRequestHandler` through Jac interop. 1,632 of 2,490 lines are Jac (~66%). Persistence comes free: canon survives across runs, so an episode is audited against a graph built hours earlier. Extraction runs on deepseek-v4-flash ($0.14/M tokens, about $0.10 for our 139-scene corpus). Adjudication runs on Sonnet, because verdicts are few and precision matters. A `CW_BACKEND=claude` mode routes everything through the Claude CLI on a subscription with no API key at all. Canon exports to a 32 KB JSON that teammates import and replay with zero LLM calls.

## Challenges we ran into

1. Extraction wants to heal the holes it should expose. "Client shall continue to be entitled to the Net-30 discount" reads like it establishes Net-30. We prompt referencing ≠ enacting, and a clause's own establishes are excluded from its requirement's evidence: it can't vouch for itself.
2. Early audits flagged every location mismatch ("Kevin required at home, canon says grocery store"). People move; phone lines don't fix themselves. Location mismatches are declined by rule, and multi-valued predicates like knowledge never flag. You can know two things at once.
3. Global canon collided. Final Destination 3 has a Kevin too, and he inherited Home Alone Kevin's timeline. Documents now declare canon scopes.
4. A cheap judge is a bad judge. DeepSeek confirmed "required true, canon says alive" as a contradiction; Sonnet never did. So: cheap model for bulk extraction, strong model for scarce verdicts, and verdicts cached per evidence state so a finding only changes when canon changes.
5. Hackathon grit: free-tier Gemini allows 5 requests a minute, jac f-strings mangle nested quotes, and episode titles containing quotes broke our own dropdowns.

## Accomplishments that we're proud of

- On a full transcript we uploaded and never curated (Final Destination 3), it found a contradiction we hadn't planted: the ride camera established down in scene 7, used in scene 9, no repair between. Proof path attached.
- The live withdrawal beat: one line of canon added on stage, and the system retracts its own finding for the right reason ("the pizza call is local").
- We publish our weakest number. `score` prints extraction accuracy against annotated ground truth (63–77% depending on extractor) instead of hiding it.
- The entire backend, web server included, is one Jac file.

## What we learned

- Give the LLM a graph and it stops hallucinating memory. Two narrow byLLM calls plus a walker beat a frontier model holding the whole script, and they produce evidence instead of vibes.
- Confine the adjudicator to the walker's timeline ("did any instrument restore this term?") and unstable answers become stable verdicts.
- The schema never knew it was about stories. Contracts ran on the same nodes and edges with only prompt changes.

## What's next for Continuity Walker

Deposition transcripts (testimony contradicting prior testimony), patient charts (discharge instructions requiring discontinued meds), and the one we want most: a continuity firewall for AI-generated fiction, vetoing scene $n$ against the canon of scenes $1$ through $n-1$.
