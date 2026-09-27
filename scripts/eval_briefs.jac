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
import time;
import re;
import io;
import sys;
import contextlib;
import from pathlib { Path }
import from datetime { datetime }
import from services { pulse_llm }
import from services.brief_dates { brief_day_index, brief_week_label, brief_monday }
import from services.event_dates { extract_event_date }
import from services.speakable { speakable }
import from services.event_ingest { sync_online_events }
import json;
import from datetime { timedelta }
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

# Real-data testers (--real): extra profiles run against the live-ingested graph.
glob TESTERS: list[dict[str, any]] = [
    {"persona": "tester-kerry-bike", "name": "Kerrytown cyclist", "why": "Tester: Kerrytown, bike; food, music, arts", "home": "pl-kerry", "commute": "bike", "via": ["pl-kerry", "pl-main"], "interests": ["food", "music", "arts"], "follows": []},
    {"persona": "tester-north-bus", "name": "North Campus bus rider", "why": "Tester: North Campus, bus to Central Campus; academic, social", "home": "pl-north", "commute": "bus", "via": ["pl-north", "pl-plymouth", "pl-central"], "interests": ["academic", "social"], "follows": []},
    {"persona": "tester-main-car", "name": "Main Street driver", "why": "Tester: Main Street, car; civic, food, nightlife", "home": "pl-main", "commute": "car", "via": ["pl-main", "pl-kerry"], "interests": ["civic", "food", "nightlife"], "follows": []}
];
# Listing sites and publications: never a host, never "someone you follow".
glob PLATFORMS: str = r"(?i)\b(eventbrite|ann arbor observer|happening (?:@|at) michigan|marquee arts|allevents|meetup)\b";
glob GENERIC_VENUES: list[str] = ["ann arbor", "ypsilanti", "online", "virtual", "tba", "tbd", "various locations", "see website", "multiple locations", "upcoming"];
glob CLOSE_BY_WORDS: str = r"(?i)\b(close by|around the corner|a short trip to|nearby|just down the (?:street|road))\b";
glob INTEREST_WORDS: str = r"(?i)(?:into|interest in|interests in|love for|fan of|if you like|your) (music|food|sports|academic|social|arts|community|outdoor|civic|networking|nightlife|comedy)\b";

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

# Narrative style: things a friend talking you through the week would not say.
glob LIST_LABELS: str = r"(?i)why it matters|the reason:|why it's here|why you'd care|why it made the list";
glob ORDINAL_LIST: str = r"\b(First|Second|Third|Fourth|Fifth|And finally)\s*,|\bNumber (one|two|three|four|five)\b";
glob STYLE_EXAMPLE_ONLY: str = r"(?i)\b(SCOR|homecoming pregame|North Fourth Avenue|cut over on Fifth|Packard bike lanes)\b";
# Reason phrasings; each should appear at most once per brief.
glob REASON_STEMS: list[str] = [
    "near your home", "close to home", "near your place", "just by your home", "right on your",
    "along your", "in the way of your", "since you follow", "who you follow", "which you follow",
    "one of your follows", "since you're into", "right up your alley", "matches your interest",
    "your love for", "just around the corner", "a short trip to", "close by at", "your part of town",
    "where you live", "where you get around"
];

"""Style checks for the spoken brief. Returns [(name, ok, detail)]."""
def style_checks(spoken: str) -> list[dict[str, any]] {
    sentences: list[str] = [x.strip() for x in re.split(r"(?<=[.!?])\s+(?=[A-Z])", spoken.strip()) if x.strip()];
    labels = [m.group(0) for m in re.finditer(LIST_LABELS, spoken)];
    ordinals = [m.group(0) for m in re.finditer(ORDINAL_LIST, spoken)];
    low = spoken.lower();
    repeated = [f"{stem!r} x{low.count(stem)}" for stem in REASON_STEMS if low.count(stem) > 1];
    opening_ok = len(sentences) >= 2 and sentences[0].startswith("Good morning") and ("week" in sentences[1].lower() or "week" in sentences[0].lower());
    closing: str = sentences[-1] if sentences else "";
    closing_ok = len(closing.split()) <= 10 and "that's your monday" not in low and closing not in sentences[:2];
    leaked = [m.group(0) for m in re.finditer(STYLE_EXAMPLE_ONLY, spoken)];
    return [
        {"name": "No list labels", "ok": len(labels) == 0, "detail": ", ".join(labels)},
        {"name": "No ordinal list", "ok": len(ordinals) == 0, "detail": ", ".join(ordinals)},
        {"name": "No repeated reason", "ok": len(repeated) == 0, "detail": ", ".join(repeated)},
        {"name": "Opening and closing", "ok": opening_ok and closing_ok, "detail": ("" if opening_ok else "no week-setting opening; ") + ("" if closing_ok else f"closing: {closing[:60]!r}")},
        {"name": "Nothing from style example", "ok": len(leaked) == 0, "detail": ", ".join(leaked)}
    ];
}

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

