"""Brief quality eval: GenerateBrief(debug=True) for Jordan, Maya and six synthetic
profiles, checked against the graph and written to reports/eval_briefs.md.

Run through scripts/eval_briefs, which points JAC_DATA_PATH at a throwaway
directory so the synthetic profiles never reach the dev graph. The LLM mode
comes from LLM_MODEL like the app, so the same command re-runs the eval once a
model is set. Exit code 1 when any profile fails a check.
"""

# First: normalize an empty or "off" LLM_MODEL before any module with `by llm` loads.
import services.llm_env;
import os;
import re;
import io;
import sys;
import contextlib;
import from pathlib { Path }
import from datetime { datetime }
import from services { pulse_llm }
import from services.pulse {
    GenerateBrief, UserProfile, PulseNode, Place, Venue, Category, Organizer, Alert,
    LivesAt, CommutesVia, InterestedIn, Follows, AffectsRoute, Near, HostedAt, TaggedAs, OrganizedBy,
    _ensure_seed, _find_key
}

glob REPORT_PATH: Path = Path(str(__file__ or ".")).resolve().parent.parent / "reports" / "eval_briefs.md";
glob MIN_WORDS: int = 120;
glob MAX_WORDS: int = 180;

glob SEEDED: list[dict[str, str]] = [
    {"persona": "student", "why": "Seeded: Jordan, North Campus, bike"},
    {"persona": "shop", "why": "Seeded: Maya, Main Street, car"}
];

# One per commute mode across different neighborhoods, plus no-follows and single-interest.
glob SYNTHETIC: list[dict[str, any]] = [
    {"persona": "eval-walk", "name": "Priya, Kerrytown walker", "why": "Walk commute, Kerrytown", "home": "pl-kerry", "commute": "walk", "via": ["pl-kerry", "pl-main"], "interests": ["food", "community"], "follows": ["o-zing"]},
    {"persona": "eval-bike", "name": "Sam, Washtenaw cyclist", "why": "Bike commute, Washtenaw Avenue", "home": "pl-washtenaw", "commute": "bike", "via": ["pl-washtenaw", "pl-central", "pl-state"], "interests": ["outdoor", "sports"], "follows": ["o-hike"]},
    {"persona": "eval-car", "name": "Dana, Plymouth Road driver", "why": "Car commute, Plymouth Road corridor", "home": "pl-plymouth", "commute": "car", "via": ["pl-plymouth", "pl-north"], "interests": ["networking", "academic"], "follows": ["o-career"]},
    {"persona": "eval-bus", "name": "Luis, State Street bus rider", "why": "Bus commute, State Street", "home": "pl-state", "commute": "bus", "via": ["pl-state", "pl-central", "pl-washtenaw"], "interests": ["arts", "music"], "follows": ["o-ums"]},
    {"persona": "eval-nofollow", "name": "Ava, Central Campus", "why": "No follows, Central Campus, walk", "home": "pl-central", "commute": "walk", "via": ["pl-central"], "interests": ["civic", "music", "social"], "follows": []},
    {"persona": "eval-oneinterest", "name": "Theo, Main Street", "why": "Single interest (music), Main Street, bike", "home": "pl-main", "commute": "bike", "via": ["pl-main", "pl-kerry"], "interests": ["music"], "follows": ["o-llama"]}
];

# Independent of speakable(): anything here in the spoken text is a miss.
glob ABBREVIATIONS: list[str] = [
    r"\b(?:Rd|St|Ave|Av|Blvd|Dr|Hwy|Pkwy|Ln|Ct|Cir|Ter|Trl|Fwy|Expy|Sq)\b\.?",
    r"(?<![\w.'’-])(?:N|S|E|W|NE|NW|SE|SW)\.?(?=\s)",
    r"\b(?:Mon|Tue|Tues|Wed|Thu|Thur|Thurs|Fri|Sat|Sun)\b\.?",
    r"\b(?:Jan|Feb|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\b\.?",
    r"\b(?:AM|PM|am|pm)\b",
    r"\b\d{1,2}:00\b",
    r"\bU-M\b|\bUofM\b|\bUMich\b|\b(?:AADL|UMS|DDA|SEAS)\b",
    r"\b(?:approx|vs|etc|e\.g|i\.e)\b\.?",
    r"\b\d+(?:\.\d+)?\s?(?:mi|min|mins|hr|hrs|ft)\b",
    r"https?://\S+|\bwww\.\S+",
    r"[&@$%#*_()\[\]{}<>|~^=+\\/]",
    r"[\U0001F000-\U0001FAFF☀-➿]"
];

