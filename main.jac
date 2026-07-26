"""Continuity Walker — finds provable state contradictions in scripts.

Every scene both ESTABLISHES facts and REQUIRES facts. A plot hole is a scene
requiring something the accumulated canon graph doesn't support.

Usage:
    jac run main.jac ingest data/home_alone_ep1.txt
    jac run main.jac audit
    jac run main.jac report
    jac run main.jac canon
    jac run main.jac score
    jac run main.jac reset
"""

import sys;
import os;
import time;
import litellm;
import from byllm.llm { Model }

def pick_model() -> str {
    m = os.environ.get("CW_MODEL", "");
    if m != "" {
        return m;
    }
    if os.environ.get("OPENROUTER_API_KEY", "") != "" {
        return "openrouter/anthropic/claude-sonnet-5";
    }
    return "gemini/gemini-2.5-flash";
}

glob llm = Model(model_name=pick_model());

# ---------------------------------------------------------------- typed facts

obj Fact {
    has subject: str;
    has predicate: str;
    has value: str;
}

obj SceneFacts {
    has establishes: list[Fact];
    has requires: list[Fact];
}

obj Verdict {
    has is_contradiction: bool;
    has confidence: str;
    has reasoning: str;
}

"""Extract concrete STATE facts from one scene of a screenplay.

establishes: facts this scene makes true from now on — events that set or
change state (an object breaks or is repaired, a system goes down or comes
back, someone moves, dies, learns something, gains or loses possession of
something, or a rule of the story world is stated).

requires: facts that must ALREADY be true for this scene's action to be
physically possible — its load-bearing preconditions. When a character
successfully USES a device, service, or arrangement on screen, you MUST emit a
requires fact that it is in working/available state (making a call requires
the phone working; springing a trap requires the trap set). When a character
or group fights, marches, or otherwise acts on screen and their survival
could be in doubt, emit a requires that they are alive / intact. When action
depends on where someone is or what they know, emit that too. Most scenes
have 1-2 requires. Exceptions: do not emit a requires fact that this same
scene itself creates or destroys — a scene where the phone line is torn down
does not "require" the phone working. Only emit a location requirement if the
action depends on someone already being in that place when the scene STARTS,
never for where they end up.

Rules:
- subject: canonical snake_case id of the plain entity or system, e.g.
  "mccallister_phone" (not "mccallister_phone_service"), "kevin". You MUST
  reuse an id from known_subjects when the scene refers to the same thing,
  even if worded differently.
- predicate: one lowercase word such as status / location / possession /
  alive / knowledge / plan. Reuse from known_predicates when it is the same
  kind of claim.
- value: SHORT — one or two lowercase words joined by underscore
  ("paris_trip", not "christmas_trip_to_paris"). For whether a device or
  service works, use exactly "working" or "down".
- Only objectively checkable states. No opinions, themes, or predictions.
- Return 2-6 establishes and 0-3 requires; only the load-bearing ones.
"""
def extract_facts(scene: str, known_subjects: list[str],
                  known_predicates: list[str]) -> SceneFacts by llm();

"""You are adjudicating a candidate continuity error in one continuous story.
The canon timeline lists, in story order, every state the script ever
established for the relevant subjects. The requirement comes from a later
scene that needs a specific state to be true.

Rules of adjudication:
- The story world changes ONLY when a scene establishes the change. If the
  latest canon state contradicts the requirement and NO fact in the timeline
  establishes a reconciling change, that IS a contradiction. Do not invent
  off-screen repairs, resets, or passage-of-time fixes, no matter how mundane
  or plausible — an unwritten fix is exactly what a continuity error is.
- It is NOT a contradiction if a fact in the timeline itself makes the
  requirement satisfiable (e.g. a partial outage that explicitly leaves the
  required kind of use working).
- It is NOT a contradiction if the mismatch is pure wording — both values
  describe the same real state (e.g. broken vs down, home vs house).
- Characters and movable things relocate under their own or others' agency
  without needing a scene to show it: a LOCATION mismatch is only a
  contradiction if canon makes the move impossible (dead, imprisoned,
  destroyed). By contrast, device/service/system states (working vs down),
  life status, and established world rules change ONLY via an establishing
  scene — someone must be shown fixing, breaking, or revoking them.
confidence is one of high / medium / low."""
def adjudicate(requirement: str, canon_timeline: str,
               scene_excerpt: str) -> Verdict by llm();