def evaluate(persona: str, why: str, today: int, real: bool = False) -> dict[str, any] {
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
    (errors, warnings) = check_rules(prof, t["scored"], today);
    checks.extend(style_checks(spoken));
    if real {
        checks.extend(real_checks(prof, items, t["scored"], spoken));
    }
    checks.append({"name": "Rules apply", "ok": len(errors) == 0, "detail": "; ".join(errors[:4]) + (f" (+{len(errors) - 4} more)" if len(errors) > 4 else "")});

    return {
        "persona": persona, "why": why, "brief": b, "trace": t, "spoken": spoken, "words": words,
        "checks": checks, "errors": errors, "warnings": warnings,
        "ok": all([c["ok"] for c in checks])
    };
}

# ---------------------------------------------------------------- real-data checks
glob FOOD_WORDS: str = r"(?i)\b(food|market|tasting|brunch|dinner|lunch|breakfast|cook|chef|restaurant|cafe|coffee|beer|wine|pizza|potluck|bake|farm)\b";

"""Data-quality notes on the live snapshot (things no brief check can see)."""
def snapshot_notes(snap: list[dict[str, any]]) -> list[str] {
    notes: list[str] = [];
    long_venues = [e for e in snap if any([len(str(v)) > 45 or str(e["name"]).split(" ")[0] in str(v) and len(str(v)) > 25 for v in e["venues"]])];
    platform_orgs = [e for e in snap if any([re.search(PLATFORMS, str(o)) is not None for o in e["organizers"]])];
    guessed_price = [e for e in snap if 0.0 < float(e["price"]) < 5.0];
    food_no_words = [e for e in snap if "food" in list(e["tags"]) and re.search(FOOD_WORDS, str(e["name"])) is None];
    no_date = [e for e in snap if not re.search(r"\d{4}-\d{2}-\d{2}", str(e["when"])) and int(e["day"]) < 0];
    def ex(rows: list[dict[str, any]]) -> str {
        return "; ".join([str(e["name"])[:50] for e in rows[:3]]);
    }
    notes.append(f"- Venue names with scraped text: {len(long_venues)} of {len(snap)} (e.g. {ex(long_venues)})");
    notes.append(f"- Organizer is a listing site or publication: {len(platform_orgs)} (e.g. {ex(platform_orgs)})");
    notes.append(f"- Implausible guessed prices (under 5 dollars, not free): {len(guessed_price)} (e.g. {ex(guessed_price)})");
    notes.append(f"- Tagged food with no food word in the name: {len(food_no_words)} of {len([e for e in snap if "food" in list(e["tags"])])} food-tagged (e.g. {ex(food_no_words)})");
    notes.append(f"- No usable date: {len(no_date)} (e.g. {ex(no_date)})");
    return notes;
}
def _is_real_venue(v: any) -> bool {
    name = str(v.name).strip().lower();
    return bool(str(v.address).strip()) and name not in GENERIC_VENUES and re.search(PLATFORMS, name) is None;
}