# Which commute modes an alert plausibly affects, from its wording (seed data has no mode field).
def alert_modes(n: PulseNode) -> list[str] {
    t = (n.name + " " + n.desc).lower();
    if "sidewalk" in t {
        return ["walk"];
    }
    if "bus" in t or "route " in t or "theride" in t {
        return ["bus"];
    }
    return ["car", "bike", "bus"];
}

def node_of(key: str) -> PulseNode {
    n = _find_key(key);
    if n is None {
        raise KeyError(f"seed node {key} not found");
    }
    return n;
}

def build_synthetic(spec: dict[str, any]) {
    prof = UserProfile(persona=spec["persona"], name=spec["name"], commute=spec["commute"], weights={});
    root ++> prof;
    prof +>:LivesAt():+> node_of(spec["home"]);
    for p in spec["via"] {
        prof +>:CommutesVia():+> node_of(p);
    }
    for c in spec["interests"] {
        prof +>:InterestedIn():+> node_of("cat-" + c);
    }
    for o in spec["follows"] {
        prof +>:Follows():+> node_of(o);
    }
}

def profile_node(persona: str) -> UserProfile {
    return [p for p in [root -->][?:UserProfile] if p.persona == persona][0];
}

def names_of(nodes: list[any]) -> list[str] {
    return [n.name for n in nodes];
}

# ---------------------------------------------------------------- checks
def check_abbreviations(spoken: str) -> list[str] {
    hits: list[str] = [];
    for pat in ABBREVIATIONS {
        for m in re.finditer(pat, spoken) {
            lo = max(0, m.start() - 20);
            hits.append(repr(m.group(0)) + " in '..." + spoken[lo:m.end() + 20] + "...'");
        }
    }
    return hits;
}

"""Re-derive every rule application from the graph. Returns (errors, warnings)."""
def check_rules(prof: UserProfile, scored: list[dict[str, any]], today: int) -> tuple[list[str], list[str]] {
    homes = [prof ->:LivesAt:->][?:Place];
    via = [prof ->:CommutesVia:->][?:Place];
    near_places = homes + via;
    interests = names_of([prof ->:InterestedIn:->][?:Category]);
    follows = names_of([prof ->:Follows:->][?:Organizer]);
    errors: list[str] = [];
    warnings: list[str] = [];
    for s in scored {
        n = _find_key(str(s["key"]));
        if n is None {
            errors.append(f"{s['key']}: scored item not in the graph");
            continue;
        }
        affects = names_of([n ->:AffectsRoute:->][?:Place]);
        venues = [n ->:HostedAt:->][?:Venue];
        cats = names_of([n ->:TaggedAs:->][?:Category]);
        orgs = names_of([n ->:OrganizedBy:->][?:Organizer]);
        seen: list[str] = [];
        for r in s["rules"] {
            rule = str(r["rule"]);
            detail = str(r["detail"]);
            label = f"{n.name} [{rule}: {detail}, {r['points']}]";
            sig = rule + "|" + detail;
            if sig in seen and rule not in ["weight"] {
                errors.append(f"{label}: same rule and reason counted twice");
            }
            seen.append(sig);
            m: any = None;
            if rule == "home_alert" {
                m = re.fullmatch(r"Near your home in (.+)", detail);
                if n.kind != "alert" or m is None or m.group(1) not in names_of(homes) or m.group(1) not in affects {
                    errors.append(f"{label}: not an alert affecting the home neighborhood");
                }
            } elif rule == "route_alert" {
                m = re.fullmatch(r"On your \w+ route via (.+)", detail);
                if n.kind != "alert" or m is None or m.group(1) not in names_of(via) or m.group(1) not in affects {
                    errors.append(f"{label}: not an alert on a neighborhood this person commutes through");
                } elif prof.commute not in alert_modes(n) {
                    warnings.append(f"{label}: affects {'/'.join(alert_modes(n))}, but this person commutes by {prof.commute}");
                }
            } elif rule == "affects_place" {
                m = re.fullmatch(r"Affects (.+), where you live or travel", detail);
                if m is None or m.group(1) not in names_of(near_places) or m.group(1) not in affects {
                    errors.append(f"{label}: does not affect a home or commute neighborhood");
                }
            } elif rule == "near_venue" {
                m = re.fullmatch(r"Close by at (.+)", detail);
                ok = False;
                for v in venues {
                    if m is not None and v.name == m.group(1) {
                        ok = any([p in near_places for p in [v ->:Near:->][?:Place]]);
                    }
                }
                if not ok {
                    errors.append(f"{label}: venue is not near a home or commute neighborhood");
                }
            } elif rule == "interest" {
                m = re.fullmatch(r"Matches your interest in (.+)", detail);
                if m is None or m.group(1) not in interests or m.group(1) not in cats {
                    errors.append(f"{label}: not tagged with one of this person's interests");
                }
            } elif rule == "follows" {
                m = re.fullmatch(r"From (.+), which you follow", detail);
                if m is None or m.group(1) not in follows or m.group(1) not in orgs {
                    errors.append(f"{label}: not organized by someone this person follows");
                }
            } elif rule == "soon" {
                delta = n.day - today;
                if n.kind not in ["civic", "alert"] or delta < 0 or delta > 2 {
                    errors.append(f"{label}: not a civic item or alert in the next 3 days");
                }
            } elif rule == "weight" {
                if not any([c in detail for c in cats]) {
                    errors.append(f"{label}: weight for a category the item does not have");
                }
            } else {
                errors.append(f"{label}: unknown rule");
            }
        }
    }
    return (errors, warnings);
}