# --------------------------------------------------------------------- graph

node Document {
    has title: str;
    has kind: str;
    has doc_index: int;
}

node Segment {
    has order: float;
    has doc_index: int;
    has prose: str;
    has exp_total: int = 0;
    has exp_matched: int = 0;
}

node State {
    has subject: str;
    has predicate: str;
    has value: str;
    has doc_index: int;
    has seg_order: float;
}

node Violation {
    has subject: str;
    has predicate: str;
    has required_value: str;
    has found_value: str;
    has req_doc: int;
    has req_seg: float;
    has timeline: str;
    has status: str;
    has confidence: str = "";
    has reasoning: str = "";
}

edge Establishes {}
edge Requires {}
edge Transition {}
edge Supersedes {}

# ------------------------------------------------------------------- helpers

def norm(s: str) -> str {
    return s.strip().lower().replace(" ", "_").replace("-", "_");
}

def skey(doc_index: int, order: float) -> float {
    return doc_index * 100000.0 + order;
}

def fmt_scene(order: float) -> str {
    if order == int(order) {
        return str(int(order));
    }
    return str(order);
}

def all_documents() -> list {
    return sorted([root -->[?:Document]], key=lambda d: Document : d.doc_index);
}

def all_segments() -> list {
    segs = [];
    for d in all_documents() {
        segs.extend([d -->[?:Segment]]);
    }
    return sorted(segs, key=lambda s: Segment : skey(s.doc_index, s.order));
}

def all_established() -> list {
    states = [];
    for s in all_segments() {
        states.extend([s ->:Establishes:->]);
    }
    return sorted(states, key=lambda st: State : skey(st.doc_index, st.seg_order));
}

def doc_title(doc_index: int) -> str {
    for d in all_documents() {
        if d.doc_index == doc_index {
            return d.title;
        }
    }
    return f"doc {doc_index}";
}

def related(a: str, b: str) -> bool {
    na = norm(a);
    nb = norm(b);
    if na == nb {
        return True;
    }
    return na.startswith(nb) or nb.startswith(na);
}

def timeline_for(subject: str, states: list) -> str {
    lines = [];
    for st in states {
        if related(st.subject, subject) {
            lines.append(
                f"  [{doc_title(st.doc_index)} — scene {fmt_scene(st.seg_order)}] "
                f"{st.subject} {st.predicate} = {st.value}");
        }
    }
    if len(lines) == 0 {
        return "  (no canon at all for this subject)";
    }
    return "\n".join(lines);
}

def fuzzy(a: str, b: str) -> bool {
    if norm(a) == norm(b) {
        return True;
    }
    ta = set(norm(a).split("_"));
    tb = set(norm(b).split("_"));
    inter = len(ta.intersection(tb));
    if inter == 0 {
        return False;
    }
    return inter >= 2 or inter == min(len(ta), len(tb));
}

def share_token(a: str, b: str) -> bool {
    ta = set(norm(a).split("_"));
    tb = set(norm(b).split("_"));
    return len(ta.intersection(tb)) >= 1;
}

def fact_match(e: Fact, g: Fact) -> bool {
    return share_token(e.subject, g.subject)
        and norm(e.predicate) == norm(g.predicate)
        and fuzzy(e.value, g.value);
}

def safe_extract(prose: str, ks: list, kp: list) -> SceneFacts {
    delay = float(os.environ.get("CW_DELAY", "0"));
    if delay > 0 {
        time.sleep(delay);
    }
    attempt = 0;
    while attempt < 3 {
        try {
            return extract_facts(prose, ks, kp);
        } except Exception as e {
            attempt += 1;
            print(f"      ! extraction error, attempt {attempt}: {str(e)[:100]}");
            time.sleep(15.0 * attempt);
        }
    }
    return SceneFacts(establishes=[], requires=[]);
}

def safe_adjudicate(requirement: str, tl: str, excerpt: str) -> Verdict {
    delay = float(os.environ.get("CW_DELAY", "0"));
    if delay > 0 {
        time.sleep(delay);
    }
    attempt = 0;
    while attempt < 3 {
        try {
            return adjudicate(requirement, tl, excerpt);
        } except Exception as e {
            attempt += 1;
            print(f"  ! adjudication error, attempt {attempt}: {str(e)[:100]}");
            time.sleep(15.0 * attempt);
        }
    }
    return Verdict(is_contradiction=True, confidence="unadjudicated",
                   reasoning="exact-match mismatch; adjudicator unavailable");
}