"""Checks that only make sense on live data. Returns (checks, bug entries)."""
def real_checks(prof: UserProfile, items: list[any], scored: list[dict[str, any]], spoken: str) -> list[dict[str, any]] {
    monday = brief_monday(datetime.now());
    sunday = monday + timedelta(days=6);
    nodes = [_find_key(str(it.key)) for it in items];
    checks: list[dict[str, any]] = [];

    # 1. Every item inside the brief week (Monday..Sunday).
    outside: list[str] = [];
    for n in nodes {
        if n is None {
            continue;
        }
        d: any = extract_event_date(str(n.when), monday.year);
        if d is not None {
            if d < monday or d > sunday {
                outside.append(f"{n.name} ({d.isoformat()})");
            }
        } elif not (0 <= int(n.day) <= 6) {
            outside.append(f"{n.name} (no date: {n.when!r})");
        }
    }
    checks.append({"name": "Inside brief week", "ok": len(outside) == 0, "detail": "; ".join(outside)});

    # 2. No spoken year, ISO date, HH:MM:SS or raw 24-hour time.
    bad_times = re.findall(r"\b(?:19|20)\d{2}\b|\d{4}-\d{2}-\d{2}|\b\d{1,2}:\d{2}:\d{2}\b|\b\d{1,2}:\d{2}\b(?!\s?[ap]\.m\.)", spoken);
    checks.append({"name": "Spoken dates and times", "ok": len(bad_times) == 0, "detail": ", ".join(bad_times[:5])});

    # 3. No listing site or publication named as a host or follow.
    hosts: list[str] = [m.group(0) for m in re.finditer(PLATFORMS, spoken)];
    for n in nodes {
        if n is None {
            continue;
        }
        for o in [n ->:OrganizedBy:->][?:Organizer] {
            if re.search(PLATFORMS, str(o.name)) {
                hosts.append(f"{n.name} organized by {o.name}");
            }
        }
    }
    checks.append({"name": "No platform as host", "ok": len(hosts) == 0, "detail": "; ".join(sorted(set(hosts)))[:300]});

    # 4. "Close by" only with a real venue.
    fake_near: list[str] = [];
    real_near = 0;
    top_keys = [str(it.key) for it in items];
    for s in scored {
        if str(s["key"]) not in top_keys {
            continue;
        }
        for r in s["rules"] {
            if str(r["rule"]) != "near_venue" {
                continue;
            }
            vname = str(r["detail"]).replace("Close by at ", "");
            n = _find_key(str(s["key"]));
            venues = [v for v in [n ->:HostedAt:->][?:Venue] if v.name == vname] if n is not None else [];
            if len(venues) > 0 and _is_real_venue(venues[0]) {
                real_near += 1;
            } else {
                fake_near.append(f"{s['name']} near {vname!r}");
            }
        }
    }
    said_near = len(re.findall(CLOSE_BY_WORDS, spoken));
    if said_near > real_near {
        fake_near.append(f"says close by {said_near}x, {real_near} real venue(s)");
    }
    checks.append({"name": "Close by has a real venue", "ok": len(fake_near) == 0, "detail": "; ".join(sorted(set(fake_near)))[:300]});

    # 5. A named interest matches the tags of the item it is said about.
    wrong_interest: list[str] = [];
    sentences = [x for x in re.split(r"(?<=[.!?])\s+(?=[A-Z])", spoken) if x.strip()];
    for sent in sentences {
        for m in re.finditer(INTEREST_WORDS, sent) {
            cat = m.group(1).lower();
            for (it, n) in zip(items, nodes) {
                if n is None {
                    continue;
                }
                spoken_name: str = speakable(str(it.name));
                words: list[str] = [str(w) for w in re.findall(r"[A-Za-z']{4,}", spoken_name) if str(w).lower() not in ["with", "from", "night", "free", "your", "this"]];
                # Whole words only: "Round" must not match "around".
                if len(words) > 0 and any([re.search(r"(?i)\b" + re.escape(w) + r"\b", sent) is not None for w in words[:3]]) {
                    tags = [c.name for c in [n ->:TaggedAs:->][?:Category]];
                    if cat not in tags {
                        wrong_interest.append(f"{it.name}: said {cat}, tags {tags}");
                    }
                }
            }
        }
    }
    checks.append({"name": "Interest matches tags", "ok": len(wrong_interest) == 0, "detail": "; ".join(sorted(set(wrong_interest)))[:300]});

    # 6. A home or route closure that fits the travel mode is present; alerts in the brief fit the mode.
    places = [p for p in [prof ->:LivesAt:->][?:Place]] + [p for p in [prof ->:CommutesVia:->][?:Place]];
    fitting: list[any] = [];
    for p in places {
        for a in [p <-:AffectsRoute:<-][?:Alert] {
            if a.sub == "closure" and prof.commute in alert_modes(a) and a not in fitting {
                fitting.append(a);
            }
        }
    }
    in_top = [a for a in fitting if a.key in top_keys];
    mismatched = [f"{n.name} affects {'/'.join(alert_modes(n))}, commute is {prof.commute}" for n in nodes if n is not None and n.kind == "alert" and prof.commute not in alert_modes(n)];
    closure_ok = (len(fitting) == 0 or len(in_top) > 0) and len(mismatched) == 0;
    detail = ("" if len(fitting) == 0 or len(in_top) > 0 else "missing: " + ", ".join([a.name for a in fitting]) + "; ") + "; ".join(mismatched);
    checks.append({"name": "Closure present and fits mode", "ok": closure_ok, "detail": detail});
    return checks;
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

def write_report(results: list[dict[str, any]], mode: str, samples: list[list[str]] = [], data_note: str = "") -> str {
    check_names = [c["name"] for c in results[0]["checks"]];
    out: list[str] = [
        "# Brief eval", "",
        f"- Run: {datetime.now().isoformat(timespec='seconds')} ({datetime.now().strftime('%A')}; the 'soon' rule and date wording depend on the weekday)",
        f"- Brief week: {brief_week_label(datetime.now())}",
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
    fails: dict[str, list[str]] = {};
    for r in results {
        for c in r["checks"] {
            if not c["ok"] {
                fails.setdefault(str(c["name"]), []).append(f"{r['persona']}: {cell(str(c['detail']))}");
            }
        }
    }
    if data_note or fails {
        out.extend(["", "## Bug list (failures by type)", ""]);
        if data_note {
            out.extend([data_note, ""]);
        }
        def by_count(kv: tuple) -> int {
            return -len(kv[1]);
        }
        for (name, rows) in sorted(fails.items(), key=by_count) {
            out.append(f"### {name}: {len(rows)} profile(s)");
            out.extend(["- " + x for x in rows]);
            out.append("");
        }
    }
    if samples {
        out.extend(["", "## Sample briefs", ""]);
        for smp in samples {
            out.extend([f"**{smp[0]}** ({len(smp[1].split())} words)", "", "> " + smp[1], ""]);
        }
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
    real = "--real" in sys.argv;
    data_note = "";
    if real {
        # Snapshot of the live graph: pull the public calendars into this throwaway graph now.
        with contextlib.redirect_stdout(io.StringIO()) {
            rep: any = sync_online_events(True);
        }
        live = [n for n in [_ensure_seed() -->][?:PulseNode] if str(n.key).startswith("live-")];
        snap = [{"key": n.key, "name": n.name, "when": n.when, "day": n.day, "source": n.source_name,
                 "organizers": [o.name for o in [n ->:OrganizedBy:->][?:Organizer]],
                 "venues": [v.name for v in [n ->:HostedAt:->][?:Venue]],
                 "tags": [c.name for c in [n ->:TaggedAs:->][?:Category]], "price": n.price} for n in live];
        snap_path = REPORT_PATH.parent / "real_snapshot.json";
        snap_path.parent.mkdir(parents=True, exist_ok=True);
        snap_path.write_text(json.dumps(snap, indent=1, default=lambda (o: any) -> str { return str(o); }), encoding="utf-8");
        data_note = f"Live snapshot: {len(live)} ingested events from {len(rep.sources)} sources ({', '.join(rep.sources)}); errors: {'; '.join(rep.errors) or 'none'}. Saved to {snap_path.name}.";
        data_note += "\n\nData quality notes (live snapshot):\n" + "\n".join(snapshot_notes(snap));
        print(data_note);
    }
    extra = TESTERS if real else [];
    for spec in SYNTHETIC + extra {
        build_synthetic(spec);
    }
    mode = mode_line();
    print(f"Mode: {mode}");
    if "--require-llm" in sys.argv and not pulse_llm.llm_enabled() {
        print("--require-llm: the LLM is off, so this run would only test the templates. Set LLM_MODEL and its key.");
        sys.exit(3);
    }
    today = brief_day_index(datetime.now());
    profiles: list[dict[str, any]] = SEEDED + SYNTHETIC + extra;
    # --pace SECONDS waits between profiles, for providers with per-minute quotas.
    pace = 0.0;
    if "--pace" in sys.argv and sys.argv.index("--pace") + 1 < len(sys.argv) {
        pace = float(sys.argv[sys.argv.index("--pace") + 1]);
    }
    results: list[dict[str, any]] = [];
    for (i, p) in enumerate(profiles) {
        if pace > 0.0 and i > 0 {
            time.sleep(pace);
        }
        results.append(evaluate(str(p["persona"]), str(p["why"]), today, real));
    }
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
    # Samples for reading: up to 3 LLM briefs from this run, plus one template brief.
    samples: list[list[str]] = [];
    for r in results {
        if r["trace"]["editor"]["mode"] == "llm" and len(samples) < 3 {
            samples.append([f"LLM ({pulse_llm.llm_model_label()}): {r['persona']}", r["spoken"]]);
        }
    }
    tpl_persona = str(profiles[1]["persona"]);
    with contextlib.redirect_stdout(io.StringIO()) {
        tb: any = (root spawn GenerateBrief(persona=tpl_persona, use_ai=False)).reports[0];
    }
    samples.append([f"Template: {tpl_persona}", str(tb.summary)]);
    print(f"{len([r for r in results if r['ok']])}/{len(results)} profiles pass. Report: {write_report(results, mode, samples, data_note)}");
    if "--require-llm" in sys.argv and not all([r["trace"]["editor"]["mode"] == "llm" for r in results]) {
        sys.exit(1);
    }
    if not all([r["ok"] for r in results]) {
        sys.exit(1);
    }
}