def evaluate(persona: str, why: str, today: int) -> dict[str, any] {
    # `jac run` echoes walker reports to stdout; keep the console to the verdicts.
    with contextlib.redirect_stdout(io.StringIO()) {
        b: any = (root spawn GenerateBrief(persona=persona, use_ai=True, debug=True)).reports[0];
    }
    t: dict[str, any] = b.trace;
    prof = profile_node(persona);
    items: list[any] = list(b.items);
    spoken = str(b.summary);
    words = len(spoken.split());
    keys = [it.key for it in items];
    names = [it.name.lower() for it in items];

    checks: list[dict[str, any]] = [];
    abbr = check_abbreviations(spoken);
    checks.append({"name": "No abbreviations", "ok": len(abbr) == 0, "detail": "; ".join(abbr[:6])});
    checks.append({"name": f"{MIN_WORDS}-{MAX_WORDS} words", "ok": MIN_WORDS <= words <= MAX_WORDS, "detail": f"{words} words"});
    dupes = sorted(set([k for k in keys if keys.count(k) > 1] + [x for x in names if names.count(x) > 1]));
    checks.append({"name": "No repeated item", "ok": len(dupes) == 0 and len(items) > 0, "detail": ", ".join(dupes) or f"{len(items)} distinct items"});
    missing = [it.name for it in items if not str(it.action).strip()];
    checks.append({"name": "Every item has a to-do", "ok": len(missing) == 0 and len(items) > 0, "detail": ", ".join(missing)});
    home_closures: list[any] = [];
    for h in [prof ->:LivesAt:->][?:Place] {
        home_closures.extend([a for a in [h <-:AffectsRoute:<-][?:Alert] if a.sub == "closure"]);
    }
    in_top = [a.name for a in home_closures if a.key in keys];
    left_out = [a.name for a in home_closures if a.key not in keys];
    checks.append({
        "name": "Home closure in top 5",
        "ok": len(home_closures) == 0 or len(in_top) > 0,
        "detail": ("none in the home neighborhood" if len(home_closures) == 0 else "in: " + (", ".join(in_top) or "none") + ("; left out: " + ", ".join(left_out) if left_out else ""))
    });
    (errors, warnings) = check_rules(prof, t["scored"], datetime.now().weekday());
    checks.append({"name": "Rules apply", "ok": len(errors) == 0, "detail": "; ".join(errors[:4]) + (f" (+{len(errors) - 4} more)" if len(errors) > 4 else "")});

    return {
        "persona": persona, "why": why, "brief": b, "trace": t, "spoken": spoken, "words": words,
        "checks": checks, "errors": errors, "warnings": warnings,
        "ok": all([c["ok"] for c in checks])
    };
}

# ---------------------------------------------------------------- report
def mode_line -> str {
    st = pulse_llm.llm_config_status();
    if pulse_llm.llm_enabled() {
        return f"LLM on: {st['model']} ({st['provider']})";
    }
    return f"LLM off: fallback templates ({st.get('reason', '')})";
}

def cell(s: str) -> str {
    return s.replace("|", "/").replace("\n", " ");
}