def to_order(tag: str, fallback: float) -> float {
    t = tag.strip();
    if t.replace(".", "", 1).isdigit() {
        return float(t);
    }
    return fallback;
}

# ------------------------------------------------------------ script parsing

obj SceneData {
    has order: float;
    has prose: str;
    has exp_est: list;
    has exp_req: list;
}

obj ScriptData {
    has title: str;
    has kind: str;
    has scenes: list;
    has vocab: list;
}

def parse_script(path: str) -> ScriptData {
    f = open(path, "r");
    text = f.read();
    f.close();
    title = path;
    kind = "script";
    vocab = [];
    for raw in text.split("\n") {
        line = raw.strip();
        if line.startswith("# TITLE:") {
            title = line[8:].strip();
        } elif line.startswith("# KIND:") {
            kind = line[7:].strip();
        } elif line.startswith("# VOCAB:") {
            vocab = [norm(v) for v in line[8:].split(",") if v.strip() != ""];
        }
    }

    scenes = [];
    chunks = text.split("## SCENE");
    counter = 0.0;
    for chunk in chunks[1:] {
        lines = chunk.split("\n");
        counter += 1.0;
        order = to_order(lines[0], counter);
        prose_lines = [];
        est = [];
        req = [];
        for raw in lines[1:] {
            line = raw.strip();
            if line.startswith("@expect") {
                parts = line[7:].strip().split(" ", 1);
                if len(parts) == 2 {
                    trip = [p.strip() for p in parts[1].split("|")];
                    if len(trip) == 3 {
                        fact = Fact(subject=trip[0], predicate=trip[1],
                                    value=trip[2]);
                        if parts[0] == "establishes" {
                            est.append(fact);
                        } else {
                            req.append(fact);
                        }
                    }
                }
            } elif line.startswith("# TITLE:") or line.startswith("# KIND:")
                or line.startswith("# VOCAB:") {
                continue;
            } else {
                prose_lines.append(raw);
            }
        }
        scenes.append(SceneData(order=order, prose="\n".join(prose_lines).strip(),
                                exp_est=est, exp_req=req));
    }
    return ScriptData(title=title, kind=kind, scenes=scenes, vocab=vocab);
}

# ------------------------------------------------------------------- walkers

