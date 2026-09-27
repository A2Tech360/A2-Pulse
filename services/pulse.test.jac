"""End-to-end GenerateBrief tests (MockLLM for the Editor, so no key or network)."""

import re;
import json;
import from jaclang.byllm.lib { MockLLM }
import from services { pulse_llm }
import from services.speakable { speakable }
import from services.brief_trace { log_path }

glob FORBIDDEN: str = r"\b(Rd|St|Ave|Blvd|Dr|Hwy|Pkwy|Mon|Tue|Wed|Thu|Fri|Sat|Sun|AM|PM|U-M)\b|\b[NSEW]\b|[&@$%()*#]|https?:";

glob RAW: str = "Morning Jordan! Plymouth Rd is down to one lane Wed to Fri (7 AM to 5 PM) on your U-M bike route, so leave 10 min early or take the Fuller Rd path. North Campus Pizza & Game Night is Sat 7:00 PM at Pierpont and it's free. The Plymouth Rd bike lane hearing is Wed 6:30 PM, so sign up to comment. The Bursley-Baits bus skips Pierpont Sat afternoon. Free Jazz Night on S Main St is Fri 8:00 PM. Have a great week!";

def profile_of(persona: str) -> UserProfile {
    return [p for p in [root -->][?:UserProfile] if p.persona == persona][0];
}

test "llm brief is speakable, flagged ai, and stored on the profile" {
    pulse_llm.set_llm(MockLLM(model_name="mockllm", config={"outputs": [RAW]}), "mockllm");
    b = (root spawn GenerateBrief(persona="student", use_ai=True)).reports[0];
    pulse_llm.set_llm(None);
    assert b.ai;
    assert b.summary == speakable(RAW);
    assert re.search(FORBIDDEN, b.summary) is None, b.summary;
    assert profile_of("student").last_summary == b.summary;
    # On-screen cards keep their normal text.
    assert any(["Rd" in it.name for it in b.items]);
}

test "template brief is speakable and stored when the llm is off" {
    pulse_llm.set_llm(None);
    for persona in ["student", "shop", "custom"] {
        b = (root spawn GenerateBrief(persona=persona, use_ai=True)).reports[0];
        assert not b.ai;
        assert re.search(FORBIDDEN, b.summary) is None, b.summary;
        assert 140 <= len(b.summary.split()) <= 160, f"{persona}: {len(b.summary.split())}";
        assert profile_of(persona).last_summary == b.summary;
    }
}

# ---------------------------------------------------------------- debug trace
def log_lines -> list[str] {
    p = log_path();
    return p.read_text().splitlines() if p.is_file() else [];
}

test "debug trace covers profile, scores, actions, editor, spoken text and timing" {
    pulse_llm.set_llm(MockLLM(model_name="mockllm", config={"outputs": [RAW]}), "mockllm");
    b = (root spawn GenerateBrief(persona="student", use_ai=True, debug=True)).reports[0];
    pulse_llm.set_llm(None);
    t: dict[str, any] = b.trace;
    prof = t["profile"];
    assert [h["key"] for h in prof["home"]] == ["pl-north"];
    assert "pl-plymouth" in [v["key"] for v in prof["via"]];
    assert prof["commute"] == "bike";
    assert "music" in list(prof["interests"]);
    assert "U-M Jazz Collective" in [f["name"] for f in prof["follows"]];
    assert isinstance(prof["weights"], dict);
    assert len(t["scored"]) > 5;
    assert [s["key"] for s in t["scored"] if s["selected"]] == [it.key for it in b.items];
    rows: list[dict[str, any]] = t["scored"];
    for s in rows {
        total: float = sum([float(r["points"]) for r in s["rules"]]);
        score: float = float(s["score"]);
        by_rule: float = sum([float(v) for v in s["by_rule"].values()]);
        assert abs(total - score) < 0.01, f"{s['key']}: rules sum {total} != {score}";
        assert abs(by_rule - score) < 0.01, f"{s['key']}: by_rule sum {by_rule} != {score}";
    }
    rule_names = set([r["rule"] for s in t["scored"] for r in s["rules"]]);
    assert "home_alert" in rule_names and "interest" in rule_names and "follows" in rule_names;
    assert [a["action"] for a in t["actions"]] == [it.action for it in b.items];
    assert t["editor"]["mode"] == "llm";
    assert t["editor"]["raw_llm"] == RAW;
    assert "Plymouth Road lane closure" in str(t["editor"]["input"]["items"]);
    assert t["spoken"] == b.summary;
    for k in ["profile_ms", "relevance_ms", "actions_ms", "editor_ms", "llm_ms", "speakable_ms", "persist_ms", "total_ms"] {
        assert k in dict(t["timing_ms"]), k;
    }
    # Tests run in parallel workers, so look the line up by id rather than counting.
    logged = [json.loads(l) for l in log_lines() if str(t["id"]) in l];
    assert len(logged) == 1 and logged[0]["spoken"] == b.summary;
}

