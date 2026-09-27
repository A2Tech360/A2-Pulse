"""Editor stage tests. The LLM path runs against byLLM's MockLLM (no key, no network)."""

import re;
import time;
import from datetime { date }
import from jaclang.byllm.lib { MockLLM, MockError }
import from services { pulse_llm }
import from services.speakable { speakable, word_count }

glob TODAY: date = date(2026, 9, 28);
glob FORBIDDEN: str = r"\b(Rd|St|Ave|Blvd|Dr|Hwy|Pkwy|Mon|Tue|Wed|Thu|Fri|Sat|Sun|AM|PM|U-M)\b|\b[NSEW]\b|[&@$%()*#]|https?:";

# Deliberately un-speakable: abbreviations, symbols, markdown, emoji, a URL and parentheses.
glob RAW_LLM: str = "**Morning Jordan!** 🚲 Plymouth Rd is down to one lane Wed to Fri (7 AM to 5 PM), right on your U-M bike route, so leave 10 min early or use the Fuller Rd path. North Campus Pizza & Game Night is Sat 7:00 PM at Pierpont, free, and close to home. The Plymouth Rd bike lane hearing is Wed 6:30 PM; sign up to comment at https://a2gov.legistar.com. The Bursley-Baits bus skips Pierpont Sat afternoon, so give yourself extra time. Free Jazz Night at Blue LLama on S Main St is Fri 8:00 PM, walk-ins welcome. That's your week!";

glob ITEMS: list[dict[str, any]] = [
    {"name": "Plymouth Rd lane closure", "kind": "alert", "when": "Wed to Fri, 7 AM to 5 PM", "reasons": ["Near your home in North Campus", "On your bike route via Plymouth Rd corridor"], "action": "Leave 10 minutes early or take the Fuller Rd path instead."},
    {"name": "North Campus Pizza & Game Night", "kind": "event", "when": "Sat 7:00 PM", "reasons": ["Close by at Pierpont Commons", "Matches your interest in social"], "action": "Free. Save it to your calendar for Sat 7:00 PM."},
    {"name": "Plymouth Rd protected bike lane plan", "kind": "civic", "when": "Wed 6:30 PM hearing", "reasons": ["Affects North Campus, where you live or travel"], "action": "Sign up for public comment or email Council: Wed 6:30 PM hearing."},
    {"name": "Bursley-Baits bus reroute", "kind": "alert", "when": "Sat afternoon", "reasons": ["Near your home in North Campus"], "action": "Check TheRide trip planner and give yourself 10 extra minutes."},
    {"name": "Free Jazz Night", "kind": "event", "when": "Fri 8:00 PM", "reasons": ["Matches your interest in music", "From U-M Jazz Collective, which you follow"], "action": "RSVP and grab a ticket ($5) for Fri 8:00 PM."}
];

def mock(outputs: list[any]) {
    pulse_llm.set_llm(MockLLM(model_name="mockllm", config={"outputs": outputs}), "mockllm");
}

test "llm output goes through speakable" {
    mock([RAW_LLM]);
    out = edit_brief("Jordan", "Jordan, U-M junior", ITEMS, True, TODAY);
    pulse_llm.set_llm(None);
    assert out["mode"] == "llm", out["error"];
    assert out["model"] == "mockllm";
    assert out["raw_llm"] == RAW_LLM;
    assert out["spoken"] == speakable(RAW_LLM, TODAY);
    assert re.search(FORBIDDEN, out["spoken"]) is None, out["spoken"];
    assert "Plymouth Road" in str(out["spoken"]);
    assert "Saturday at 7 p.m." in str(out["spoken"]);
    assert "University of Michigan" in str(out["spoken"]);
    assert "1. Plymouth Rd lane closure" in str(out["input"]["items"]);
}

test "llm error falls back to the template" {
    mock([MockError(error=RuntimeError("provider down"))]);
    out = edit_brief("Jordan", "Jordan", ITEMS, True, TODAY);
    pulse_llm.set_llm(None);
    assert out["mode"] == "template";
    assert "provider down" in str(out["error"]);
    assert out["raw_llm"] is None;
    assert out["spoken"].startswith("Good morning Jordan.");
}

test "too-short llm output falls back to the template" {
    mock(["Have a good week."]);
    out = edit_brief("Jordan", "Jordan", ITEMS, True, TODAY);
    pulse_llm.set_llm(None);
    assert out["mode"] == "template";
    assert "too short" in str(out["error"]);
    assert out["raw_llm"] == "Have a good week.";
}

test "llm off uses the template with no waiting" {
    pulse_llm.set_llm(None);
    t0 = time.perf_counter();
    out = edit_brief("Jordan", "Jordan", ITEMS, True, TODAY);
    elapsed = time.perf_counter() - t0;
    assert out["mode"] == "template";
    assert out["error"] == "LLM off";
    assert elapsed < 0.5, elapsed;
}

test "template is 140 to 160 speakable words" {
    out = template_brief("Jordan", ITEMS, TODAY);
    assert 140 <= word_count(out) <= 160, f"{word_count(out)}: {out}";
    assert re.search(FORBIDDEN, out) is None, out;
    assert speakable(out, TODAY) == out;
    assert "5 dollars" in out;
}