walker Ingest {
    has path: str;

    can go with Root entry {
        script = parse_script(self.path);
        docs = all_documents();
        doc = None;
        for d in docs {
            if d.title == script.title {
                doc = d;
            }
        }
        if doc is None {
            doc = Document(title=script.title, kind=script.kind,
                           doc_index=len(docs));
            here ++> doc;
            print(f"+ document [{doc.doc_index}] {doc.title}");
        } else {
            print(f"= document [{doc.doc_index}] {doc.title} (appending)");
        }

        no_llm = os.environ.get("CW_NO_LLM", "") == "1";
        existing_orders = [s.order for s in [doc -->[?:Segment]]];
        states = all_established();
        known_subj = sorted(set([st.subject for st in states] + script.vocab));
        known_pred = sorted(set([st.predicate for st in states]
                                + ["status", "location", "possession", "alive",
                                   "knowledge", "plan"]));

        for sc in script.scenes {
            if sc.order in existing_orders {
                print(f"  scene {fmt_scene(sc.order)}: already ingested, skipping");
                continue;
            }
            if no_llm {
                facts = SceneFacts(establishes=sc.exp_est, requires=sc.exp_req);
                print(f"  scene {fmt_scene(sc.order)}: structured mode "
                      f"({len(sc.exp_est)} est, {len(sc.exp_req)} req)");
            } else {
                facts = safe_extract(sc.prose, sorted(set(known_subj)),
                                     sorted(set(known_pred)));
                if len(facts.establishes) == 0 and len(facts.requires) == 0
                    and len(sc.exp_est) + len(sc.exp_req) > 0 {
                    facts = SceneFacts(establishes=sc.exp_est, requires=sc.exp_req);
                    print(f"  scene {fmt_scene(sc.order)}: extraction failed, "
                          f"using annotated facts");
                } else {
                    print(f"  scene {fmt_scene(sc.order)}: extracted "
                          f"{len(facts.establishes)} est, {len(facts.requires)} req");
                }
            }

            seg = Segment(order=sc.order, doc_index=doc.doc_index, prose=sc.prose);
            doc ++> seg;

            for fc in facts.establishes {
                st = State(subject=norm(fc.subject), predicate=norm(fc.predicate),
                           value=norm(fc.value), doc_index=doc.doc_index,
                           seg_order=sc.order);
                seg +>:Establishes:+> st;
                prev = None;
                for old in all_established() {
                    if old is not st and old.subject == st.subject
                        and old.predicate == st.predicate
                        and skey(old.doc_index, old.seg_order) < skey(st.doc_index, st.seg_order) {
                        if prev is None
                            or skey(old.doc_index, old.seg_order) > skey(prev.doc_index, prev.seg_order) {
                            prev = old;
                        }
                    }
                }
                if prev is not None and prev.value != st.value {
                    prev +>:Transition:+> st;
                    st +>:Supersedes:+> prev;
                }
                print(f"      + {st.subject} {st.predicate} = {st.value}");
                known_subj.append(st.subject);
                known_pred.append(st.predicate);
            }
            for fc in facts.requires {
                st = State(subject=norm(fc.subject), predicate=norm(fc.predicate),
                           value=norm(fc.value), doc_index=doc.doc_index,
                           seg_order=sc.order);
                seg +>:Requires:+> st;
                print(f"      ? {st.subject} {st.predicate} = {st.value}");
            }

            if not no_llm {
                expected = sc.exp_est + sc.exp_req;
                got = facts.establishes + facts.requires;
                matched = 0;
                for e in expected {
                    for g in got {
                        if fact_match(e, g) {
                            matched += 1;
                            break;
                        }
                    }
                }
                seg.exp_total = len(expected);
                seg.exp_matched = matched;
                if len(expected) > 0 {
                    print(f"      accuracy: {matched}/{len(expected)} key facts");
                }
            }
        }
    }
}

walker Auditor {
    has quiet: bool = False;

    can go with Root entry {
        no_llm = os.environ.get("CW_NO_LLM", "") == "1";
        states = all_established();
        segs = all_segments();

        old_viols = [here -->[?:Violation]];
        vmap = {};
        for v in old_viols {
            vmap[f"{v.subject}|{v.predicate}|{v.req_doc}|{v.req_seg}"] = v;
        }
        seen = [];
        n_supported = 0;
        n_nocanon = 0;

        for seg in segs {
            for req in [seg ->:Requires:->] {
                hist = [];
                for st in states {
                    if st.subject == req.subject and st.predicate == req.predicate
                        and skey(st.doc_index, st.seg_order) < skey(seg.doc_index, seg.order) {
                        hist.append(st);
                    }
                }
                if len(hist) == 0 {
                    n_nocanon += 1;
                    continue;
                }
                latest = hist[-1];
                if latest.value == req.value {
                    n_supported += 1;
                    continue;
                }

                key = f"{req.subject}|{req.predicate}|{seg.doc_index}|{seg.order}";
                seen.append(key);
                tl = timeline_for(req.subject, states);
                requirement = (f"Scene {fmt_scene(seg.order)} of "
                               f"'{doc_title(seg.doc_index)}' requires: "
                               f"{req.subject} {req.predicate} = {req.value}");

                if no_llm {
                    status = "candidate";
                    confidence = "";
                    reasoning = "exact-match mismatch (LLM adjudication off)";
                } else {
                    verdict = safe_adjudicate(requirement, tl, seg.prose[:400]);
                    if verdict.confidence == "unadjudicated" {
                        status = "candidate";
                    } elif verdict.is_contradiction {
                        status = "confirmed";
                    } else {
                        status = "declined";
                    }
                    confidence = verdict.confidence;
                    reasoning = verdict.reasoning;
                }

                if key in vmap {
                    v = vmap[key];
                    if v.status in ["confirmed", "candidate"] and status == "declined" {
                        status = "withdrawn";
                    }
                    v.status = status;
                    v.found_value = latest.value;
                    v.timeline = tl;
                    v.confidence = confidence;
                    v.reasoning = reasoning;
                } else {
                    v = Violation(subject=req.subject, predicate=req.predicate,
                                  required_value=req.value, found_value=latest.value,
                                  req_doc=seg.doc_index, req_seg=seg.order,
                                  timeline=tl, status=status,
                                  confidence=confidence, reasoning=reasoning);
                    here ++> v;
                }
            }
        }

        for k in vmap.keys() {
            if k not in seen {
                v = vmap[k];
                if v.status in ["confirmed", "candidate"] {
                    v.status = "withdrawn";
                    v.reasoning = ("Canon amended: the requirement is now "
                                   "supported by the latest state — finding withdrawn.");
                }
            }
        }

        if not self.quiet {
            print(f"\naudit: {n_supported} requirements supported, "
                  f"{n_nocanon} with no prior canon (presupposed background)");
            report_violations();
        }
    }
}

