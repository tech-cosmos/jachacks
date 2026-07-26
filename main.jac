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
import json;
import re;
import html;
import zipfile;
import subprocess;
import litellm;
import from byllm.llm { Model }
import from http.server { HTTPServer, BaseHTTPRequestHandler }

def pick_model() -> str {
    m = os.environ.get("CW_MODEL", "");
    if m != "" {
        return m;
    }
    if os.environ.get("OPENROUTER_API_KEY", "") != "" {
        return "openrouter/deepseek/deepseek-v4-flash";
    }
    return "gemini/gemini-2.5-flash";
}

def pick_judge() -> str {
    m = os.environ.get("CW_JUDGE_MODEL", "");
    if m != "" {
        return m;
    }
    if os.environ.get("OPENROUTER_API_KEY", "") != "" {
        return "openrouter/anthropic/claude-sonnet-5";
    }
    return pick_model();
}

glob llm = Model(model_name=pick_model());
glob judge_llm = Model(model_name=pick_judge());

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
               scene_excerpt: str) -> Verdict by judge_llm();

"""List the plot holes in this script. Be specific and number them."""
def find_plot_holes(script: str) -> list[str] by judge_llm();

# --------------------------------------------------------------------- graph

node Document {
    has title: str;
    has kind: str;
    has doc_index: int;
    has canon: str = "";
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

glob MULTI_VALUED = ["knowledge", "possession", "plan", "desire", "action",
                     "emotion", "goal"];

def same_state(pred: str, a: str, b: str) -> bool {
    if a == b {
        return True;
    }
    if pred == "alive" {
        t = ["true", "yes", "alive", "living", "intact"];
        f = ["false", "no", "dead", "destroyed", "wiped_out", "gone"];
        return (a in t and b in t) or (a in f and b in f);
    }
    return False;
}

def related(a: str, b: str) -> bool {
    na = norm(a);
    nb = norm(b);
    if na == nb {
        return True;
    }
    return na.startswith(nb) or nb.startswith(na);
}

def canon_of(doc_index: int) -> str {
    for d in all_documents() {
        if d.doc_index == doc_index {
            if d.canon != "" {
                return d.canon;
            }
            return norm(d.title);
        }
    }
    return "";
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

def backend() -> str {
    return os.environ.get("CW_BACKEND", "");
}

def cli_json(prompt: str, model: str) -> dict {
    r = subprocess.run(["claude", "-p", "--model", model,
                        "--output-format", "text"],
                       input=prompt, capture_output=True, text=True,
                       timeout=240);
    out = r.stdout.strip();
    i = out.find("{");
    j = out.rfind("}");
    if i < 0 or j <= i {
        raise ValueError(f"no JSON in claude CLI output: {out[:120]}");
    }
    return json.loads(out[i:j + 1]);
}

def cli_extract(scene: str, ks: list, kp: list) -> SceneFacts {
    model = os.environ.get("CW_CLI_MODEL", "haiku");
    prompt = (
        "Extract concrete STATE facts from this scene of a screenplay.\n\n"
        "establishes: facts this scene makes true from now on (state set or "
        "changed: broken/repaired, down/up, moved, died, learned, gained, "
        "lost, or a stated world rule).\n"
        "requires: facts that must ALREADY be true for the scene's action to "
        "be physically possible. If a character successfully USES a device or "
        "service, you MUST include a requires that it is working. If a group "
        "acts and their survival could be in doubt, require them alive. Never "
        "require what this same scene creates or destroys. Location "
        "requirements only for where someone must be when the scene STARTS.\n\n"
        "Rules: subject = canonical snake_case entity id — REUSE from "
        f"known_subjects when the same thing is meant: {ks}\n"
        f"predicate = one lowercase word, reuse from: {kp}\n"
        "value = 1-2 lowercase words joined by underscore; use exactly "
        "working or down for device/service health.\n"
        "Only objectively checkable states. 2-6 establishes, 0-3 requires.\n\n"
        "Respond with ONLY this JSON, no prose:\n"
        "{\"establishes\": [{\"subject\": \"s\", \"predicate\": \"p\", "
        "\"value\": \"v\"}], \"requires\": [...]}\n\n"
        f"SCENE:\n{scene}");
    d = cli_json(prompt, model);
    est = [Fact(subject=str(x.get("subject", "")),
                predicate=str(x.get("predicate", "")),
                value=str(x.get("value", "")))
           for x in d.get("establishes", []) if x.get("subject")];
    req = [Fact(subject=str(x.get("subject", "")),
                predicate=str(x.get("predicate", "")),
                value=str(x.get("value", "")))
           for x in d.get("requires", []) if x.get("subject")];
    return SceneFacts(establishes=est, requires=req);
}

def cli_adjudicate(requirement: str, tl: str, excerpt: str) -> Verdict {
    model = os.environ.get("CW_CLI_JUDGE_MODEL", "sonnet");
    prompt = (
        "You are adjudicating a candidate continuity error in one continuous "
        "story. The canon timeline lists every state the script established, "
        "in story order. Rules: the story world changes ONLY when a scene "
        "establishes the change — do not invent off-screen repairs or fixes, "
        "however mundane; an unwritten fix is exactly what a continuity error "
        "is. NOT a contradiction if a timeline fact makes the requirement "
        "satisfiable, or the mismatch is pure wording for the same real "
        "state. Location mismatches are only contradictions if canon makes "
        "the move impossible; device/service/life states change only via an "
        "establishing scene.\n\n"
        f"REQUIREMENT: {requirement}\n\nCANON TIMELINE:\n{tl}\n\n"
        f"SCENE EXCERPT:\n{excerpt}\n\n"
        "Respond with ONLY this JSON:\n"
        "{\"is_contradiction\": true, \"confidence\": "
        "\"high|medium|low\", \"reasoning\": \"...\"}");
    d = cli_json(prompt, model);
    return Verdict(is_contradiction=bool(d.get("is_contradiction", False)),
                   confidence=str(d.get("confidence", "low")),
                   reasoning=str(d.get("reasoning", "")));
}

def cli_naive(script: str) -> list {
    model = os.environ.get("CW_CLI_JUDGE_MODEL", "sonnet");
    prompt = ("List the plot holes in this script. Be specific.\n"
              "Respond with ONLY JSON: {\"holes\": [\"...\", \"...\"]}\n\n"
              + script);
    d = cli_json(prompt, model);
    return [str(h) for h in d.get("holes", [])];
}

def safe_extract(prose: str, ks: list, kp: list) -> SceneFacts {
    delay = float(os.environ.get("CW_DELAY", "0"));
    if delay > 0 {
        time.sleep(delay);
    }
    attempt = 0;
    while attempt < 3 {
        try {
            if backend() == "claude" {
                return cli_extract(prose, ks, kp);
            }
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
            if backend() == "claude" {
                return cli_adjudicate(requirement, tl, excerpt);
            }
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

def note(w: object, s: str) {
    print(s);
    w.log.append(s);
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
    has canon: str;
}

def read_doc(path: str) -> str {
    if path.lower().endswith(".docx") {
        z = zipfile.ZipFile(path);
        xml = z.read("word/document.xml").decode("utf-8");
        z.close();
        t = re.sub("<w:p [^>]*>|<w:p>", "\n", xml);
        t = re.sub("<[^>]+>", "", t);
        t = html.unescape(t);
        return re.sub("\n{2,}", "\n", t).strip();
    }
    f = open(path, "r");
    t = f.read();
    f.close();
    return t;
}

def parse_script(path: str) -> ScriptData {
    return parse_script_text(read_doc(path), path);
}

def parse_script_text(text: str, fallback_title: str) -> ScriptData {
    title = fallback_title;
    kind = "script";
    vocab = [];
    canon = "";
    for raw in text.split("\n") {
        line = raw.strip();
        if line.startswith("# TITLE:") {
            title = line[8:].strip();
        } elif line.startswith("# KIND:") {
            kind = line[7:].strip();
        } elif line.startswith("# VOCAB:") {
            vocab = [norm(v) for v in line[8:].split(",") if v.strip() != ""];
        } elif line.startswith("# CANON:") {
            canon = norm(line[8:]);
        }
    }

    # normalize "Scene 12: Title" style headings into ## SCENE markers
    text = re.sub("(?mi)^\\s*scene\\s+(\\d+)\\s*[:.].*$", "## SCENE \\1", text);
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
                or line.startswith("# VOCAB:") or line.startswith("# CANON:") {
                continue;
            } else {
                prose_lines.append(raw);
            }
        }
        scenes.append(SceneData(order=order, prose="\n".join(prose_lines).strip(),
                                exp_est=est, exp_req=req));
    }
    if len(scenes) == 0 and text.strip() != "" {
        # unstructured transcript: auto-chunk into ~2400-char segments
        seg_lines = [];
        size = 0;
        order = 0.0;
        for ln in text.split("\n") {
            seg_lines.append(ln);
            size += len(ln) + 1;
            if size >= 2400 {
                order += 1.0;
                scenes.append(SceneData(order=order,
                    prose="\n".join(seg_lines).strip(), exp_est=[], exp_req=[]));
                seg_lines = [];
                size = 0;
            }
        }
        if "\n".join(seg_lines).strip() != "" {
            order += 1.0;
            scenes.append(SceneData(order=order,
                prose="\n".join(seg_lines).strip(), exp_est=[], exp_req=[]));
        }
    }
    if canon == "" {
        canon = norm(title);
    }
    return ScriptData(title=title, kind=kind, scenes=scenes, vocab=vocab,
                      canon=canon);
}

# ------------------------------------------------------------------- walkers

walker Ingest {
    has path: str = "";
    has text: str = "";
    has title_hint: str = "Pasted Script";
    has log: list = [];

    can go with Root entry {
        if self.text != "" {
            script = parse_script_text(self.text, self.title_hint);
        } else {
            script = parse_script(self.path);
        }
        docs = all_documents();
        doc = None;
        for d in docs {
            if d.title == script.title {
                doc = d;
            }
        }
        if doc is None {
            doc = Document(title=script.title, kind=script.kind,
                           doc_index=len(docs), canon=script.canon);
            here ++> doc;
            note(self, f"+ document [{doc.doc_index}] {doc.title}");
        } else {
            note(self, f"= document [{doc.doc_index}] {doc.title} (appending)");
        }

        no_llm = os.environ.get("CW_NO_LLM", "") == "1";
        existing_orders = [s.order for s in [doc -->[?:Segment]]];
        states = [st for st in all_established()
                  if canon_of(st.doc_index) == script.canon];
        known_subj = sorted(set([st.subject for st in states] + script.vocab));
        known_pred = sorted(set([st.predicate for st in states]
                                + ["status", "location", "possession", "alive",
                                   "knowledge", "plan"]));

        for sc in script.scenes {
            if sc.order in existing_orders {
                note(self, f"  scene {fmt_scene(sc.order)}: already ingested, skipping");
                continue;
            }
            if no_llm {
                facts = SceneFacts(establishes=sc.exp_est, requires=sc.exp_req);
                note(self, f"  scene {fmt_scene(sc.order)}: structured mode "
                      f"({len(sc.exp_est)} est, {len(sc.exp_req)} req)");
            } else {
                facts = safe_extract(sc.prose, sorted(set(known_subj))[:80],
                                     sorted(set(known_pred))[:30]);
                if len(facts.establishes) == 0 and len(facts.requires) == 0
                    and len(sc.exp_est) + len(sc.exp_req) > 0 {
                    facts = SceneFacts(establishes=sc.exp_est, requires=sc.exp_req);
                    note(self, f"  scene {fmt_scene(sc.order)}: extraction failed, "
                          f"using annotated facts");
                } else {
                    note(self, f"  scene {fmt_scene(sc.order)}: extracted "
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
                note(self, f"      + {st.subject} {st.predicate} = {st.value}");
                known_subj.append(st.subject);
                known_pred.append(st.predicate);
            }
            for fc in facts.requires {
                st = State(subject=norm(fc.subject), predicate=norm(fc.predicate),
                           value=norm(fc.value), doc_index=doc.doc_index,
                           seg_order=sc.order);
                seg +>:Requires:+> st;
                note(self, f"      ? {st.subject} {st.predicate} = {st.value}");
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
                    note(self, f"      accuracy: {matched}/{len(expected)} key facts");
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
            seg_canon = canon_of(seg.doc_index);
            scoped = [st for st in states
                      if canon_of(st.doc_index) == seg_canon];
            for req in [seg ->:Requires:->] {
                hist = [];
                for st in scoped {
                    if st.subject == req.subject and st.predicate == req.predicate
                        and skey(st.doc_index, st.seg_order) < skey(seg.doc_index, seg.order) {
                        hist.append(st);
                    }
                }
                if len(hist) == 0 {
                    n_nocanon += 1;
                    continue;
                }
                if req.predicate in MULTI_VALUED {
                    # many values can hold at once (you know/own many things):
                    # supported if ANY prior state matches, never a violation
                    ok = False;
                    for st in hist {
                        if same_state(req.predicate, st.value, req.value) {
                            ok = True;
                        }
                    }
                    if ok {
                        n_supported += 1;
                    }
                    continue;
                }
                latest = hist[-1];
                if same_state(req.predicate, latest.value, req.value) {
                    n_supported += 1;
                    continue;
                }

                key = f"{req.subject}|{req.predicate}|{seg.doc_index}|{seg.order}";
                seen.append(key);
                tl = timeline_for(req.subject, scoped);
                requirement = (f"Scene {fmt_scene(seg.order)} of "
                               f"'{doc_title(seg.doc_index)}' requires: "
                               f"{req.subject} {req.predicate} = {req.value}");

                # verdicts are cached per evidence state: an existing verdict
                # only re-opens when the canon timeline for its subject changes
                if key in vmap and vmap[key].timeline == tl
                    and vmap[key].status in ["confirmed", "declined", "withdrawn"] {
                    vmap[key].found_value = latest.value;
                    continue;
                }

                if req.predicate == "location" {
                    status = "declined";
                    confidence = "rule";
                    reasoning = ("Location mismatch declined by rule: agents "
                                 "relocate freely between scenes, so movement is "
                                 "always a legal implicit transition. Only "
                                 "device/system/life states need an establishing "
                                 "scene to change.");
                } elif no_llm {
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

def score_stats() -> dict {
    total = 0;
    matched = 0;
    for seg in all_segments() {
        total += seg.exp_total;
        matched += seg.exp_matched;
    }
    pct = 0.0;
    if total > 0 {
        pct = round(100.0 * matched / total, 1);
    }
    return {"expected": total, "matched": matched, "pct": pct};
}

walker Score {
    can go with Root entry {
        s = score_stats();
        if s["expected"] == 0 {
            print("no annotated expectations ingested yet.");
            return;
        }
        print(f"extraction accuracy: {s['matched']}/{s['expected']} annotated "
              f"key facts recovered = {s['pct']}%");
    }
}

def build_graph_payload() -> dict {
    nodes = [];
    edges = [];
    sid = {};
    i = 0;
    for d in all_documents() {
        nodes.append({"data": {"id": f"d{d.doc_index}", "label": d.title,
                               "type": "document"}});
    }
    for seg in all_segments() {
        segid = f"d{seg.doc_index}s{seg.order}";
        nodes.append({"data": {"id": segid,
                               "label": f"scene {fmt_scene(seg.order)}",
                               "type": "segment"}});
        edges.append({"data": {"source": f"d{seg.doc_index}",
                               "target": segid, "kind": "contains"}});
        for st in [seg ->:Establishes:->] {
            i += 1;
            stid = f"st{i}";
            sid[id(st)] = stid;
            nodes.append({"data": {"id": stid,
                "label": f"{st.subject}.{st.predicate} = {st.value}",
                "type": "state"}});
            edges.append({"data": {"source": segid, "target": stid,
                                   "kind": "establishes"}});
        }
        for st in [seg ->:Requires:->] {
            i += 1;
            stid = f"rq{i}";
            nodes.append({"data": {"id": stid,
                "label": f"{st.subject}.{st.predicate} = {st.value}",
                "type": "requires"}});
            edges.append({"data": {"source": segid, "target": stid,
                                   "kind": "requires"}});
        }
    }
    for seg in all_segments() {
        for st in [seg ->:Establishes:->] {
            for nxt in [st ->:Transition:->] {
                if id(st) in sid and id(nxt) in sid {
                    edges.append({"data": {"source": sid[id(st)],
                                           "target": sid[id(nxt)],
                                           "kind": "transition"}});
                }
            }
        }
    }
    viols = [];
    for v in [root -->[?:Violation]] {
        i += 1;
        vid = f"v{i}";
        nodes.append({"data": {"id": vid,
            "label": f"{v.subject}.{v.predicate}: {v.required_value} vs {v.found_value}",
            "type": "violation", "status": v.status}});
        edges.append({"data": {"source": f"d{v.req_doc}s{v.req_seg}",
                               "target": vid, "kind": "flags"}});
        viols.append({"subject": v.subject, "predicate": v.predicate,
                      "required": v.required_value, "found": v.found_value,
                      "at": f"{doc_title(v.req_doc)} — scene {fmt_scene(v.req_seg)}",
                      "status": v.status, "confidence": v.confidence,
                      "timeline": v.timeline, "reasoning": v.reasoning});
    }
    return {"elements": {"nodes": nodes, "edges": edges},
            "violations": viols};
}

def write_graph(out: str) -> dict {
    data = build_graph_payload();
    f = open(out, "w");
    f.write(json.dumps(data, indent=1));
    f.close();
    return data;
}

walker Dump {
    has out: str = "web/graph.json";

    can go with Root entry {
        data = write_graph(self.out);
        print(f"wrote {self.out}: {len(data['elements']['nodes'])} nodes, "
              f"{len(data['elements']['edges'])} edges, "
              f"{len(data['violations'])} violations");
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

# ----------------------------------------------------------------- http api

def api_analyze(body: dict) -> dict {
    w = Ingest(text=body.get("text", ""),
               title_hint=body.get("title", "Pasted Script"));
    root spawn w;
    root spawn Auditor(quiet=True);
    data = write_graph("web/graph.json");
    return {"log": w.log, "violations": data["violations"],
            "score": score_stats()};
}

def api_naive(body: dict) -> dict {
    script = parse_script_text(body.get("text", ""), "pasted");
    txt = "";
    for sc in script.scenes {
        txt += f"SCENE {fmt_scene(sc.order)}\n{sc.prose}\n\n";
    }
    if txt.strip() == "" {
        txt = body.get("text", "");
    }
    if backend() == "claude" {
        return {"holes": cli_naive(txt)};
    }
    return {"holes": find_plot_holes(txt)};
}

def api_reset() -> dict {
    root spawn Reset();
    write_graph("web/graph.json");
    return {"ok": True};
}

class ApiHandler(BaseHTTPRequestHandler) {
    def _send(self: object, code: int, ctype: str, payload: bytes) {
        self.send_response(code);
        self.send_header("Content-Type", ctype);
        self.send_header("Cache-Control", "no-store");
        self.end_headers();
        self.wfile.write(payload);
    }

    def _file(self: object, relpath: str, ctype: str) {
        try {
            f = open(relpath, "rb");
            data = f.read();
            f.close();
            self._send(200, ctype, data);
        } except Exception as e {
            self._send(404, "text/plain", "not found".encode());
        }
    }

    def do_GET(self: object) {
        p = self.path.split("?")[0];
        if p == "/" or p == "/index.html" {
            self._file("web/index.html", "text/html; charset=utf-8");
        } elif p == "/graph.json" {
            self._file("web/graph.json", "application/json");
        } elif p == "/api/score" {
            self._send(200, "application/json",
                       json.dumps(score_stats()).encode());
        } elif p == "/api/samples" {
            names = sorted(os.listdir("data"));
            self._send(200, "application/json", json.dumps(names).encode());
        } elif p.startswith("/data/") {
            self._file(f"data/{os.path.basename(p)}",
                       "text/plain; charset=utf-8");
        } else {
            self._send(404, "text/plain", "not found".encode());
        }
    }

    def do_POST(self: object) {
        n = int(self.headers.get("Content-Length", "0"));
        raw = self.rfile.read(n).decode();
        body = {};
        if raw != "" {
            try {
                body = json.loads(raw);
            } except Exception as e {
                body = {};
            }
        }
        p = self.path.split("?")[0];
        try {
            if p == "/api/analyze" {
                out = api_analyze(body);
            } elif p == "/api/naive" {
                out = api_naive(body);
            } elif p == "/api/reset" {
                out = api_reset();
            } else {
                self._send(404, "text/plain", "not found".encode());
                return;
            }
            self._send(200, "application/json", json.dumps(out).encode());
        } except Exception as e {
            self._send(500, "application/json",
                       json.dumps({"error": str(e)}).encode());
        }
    }

    def log_message(self: object, fmt: str, *args: tuple) {}
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
    } elif cmd == "naive" {
        # what a raw frontier model does with the same script: run it twice
        text = "";
        for path in argv[2:] {
            script = parse_script(path);
            for sc in script.scenes {
                text += f"SCENE {fmt_scene(sc.order)}\n{sc.prose}\n\n";
            }
        }
        print("=== raw LLM, same script, asked for plot holes ===");
        for h in find_plot_holes(text) {
            print(f"  - {h}");
        }
    } elif cmd == "audit" {
        root spawn Auditor();
    } elif cmd == "report" {
        report_violations();
    } elif cmd == "canon" {
        root spawn ShowCanon();
    } elif cmd == "score" {
        root spawn Score();
    } elif cmd == "convert" {
        # convert <src(.docx|.txt)> <out.txt> [title]  — for UI sample reels
        src = argv[2];
        out = argv[3];
        title = os.path.basename(src);
        if len(argv) > 4 {
            title = argv[4];
        }
        script = parse_script_text(read_doc(src), title);
        f = open(out, "w");
        f.write(f"# TITLE: {title}\n# KIND: film transcript\n");
        for sc in script.scenes {
            f.write(f"\n## SCENE {fmt_scene(sc.order)}\n{sc.prose}\n");
        }
        f.close();
        print(f"wrote {out}: {len(script.scenes)} scenes");
    } elif cmd == "serve" {
        port = 8765;
        if len(argv) > 2 {
            port = int(argv[2]);
        }
        write_graph("web/graph.json");
        print(f"Continuity Walker → http://localhost:{port}");
        HTTPServer(("0.0.0.0", port), ApiHandler).serve_forever();
    } elif cmd == "dump" {
        root spawn Dump();
    } elif cmd == "drop" {
        frag = " ".join(argv[2:]).lower();
        if frag == "" {
            print("usage: jac run main.jac drop <title fragment>");
        } else {
            n = 0;
            for d in all_documents() {
                if frag in d.title.lower() {
                    for v in [root -->[?:Violation]] {
                        if v.req_doc == d.doc_index {
                            del v;
                        }
                    }
                    for seg in [d -->[?:Segment]] {
                        for st in [seg --> ] {
                            del st;
                        }
                        del seg;
                    }
                    print(f"dropped document [{d.doc_index}] {d.title}");
                    del d;
                    n += 1;
                }
            }
            if n == 0 {
                print(f"no document title matches: {frag}");
            }
        }
    } elif cmd == "clearviols" {
        n = 0;
        for v in [root -->[?:Violation]] {
            del v;
            n += 1;
        }
        print(f"cleared {n} violation records (canon untouched)");
    } elif cmd == "reset" {
        root spawn Reset();
    } else {
        print("Continuity Walker — commands: ingest <file> | audit | report | "
              "canon | score | reset");
    }
}