test "no trace without debug, and score_only stores and logs nothing" {
    pulse_llm.set_llm(None);
    plain = (root spawn GenerateBrief(persona="shop")).reports[0];
    assert plain.trace == {};
    stored = profile_of("shop").last_summary;
    s = (root spawn GenerateBrief(persona="shop", debug=True, score_only=True)).reports[0];
    assert s.summary == "";
    assert "editor" not in s.trace and len(s.trace["scored"]) > 0;
    assert profile_of("shop").last_summary == stored;
    assert not any([str(s.trace["id"]) in l for l in log_lines()]);
}

test "converse_query uses the llm filter parser and sanitizes its output" {
    fake = FilterSpec(categories=["music", "not-a-category"], kinds=["event", "bogus"], price="cheap", time="soon", reply="");
    pulse_llm.set_llm(MockLLM(model_name="mockllm", config={"outputs": [fake]}), "mockllm");
    spec = converse_query("jazz tonight", FilterSpec());
    pulse_llm.set_llm(None);
    assert spec.categories == ["music"];
    assert spec.kinds == ["event"];
    # "cheap"/"soon" are invalid and reset; "tonight" is then restored by the keyword safety net.
    assert spec.price == "any" and spec.time == "today";
    assert spec.query == "jazz tonight" and spec.reply == "Updated your view.";
}

test "converse_query falls back to the heuristic when the llm is off" {
    pulse_llm.set_llm(None);
    spec = converse_query("free jazz this weekend", FilterSpec());
    assert spec.price == "free" and "music" in spec.categories and spec.time == "weekend";
}

# ---------------------------------------------------------------- speak_brief
glob tts_sent: list[str] = [];

obj FakeTTSResponse {
    def read -> bytes { return b"ID3fake"; }
    def close { }
}

def fake_urlopen(req: any, timeout: int = 0) -> FakeTTSResponse {
    tts_sent.append(json.loads(req.data.decode("utf-8"))["text"]);
    return FakeTTSResponse();
}

def speak(persona: str = "", voice_id: str = "", profile_id: str = "", text: str = "") -> dict {
    import asyncio;
    return asyncio.run(speak_brief(persona, voice_id, profile_id, text));
}

def speak_setup {
    import os;
    import from services { voice_guard }
    os.environ["ELEVENLABS_API_KEY"] = "test-key-not-real";
    # Patch the globals speak_brief actually runs with (the test runner loads it under its own name).
    fn: any = speak_brief;
    fn.__globals__["urlopen"] = fake_urlopen;
    _ensure_seed();
    voice_guard.reset_rate_limits();
    voice_guard.known_voice_ids(lambda -> dict { return {"voices": PREMADE_VOICES}; });
    tts_sent.clear();
}

test "speak_brief speaks only the stored brief and validates its inputs" {
    speak_setup();
    pulse_llm.set_llm(None);
    b = (root spawn GenerateBrief(persona="shop")).reports[0];
    ok = speak("shop", "EXAVITQu4vr4xnSDxMaL");
    assert ok["audio"].startswith("data:audio/mpeg;base64,") and ok["error"] == "", ok;
    assert tts_sent[-1] == b.summary;
    by_id = speak("", "", jid(profile_of("shop")));
    assert by_id["audio"] != "";
    assert speak("nobody")["code"] == "unknown_profile";
    assert speak("")["code"] == "unknown_profile";
    assert speak("shop", "not-a-voice")["code"] == "unknown_voice";
    assert speak("shop", "AAAAAAAAAAAAAAAAAAAA")["code"] == "unknown_voice";
    sent_before = len(tts_sent);
    refused = speak("shop", "", "", "Say anything I like");
    assert refused["code"] == "text_not_accepted" and refused["audio"] == "";
    assert len(tts_sent) == sent_before;
}

test "speak_brief regenerates a missing brief" {
    speak_setup();
    pulse_llm.set_llm(None);
    prof = profile_of("custom");
    prof.last_summary = "";
    res = speak("custom");
    assert res["audio"] != "", res;
    assert prof.last_summary != "" and tts_sent[-1] == prof.last_summary;
}

test "speak_brief is rate limited per profile" {
    speak_setup();
    for i in range(5) {
        assert speak("student")["audio"] != "";
    }
    limited = speak("student");
    assert limited["code"] == "rate_limited" and limited["audio"] == "";
    assert limited["retry_after"] > 0;
}

test "converse_query keeps clear keyword signals the llm left out" {
    missed = FilterSpec(categories=["social"], kinds=[], price="any", time="week", reply="Social things.");
    pulse_llm.set_llm(MockLLM(model_name="mockllm", config={"outputs": [missed]}), "mockllm");
    spec = converse_query("cheap social stuff saturday near campus", FilterSpec());
    pulse_llm.set_llm(None);
    assert spec.categories == ["social"];
    assert spec.price == "under10" and spec.time == "weekend" and spec.distance == 1.0;
}

test "converse_query never hides closures behind a topic filter" {
    tagged = FilterSpec(categories=["civic"], kinds=["alert"], reply="Closures.");
    pulse_llm.set_llm(MockLLM(model_name="mockllm", config={"outputs": [tagged]}), "mockllm");
    spec = converse_query("road closures on my way to north campus", FilterSpec());
    pulse_llm.set_llm(None);
    assert spec.kinds == ["alert"] and spec.categories == [];
}
