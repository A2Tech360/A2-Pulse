"""Editor stage of GenerateBrief: turn the top items into a one-minute spoken brief.

The LLM writes it when one is configured (services/pulse_llm.jac); otherwise,
or when the call fails or times out, a template does. Either way the result
goes through speakable() before it is returned, stored or spoken.
"""

import time;
import from datetime { date, timedelta }
import from services { pulse_llm }
import from services.speakable { speakable, word_count }

glob TARGET_MIN_WORDS: int = 140;
glob TARGET_MAX_WORDS: int = 160;
# LLM output shorter than this is treated as a failed call.
glob LLM_MIN_WORDS: int = 60;

glob ORDINALS: list[str] = ["First", "Second", "Third", "Fourth", "Fifth"];
glob WHY_LEADS: list[str] = ["Why it matters:", "Why it's here:", "Why you'd care:", "The reason:", "Why it made the list:"];

def llm_write_brief(profile: str, items: str, week_of: str) -> str by pulse_llm.brief_llm(temperature=0.3, max_tokens=300);
sem llm_write_brief = """You are the Editor for A2 Pulse, writing a Monday morning audio brief for one Ann Arbor resident. A text-to-speech voice reads it aloud, so write for the ear, not the eye.
Length: 125 to 145 words, never more than 150. Budget about 25 words per item plus a one-line greeting and a short sign-off, and count before you answer.
Cover every numbered item, in the given order; a brief that leaves out any item is wrong. For each one say what it is and when, why it matters to this person, and the one thing to do about it. Reasons are listed strongest first; lead with the first one.
Stick to the facts in the items: keep each item's name as given, and never add or reinterpret details (no guesses about what a title means, who performs, prices, places or times that are not in the item).
The brief is for the week that starts on week_of; every weekday in the items falls in that week. Say days by name (Monday, Tuesday). Never say today, tonight, tomorrow, this morning or this evening: the listener may hear this on any day of the week. Keep every day and time range complete, such as Wednesday to Friday, 7 a.m. to 5 p.m.
Tone: friendly and direct, like a neighbor who did the homework. Short sentences. Call the listener you. Open with a one-line greeting using their first name (if the name is You or missing, just say Good morning, with no name or stand-in like resident) and close with a short sign-off.
Spoken-text rules, all mandatory:
- No abbreviations. Write Road, Street, Avenue, Boulevard, Drive, Highway, Parkway; North, South, East, West; University of Michigan, not U-M; Monday, not Mon; Saint or Doctor where that is what St. or Dr. means.
- No symbols. Write and instead of &, at instead of @, 15 dollars instead of $15, percent instead of %.
- No URLs, emoji, markdown, bullet points, numbered lists, headings or parentheses.
- Times read naturally, like 7 p.m., 7:30 a.m. or noon. Dates like Tuesday, September 29th.
- Plain sentences only.""";
sem llm_write_brief.profile = "Who the brief is for: name, home area, commute mode and interests.";
sem llm_write_brief.items = "The ranked items, one per line, each with when, why it matters (strongest reason first) and what to do.";
sem llm_write_brief.week_of = "The Monday this brief is for, e.g. Monday, September 21, 2026. Item days (Mon, Tue...) are days of this week.";

def _lower_first(s: str) -> str {
    return s[:1].lower() + s[1:] if s else s;
}

def _clause(reasons: list[str], n: int) -> str {
    picked = [_lower_first(r.strip().rstrip(".")) for r in reasons[:n] if r.strip()];
    if len(picked) == 0 {
        return "";
    }
    if len(picked) == 1 {
        return picked[0];
    }
    return ", ".join(picked[:-1]) + ", and " + picked[-1];
}

glob COUNT_WORDS: list[str] = ["no", "one", "two", "three", "four", "five"];

"""Order an item's reasons by the points each earned (from its trace rules), strongest first.
A rule counted twice for the same reason only counts once here."""
def strongest_first(reasons: list[str], rules: list[dict[str, any]]) -> list[str] {
    pts: dict[str, float] = {};
    seen: list[str] = [];
    for r in rules {
        d = str(r["detail"]);
        sig = str(r["rule"]) + "|" + d;
        if sig not in seen {
            seen.append(sig);
            pts[d] = pts.get(d, 0.0) + float(r["points"]);
        }
    }
    def weight(x: str) -> float {
        return -pts.get(x, 0.0);
    }
    return sorted(reasons, key=weight);
}

"""A reason clause as a sentence without the "Why it matters:" label."""
def _why_sentence(why: str) -> str {
    if why.startswith(("near ", "on your ", "close by ", "from ", "coming up ")) {
        return "It's " + why;
    }
    if why.startswith(("affects ", "matches ")) {
        return "It " + why;
    }
    return why[:1].upper() + why[1:];
}

"""A time phrase placed mid-sentence: "All week" -> "all week"; day names stay capitalized."""
def _mid_sentence(when: str) -> str {
    first = when.split(" ")[0].rstrip(",");
    if first[:3] in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] or not first[:1].isupper() {
        return when;
    }
    return when[:1].lower() + when[1:];
}

