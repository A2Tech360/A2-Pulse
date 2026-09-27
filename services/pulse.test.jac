"""End-to-end GenerateBrief tests (MockLLM for the Editor, so no key or network)."""

import re;
import from jaclang.byllm.lib { MockLLM }
import from services { pulse_llm }
import from services.speakable { speakable }

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
