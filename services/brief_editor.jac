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
# Reason phrasings: each may appear at most once in a brief (the LLM tends to repeat them).
glob REASON_PHRASES: list[str] = [
    "near your home", "close to home", "near your place", "right on your", "along your",
    "since you follow", "who you follow", "which you follow", "since you're into",
    "right up your alley", "matches your interest", "your love for", "just around the corner",
    "close by at", "your part of town", "where you live"
];

"""The first reason phrase used more than once, or "" if none repeats."""
def repeated_reason(text: str) -> str {
    low = text.lower();
    for p in REASON_PHRASES {
        if low.count(p) > 1 {
            return p;
        }
    }
    return "";
}

# Phrases that exist only in the prompt's style example; seeing one means the LLM copied it.
glob STYLE_EXAMPLE_ONLY: str = r"(?i)\b(SCOR|homecoming pregame|North Fourth Avenue|cut over on Fifth|Packard bike lanes)\b";


def llm_write_brief(profile: str, items: str, week_of: str) -> str by pulse_llm.brief_llm(temperature=0.5, max_tokens=400);
sem llm_write_brief = """You are the Editor for A2 Pulse. Write the weekly audio brief for one Ann Arbor resident, for the week of week_of (a Monday), the way a friend who knows Ann Arbor would talk them through their week. A text-to-speech voice reads it aloud, so write for the ear.
Shape:
- Greeting with their first name (if the name is You or missing, just Good morning), then ONE sentence that sets up the week: what kind of week it is (busy, a quiet one, one thing to watch).
- Then talk through the items by group, in this order: getting around (closures, detours, transit), things worth your time (events and clubs), civic (council votes, hearings). Skip a group that has no items. Cover every item; leaving one out is wrong.
- No numbering and no labels: never First, Second, Third, And finally, Why it matters, The reason.
- Weave the reason into the sentence (since you follow the hiking club, right on your bike route, close to home) instead of stating it separately. Use the strongest reason, listed first. Never use the same reason phrase twice: if two items are both near home or both match an interest, word the second one differently or leave its reason out.
- One concrete action per item, phrased naturally and varied (worth adding to your calendar, leave five minutes early, worth a look if you have opinions).
- Smooth transitions between items (On the fun side, Later in the week, Over the weekend, One more thing).
- Times the way a person says them (Friday night at ten, Sunday afternoon at two, Monday evening at seven). Mention a price only when the item states one or says free.
- Close with one short, warm line (Have a good week). Never That's your Monday.
Length: 120 to 150 words, never more than 160. Count before you answer; shorter is better than padded.
Facts: use only what the items and profile say. Keep each item's name as given; never add or reinterpret details, places, prices, performers or times. Do not invent anything about the listener or the event: no commutes to work or school that the profile does not state (never "since you walk to work"), no motives or benefits (never "to support our local arts scene", "perfect for fresh food"), no descriptions the item does not give.
Days: every weekday in the items falls in the week of week_of. Say days by name, including for Monday items (Monday evening at seven). Never say today, tonight, tomorrow, this morning or this evening: the listener may hear this on any day, including the weekend before. Keep day and time ranges complete, such as Wednesday to Friday, 7 a.m. to 5 p.m.
Spoken-text rules, all mandatory: no abbreviations (Road, Street, Avenue; North, South, East, West; University of Michigan, not U-M; Monday, not Mon); no symbols (and, not &; 15 dollars, not $15); no URLs, emoji, markdown, lists, headings or parentheses; plain sentences only.
STYLE EXAMPLE, for tone and shape only. Its places, events and people are not this listener's and must never appear in your brief:
"Good morning. It's a pretty easy week, with one thing to plan around. If you bike through Kerrytown, North Fourth Avenue is down to one lane until Thursday, so give yourself a few extra minutes or cut over on Fifth. On the fun side, the hiking club you follow is running pickup soccer on the Diag Sunday afternoon at two, which is an easy one to add to your calendar. Friday night, SCOR has a homecoming pregame at ten if you want to start the weekend early. And on Monday evening at seven, city council votes on the Packard bike lanes, right on your route, so it's worth a look if you have opinions. Have a good week." """;
sem llm_write_brief.profile = "Who the brief is for: name, home area, commute mode and interests.";
sem llm_write_brief.items = "This listener's items, already grouped (Getting around, Worth your time, Civic), each with when, reasons (strongest first) and what to do.";
sem llm_write_brief.week_of = "The Monday this brief is for, e.g. Monday, September 28, 2026. Item days (Monday, Tuesday...) are days of this week.";

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
    groups: list[list[any]] = [["Getting around", ["alert"]], ["Worth your time", ["event", "organizer", "venue"]], ["Civic", ["civic"]]];
    lines: list[str] = [];
    n = 1;
    def by_day(it: dict[str, any]) -> int {
        return int(it.get("day", 0) or 0);
    }
    for g in groups {
        label: str = str(g[0]);
        kinds: list[str] = list(g[1]);
        members = [it for it in items if str(it.get("kind", "")) in kinds];
        if label == "Worth your time" {
            members = sorted(members, key=by_day);
        }
        if len(members) == 0 {
            continue;
        }
        lines.append(label + ":");
        for it in members {
            why = "; ".join([speakable(str(r), ref).rstrip(".") for r in list(it.get("reasons", []))[:3]]);
            name = speakable(str(it["name"]), ref);
            when = speakable(str(it.get("when", "")), ref);
            action = speakable(str(it.get("action", "")), ref);
            lines.append(f"{n}. {name} ({it['kind']}). When: {when}. Reasons: {why}. To do: {action}");
            n += 1;
        }
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
            } elif re.search(STYLE_EXAMPLE_ONLY, spoken) is not None {
                out["error"] = "LLM brief copied the style example; used the template";
            } elif repeated_reason(spoken) {
                out["error"] = f"LLM brief repeats a reason phrase ('{repeated_reason(spoken)}'); used the template";
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