"""One item as spoken sentences. Knobs (for trimming): n_reasons, why_lead.
The heading always keeps the time unless the action already says it."""
def _item_sentence(i: int, it: dict[str, any], n_reasons: int, why_lead: bool) -> str {
    name = str(it["name"]);
    when = str(it.get("when", ""));
    action = str(it.get("action", "")).strip();
    head = "And finally" if i == 4 else (ORDINALS[i] if i < len(ORDINALS) else "Next");
    out = f"{head}, {name}" + (f", {_mid_sentence(when)}." if when and when not in action else ".");
    why = _clause(list(it.get("reasons", [])), n_reasons);
    if why and why_lead {
        out += f" {WHY_LEADS[i % len(WHY_LEADS)]} {why}.";
    } elif why {
        out += " " + _why_sentence(why) + ".";
    }
    if action {
        out += " " + action;
        if not action.endswith((".", "!", "?")) {
            out += ".";
        }
    }
    return out;
}

"""Deterministic brief aimed at 140-160 spoken words. When long it trims, last
item first: the second reason, then the "Why it matters:" labels, then the
intro. Times are never trimmed. When short it adds sign-off lines that still
fit. Returns speakable text."""
def template_brief(first_name: str, items: list[dict[str, any]], today: date | None = None) -> str {
    n = len(items);
    hello = "Good morning." if first_name.strip().lower() in ["", "you"] else f"Good morning {first_name.strip()}.";
    if n == 0 {
        return speakable(f"{hello} Nothing in Ann Arbor touches your week yet, so enjoy the quiet. Have a good week.", today);
    }
    count = COUNT_WORDS[n] if n < len(COUNT_WORDS) else str(n);
    long_intro = f"{hello} Here are the {count} things that touch your week in Ann Arbor." if n > 1 else f"{hello} One thing touches your week in Ann Arbor.";
    intros: list[str] = [long_intro, f"{hello} Here's your week."];
    outro = "That's your Monday. Have a good week.";
    extras: list[str] = [
        "Tap thumbs up or down on any card and next week's brief leans your way.",
        "Every item links back to its source on your cards."
    ];
    reasons: list[int] = [2] * n;
    leads: list[bool] = [True] * n;
    intro_i: list[int] = [0];
    def build(extra_count: int) -> str {
        parts = [intros[intro_i[0]]] + [_item_sentence(i, items[i], reasons[i], leads[i]) for i in range(n)];
        parts.extend(extras[:extra_count]);
        parts.append(outro);
        return speakable(" ".join(parts), today);
    }
    text = build(0);
    for knob in ["reasons", "leads"] {
        i = n - 1;
        while word_count(text) > TARGET_MAX_WORDS and i >= 0 {
            if knob == "reasons" { reasons[i] = 1; }
            else { leads[i] = False; }
            text = build(0);
            i -= 1;
        }
    }
    if word_count(text) > TARGET_MAX_WORDS {
        intro_i[0] = 1;
        text = build(0);
    }
    k = 1;
    while word_count(text) < TARGET_MIN_WORDS and k <= len(extras) {
        longer = build(k);
        if word_count(longer) > TARGET_MAX_WORDS {
            break;
        }
        text = longer;
        k += 1;
    }
    return text;
}

"""The lines the LLM sees for the ranked items."""
def editor_items_text(items: list[dict[str, any]]) -> str {
    lines: list[str] = [];
    for (i, it) in enumerate(items) {
        why = "; ".join([str(r).rstrip(".") for r in list(it.get("reasons", []))[:3]]);
        lines.append(f"{i + 1}. {it['name']} ({it['kind']}). When: {it['when']}. Why it matters: {why}. What to do: {it['action']}");
    }
    return "\n".join(lines);
}

"""Run the Editor stage. items: [{name, kind, when, reasons, action}] in rank order.
Returns the spoken text plus everything the debug trace needs."""
def edit_brief(first_name: str, profile_line: str, items: list[dict[str, any]], use_ai: bool = True, today: date | None = None) -> dict[str, any] {
    ref = today or date.today();
    # The brief is for its week's Monday; item days (Mon..Sun) are days of that week.
    monday = ref - timedelta(days=ref.weekday());
    week_of = monday.strftime("%A, %B ") + str(monday.day) + monday.strftime(", %Y");
    items_text = editor_items_text(items);
    out: dict[str, any] = {
        "mode": "template", "model": "", "spoken": "", "raw_llm": None, "error": "",
        "input": {"profile": profile_line, "items": items_text, "week_of": week_of},
        "llm_ms": 0.0, "template_ms": 0.0, "speakable_ms": 0.0, "words": 0
    };
    if use_ai and pulse_llm.llm_enabled() {
        out["model"] = pulse_llm.llm_model_label();
        res = pulse_llm.call_with_deadline(llm_write_brief, [profile_line, items_text, week_of]);
        out["llm_ms"] = res["ms"];
        raw = str(res["value"] or "").strip() if res["ok"] else "";
        out["raw_llm"] = raw if res["ok"] else None;
        if not res["ok"] {
            out["error"] = res["error"];
        } elif word_count(raw) < LLM_MIN_WORDS {
            out["error"] = f"LLM output too short ({word_count(raw)} words)";
        } else {
            t0 = time.perf_counter();
            out["spoken"] = speakable(raw, ref);
            out["speakable_ms"] = round((time.perf_counter() - t0) * 1000, 2);
            out["mode"] = "llm";
        }
    } elif use_ai {
        out["error"] = "LLM off";
    }
    if out["mode"] != "llm" {
        t0 = time.perf_counter();
        out["spoken"] = template_brief(first_name, items, ref);
        out["template_ms"] = round((time.perf_counter() - t0) * 1000, 2);
    }
    out["words"] = word_count(out["spoken"]);
    return out;
}
