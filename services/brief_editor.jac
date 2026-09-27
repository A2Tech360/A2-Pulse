"""Editor stage of GenerateBrief: turn the top items into a one-minute spoken brief.

The LLM writes it when one is configured (services/pulse_llm.jac); otherwise,
or when the call fails or times out, a template does. Either way the result
goes through speakable() before it is returned, stored or spoken.
"""

import re;
import time;
import from datetime { date }
import from services { pulse_llm }
import from services.speakable { speakable, word_count }
import from services.brief_dates { brief_monday }
import from services.brief_narrative { narrative_brief }

# LLM output shorter than this is treated as a failed call.
glob LLM_MIN_WORDS: int = 60;
# LLM briefs longer than this, or with relative day words (the listener may hear
# the brief on any day), are replaced by the template.
glob LLM_MAX_WORDS: int = 180;
glob RELATIVE_DAY_WORDS: str = r"(?i)\b(today|tonight|tomorrow)\b";


def llm_write_brief(profile: str, items: str, week_of: str) -> str by pulse_llm.brief_llm(temperature=0.3, max_tokens=300);
sem llm_write_brief = """You are the Editor for A2 Pulse, writing the weekly audio brief for one Ann Arbor resident, for the week of week_of (a Monday). A text-to-speech voice reads it aloud, so write for the ear, not the eye.
Length: 125 to 145 words, never more than 150. Budget about 25 words per item plus a one-line greeting and a short sign-off, and count before you answer.
Cover every numbered item, in the given order; a brief that leaves out any item is wrong. For each one say what it is and when, why it matters to this person, and the one thing to do about it. Reasons are listed strongest first; lead with the first one.
Stick to the facts in the items: keep each item's name as given, and never add or reinterpret details (no guesses about what a title means, who performs, prices, places or times that are not in the item).
Every weekday in the items falls in the week of week_of. Say days by name (Monday, Tuesday), including for Monday items: say Monday evening or on Monday at 7 p.m. Never say today, tonight, tomorrow, this morning or this evening: the listener may hear this on any day, including the weekend before. Keep every day and time range complete, such as Wednesday to Friday, 7 a.m. to 5 p.m.
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

"""The template fallback: the narrative, friend-style brief (services/brief_narrative.jac)."""
def template_brief(first_name: str, items: list[dict[str, any]], today: date | None = None) -> str {
    return narrative_brief(first_name, items, today);
}

"""The lines the LLM sees for the ranked items. They are already made speakable, so it never has to guess what an
abbreviation stands for (it read "UMS" as University of Michigan)."""
def editor_items_text(items: list[dict[str, any]], ref: date | None = None) -> str {
    lines: list[str] = [];
    for (i, it) in enumerate(items) {
        why = "; ".join([speakable(str(r), ref).rstrip(".") for r in list(it.get("reasons", []))[:3]]);
        name = speakable(str(it["name"]), ref);
        when = speakable(str(it.get("when", "")), ref);
        action = speakable(str(it.get("action", "")), ref);
        lines.append(f"{i + 1}. {name} ({it['kind']}). When: {when}. Why it matters: {why}. What to do: {action}");
    }
    return "\n".join(lines);
}

"""Run the Editor stage. items: [{name, kind, when, reasons, action}] in rank order.
Returns the spoken text plus everything the debug trace needs."""
def edit_brief(first_name: str, profile_line: str, items: list[dict[str, any]], use_ai: bool = True, today: date | None = None) -> dict[str, any] {
    ref = today or date.today();
    # The brief is for its week's Monday (next Monday on weekends); item days are days of that week.
    monday = brief_monday(ref);
    week_of = monday.strftime("%A, %B ") + str(monday.day) + monday.strftime(", %Y");
    items_text = editor_items_text(items, monday);
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
            spoken: str = speakable(raw, ref);
            out["speakable_ms"] = round((time.perf_counter() - t0) * 1000, 2);
            n = word_count(spoken);
            relative: re.Match[str] | None = re.search(RELATIVE_DAY_WORDS, spoken);
            # Guard what the prompt cannot guarantee: length and relative day words.
            if n > LLM_MAX_WORDS {
                out["error"] = f"LLM brief too long ({n} words); used the template";
            } elif relative is not None {
                out["error"] = f"LLM brief said '{relative.group(0)}'; used the template";
            } else {
                out["spoken"] = spoken;
                out["mode"] = "llm";
            }
        }
    } elif use_ai {
        out["error"] = "LLM off";
    }
    if out["mode"] != "llm" {
        t0 = time.perf_counter();
        out["spoken"] = template_brief(first_name, items, monday);
        out["template_ms"] = round((time.perf_counter() - t0) * 1000, 2);
    }
    out["words"] = word_count(out["spoken"]);
    return out;
}