def write_report(results: list[dict[str, any]], mode: str) -> str {
    check_names = [c["name"] for c in results[0]["checks"]];
    out: list[str] = [
        "# Brief eval", "",
        f"- Run: {datetime.now().isoformat(timespec='seconds')} ({datetime.now().strftime('%A')}; the 'soon' rule and date wording depend on the weekday)",
        f"- Mode: {mode}",
        f"- Editor used the LLM for {len([r for r in results if r['trace']['editor']['mode'] == 'llm'])}/{len(results)} briefs",
        f"- Result: {len([r for r in results if r['ok']])}/{len(results)} profiles pass", "",
        "| Profile | Editor | Words | " + " | ".join(check_names) + " |",
        "|---|---|---|" + "---|" * len(check_names)
    ];
    for r in results {
        ed = r["trace"]["editor"];
        out.append(f"| {r['persona']} | {ed['mode']} | {r['words']} | " + " | ".join(["PASS" if c["ok"] else "**FAIL**" for c in r["checks"]]) + " |");
    }
    for r in results {
        t = r["trace"];
        pr = t["profile"];
        ed = t["editor"];
        out.extend([
            "", f"## {r['persona']}: {pr['name']}", "",
            f"_{r['why']}_", "",
            f"- Home: {', '.join([h['name'] for h in pr['home']])}; via: {', '.join([v['name'] for v in pr['via']])}; commute: {pr['commute']}",
            f"- Interests: {', '.join(pr['interests']) or 'none'}; follows: {', '.join([f['name'] for f in pr['follows']]) or 'none'}",
            f"- Editor: {ed['mode']}" + (f" ({ed['model']})" if ed["model"] else "") + (f", fallback reason: {ed['error']}" if ed["error"] else ""),
            f"- Timing: " + ", ".join([f"{k} {v}" for (k, v) in t["timing_ms"].items()]), "",
            "| Check | Result | Detail |", "|---|---|---|"
        ]);
        for c in r["checks"] {
            out.append(f"| {c['name']} | {'PASS' if c['ok'] else '**FAIL**'} | {cell(str(c['detail']))} |");
        }
        out.extend(["", "| # | Item | Kind | Score | Breakdown | To-do |", "|---|---|---|---|---|---|"]);
        top = [s for s in t["scored"] if s["selected"]];
        actions: dict[str, str] = {a["key"]: a["action"] for a in t["actions"]};
        for s in top {
            parts = [f"{rr['rule']} {rr['points']:+g} ({rr['detail']})" for rr in s["rules"]];
            out.append(f"| {s['rank']} | {cell(s['name'])} | {s['kind']} | {s['score']} | {cell('; '.join(parts))} | {cell(actions.get(s['key'], ''))} |");
        }
        out.extend(["", f"**Spoken ({r['words']} words):**", "", "> " + r["spoken"]]);
        if r["errors"] {
            out.extend(["", "**Rule errors:**", ""] + ["- " + e for e in r["errors"]]);
        }
        if r["warnings"] {
            out.extend(["", "**Warnings (commute mode vs. alert type):**", ""] + ["- " + w for w in r["warnings"]]);
        }
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True);
    REPORT_PATH.write_text("\n".join(out) + "\n", encoding="utf-8");
    return str(REPORT_PATH);
}

with entry {
    if not os.environ.get("JAC_DATA_PATH", "") {
        print("Refusing to run on the dev graph: use scripts/eval_briefs (it sets JAC_DATA_PATH to a temp dir).");
        sys.exit(2);
    }
    _ensure_seed();
    for spec in SYNTHETIC {
        build_synthetic(spec);
    }
    mode = mode_line();
    print(f"Mode: {mode}");
    if "--require-llm" in sys.argv and not pulse_llm.llm_enabled() {
        print("--require-llm: the LLM is off, so this run would only test the templates. Set LLM_MODEL and its key.");
        sys.exit(3);
    }
    today = datetime.now().weekday();
    profiles: list[dict[str, any]] = SEEDED + SYNTHETIC;
    results = [evaluate(str(p["persona"]), str(p["why"]), today) for p in profiles];
    for r in results {
        failed = [c["name"] for c in r["checks"] if not c["ok"]];
        warn = f" ({len(r['warnings'])} warning(s))" if r["warnings"] else "";
        print(("PASS " if r["ok"] else "FAIL ") + f"{r['persona']:<17} {r['trace']['editor']['mode']:<8} {r['words']:>3} words" + ("" if r["ok"] else "  failed: " + ", ".join(failed)) + warn);
    }
    if pulse_llm.llm_enabled() {
        by_llm = [r for r in results if r["trace"]["editor"]["mode"] == "llm"];
        print(f"Model used: {pulse_llm.llm_model_label()}. The Editor used it for {len(by_llm)}/{len(results)} briefs.");
        for r in results {
            if r["trace"]["editor"]["mode"] != "llm" {
                print(f"  {r['persona']} fell back to the template: {r['trace']['editor']['error']}");
            }
        }
    } else {
        print("Model used: none (LLM off); every brief came from the template.");
    }
    print(f"{len([r for r in results if r['ok']])}/{len(results)} profiles pass. Report: {write_report(results, mode)}");
    if "--require-llm" in sys.argv and not all([r["trace"]["editor"]["mode"] == "llm" for r in results]) {
        sys.exit(1);
    }
    if not all([r["ok"] for r in results]) {
        sys.exit(1);
    }
}