test "template handles a quiet week and the You persona" {
    assert template_brief("You", [], TODAY) == "Good morning. Nothing in Ann Arbor touches your week yet, so enjoy the quiet. Have a good week.";
    one = template_brief("You", ITEMS[:1], TODAY);
    assert one.startswith("Good morning. One thing touches your week"), one;
}

test "deadline abandons a slow call" {
    def slow -> str {
        time.sleep(2.0);
        return "late";
    }
    res = pulse_llm.call_with_deadline(slow, [], 0.3);
    assert not res["ok"];
    assert "timed out" in res["error"];
    assert res["ms"] < 1000, res["ms"];
}

test "deadline returns values and errors" {
    ok = pulse_llm.call_with_deadline(lambda (a: int, b: int) -> int { return a + b; }, [2, 3], 1.0);
    assert ok["ok"] and ok["value"] == 5;
    def boom -> str {
        raise ValueError("bad");
    }
    bad = pulse_llm.call_with_deadline(boom, [], 1.0);
    assert not bad["ok"] and "ValueError: bad" in bad["error"];
}

test "provider detection" {
    assert pulse_llm.llm_provider("gpt-4o-mini") == "openai";
    assert pulse_llm.llm_provider("claude-haiku-4-5") == "anthropic";
    assert pulse_llm.llm_provider("gemini/gemini-2.0-flash") == "gemini";
    assert pulse_llm.llm_provider("ollama/llama3.1") == "ollama";
    assert pulse_llm.llm_provider("mystery-model") == "";
}

test "template never trims the time of an alert or civic item" {
    long_items: list[dict[str, any]] = [
        {**it, "reasons": list(it["reasons"]) + ["Coming up in the next 2 days", "From City of Ann Arbor, which you follow"]}
        for it in ITEMS
    ];
    out = template_brief("Jordan", long_items, TODAY);
    assert word_count(out) <= 165, word_count(out);
    for it in long_items {
        if str(it["when"]) not in str(it["action"]) {
            assert speakable(str(it["when"]), TODAY) in out, f"{it['when']} missing from: {out}";
        }
    }
    assert "Wednesday to Friday, 7 a.m. to 5 p.m." in out;
    assert "Saturday afternoon" in out;
}

test "reasons are ordered strongest first" {
    rules: list[dict[str, any]] = [
        {"rule": "interest", "points": 1.5, "detail": "Matches your interest in music"},
        {"rule": "follows", "points": 2.0, "detail": "From U-M Jazz Collective, which you follow"},
        {"rule": "near_venue", "points": 1.0, "detail": "Close by at The Ark"},
        {"rule": "near_venue", "points": 1.0, "detail": "Close by at The Ark"}
    ];
    got = strongest_first(["Matches your interest in music", "Close by at The Ark", "From U-M Jazz Collective, which you follow"], rules);
    # The double-counted "Close by" counts once, so it does not tie with the follow.
    assert got == ["From U-M Jazz Collective, which you follow", "Matches your interest in music", "Close by at The Ark"], got;
}

test "unlabeled reasons read as sentences and mid-sentence times are lowercase" {
    one: list[dict[str, any]] = [{"name": "State St sidewalk closure", "kind": "alert", "when": "All week", "reasons": ["From City of Ann Arbor, which you follow"], "action": "Use the east side crossing."}];
    out = template_brief("Luis", one, TODAY);
    assert "State Street sidewalk closure, all week." in out, out;
    assert _why_sentence("from Michigan Hiking Club, which you follow") == "It's from Michigan Hiking Club, which you follow";
    assert _why_sentence("affects Central Campus, where you live or travel") == "It affects Central Campus, where you live or travel";
    assert _mid_sentence("Thu all day") == "Thu all day";
}

test "the Editor is told the Monday the brief is for, never today's date" {
    mock(["Good morning Jordan. " + " ".join(["word"] * 120)]);
    out = edit_brief("Jordan", "Jordan", ITEMS, True, date(2026, 9, 26));
    pulse_llm.set_llm(None);
    assert out["input"]["week_of"] == "Monday, September 21, 2026", out["input"];
    assert "today" not in dict(out["input"]);
    sunday = edit_brief("Jordan", "Jordan", ITEMS, False, date(2026, 9, 27));
    assert sunday["input"]["week_of"] == "Monday, September 21, 2026";
    monday = edit_brief("Jordan", "Jordan", ITEMS, False, date(2026, 9, 28));
    assert monday["input"]["week_of"] == "Monday, September 28, 2026";
}

test "an LLM brief over 180 words falls back to the template" {
    long = "Good morning Jordan. " + " ".join(["Plymouth Road is busy this week."] * 40);
    mock([long]);
    out = edit_brief("Jordan", "Jordan", ITEMS, True, TODAY);
    pulse_llm.set_llm(None);
    assert out["mode"] == "template";
    assert "too long" in str(out["error"]), out["error"];
    assert out["raw_llm"] == long;
    assert out["spoken"].startswith("Good morning Jordan.") and out["words"] <= 165;
}

test "an LLM brief that says today, tonight or tomorrow falls back to the template" {
    for word in ["today", "Tonight", "tomorrow"] {
        text = "Good morning Jordan. The council votes " + word + " at 7 p.m. " + " ".join(["Plymouth Road work runs all week."] * 12);
        mock([text]);
        out = edit_brief("Jordan", "Jordan", ITEMS, True, TODAY);
        pulse_llm.set_llm(None);
        assert out["mode"] == "template", word;
        assert word in str(out["error"]), out["error"];
    }
}