def report_violations() {
    viols = [root -->[?:Violation]];
    if len(viols) == 0 {
        print("no violations recorded.");
        return;
    }
    rank = {"confirmed": 0, "candidate": 1, "withdrawn": 2, "declined": 3};
    viols = sorted(viols, key=lambda v: Violation : rank.get(v.status, 9));
    icons = {"confirmed": "✖", "candidate": "▲", "withdrawn": "↩", "declined": "·"};
    print("\n================ CONTINUITY REPORT ================");
    for v in viols {
        icon = icons.get(v.status, "?");
        print(f"\n{icon} [{v.status.upper()}] {v.subject} {v.predicate}: "
              f"required <{v.required_value}> but canon says <{v.found_value}>");
        print(f"  at: {doc_title(v.req_doc)} — scene {fmt_scene(v.req_seg)}");
        print("  proof path:");
        print(v.timeline);
        if v.reasoning != "" {
            conf = "";
            if v.confidence != "" {
                conf = f" ({v.confidence} confidence)";
            }
            print(f"  adjudicator{conf}: {v.reasoning}");
        }
    }
    print("\n===================================================");
}

walker ShowCanon {
    can go with Root entry {
        states = all_established();
        subjects = sorted(set([st.subject for st in states]));
        print(f"\ncanon: {len(states)} established states across "
              f"{len(all_segments())} scenes in {len(all_documents())} documents\n");
        for subj in subjects {
            print(f"{subj}:");
            for st in states {
                if st.subject == subj {
                    print(f"    [{doc_title(st.doc_index)} — scene "
                          f"{fmt_scene(st.seg_order)}] {st.predicate} = {st.value}");
                }
            }
        }
    }
}

walker Score {
    can go with Root entry {
        total = 0;
        matched = 0;
        for seg in all_segments() {
            total += seg.exp_total;
            matched += seg.exp_matched;
        }
        if total == 0 {
            print("no annotated expectations ingested yet.");
            return;
        }
        pct = round(100.0 * matched / total, 1);
        print(f"extraction accuracy: {matched}/{total} annotated key facts "
              f"recovered = {pct}%");
    }
}

walker Reset {
    can go with Root entry {
        n = 0;
        for d in [here --> ] {
            for seg in [d --> ] {
                for st in [seg --> ] {
                    del st;
                    n += 1;
                }
                del seg;
                n += 1;
            }
            del d;
            n += 1;
        }
        print(f"reset: deleted {n} nodes.");
    }
}

# --------------------------------------------------------------------- entry

with entry {
    litellm.suppress_debug_info = True;
    argv = sys.argv;
    cmd = "help";
    if len(argv) > 1 {
        cmd = argv[1];
    }

    if cmd == "ingest" {
        if len(argv) < 3 {
            print("usage: jac run main.jac ingest <script.txt>");
        } else {
            root spawn Ingest(path=argv[2]);
            print("\ningest done. next: jac run main.jac audit");
        }
    } elif cmd == "audit" {
        root spawn Auditor();
    } elif cmd == "report" {
        report_violations();
    } elif cmd == "canon" {
        root spawn ShowCanon();
    } elif cmd == "score" {
        root spawn Score();
    } elif cmd == "reset" {
        root spawn Reset();
    } else {
        print("Continuity Walker — commands: ingest <file> | audit | report | "
              "canon | score | reset");
    }
}
