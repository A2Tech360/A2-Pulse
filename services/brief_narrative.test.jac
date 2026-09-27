"""Narrative template tests: friend-style structure, no list labels, natural times."""

import re;
import from datetime { date }

glob TODAY: date = date(2026, 9, 26);

glob ITEMS: list[dict[str, any]] = [
    {"name": "North Campus Pizza & Game Night", "kind": "event", "when": "Sat 7:00 PM", "day": 5, "reasons": ["From U-M Career Center, which you follow", "Close by at Pierpont Commons"], "action": "Free. Save it to your calendar for Sat 7:00 PM."},
    {"name": "Plymouth Rd lane closure", "kind": "alert", "when": "Wed to Fri, 7 AM to 5 PM", "day": 2, "reasons": ["Near your home in North Campus", "On your bike route via Plymouth Rd corridor"], "action": "Leave 10 minutes early or take the Fuller Rd path instead."},
    {"name": "Free Jazz Night", "kind": "event", "when": "Fri 8:00 PM", "day": 4, "reasons": ["From U-M Jazz Collective, which you follow", "Matches your interest in music"], "action": "Free. Save it to your calendar for Fri 8:00 PM."},
    {"name": "Plymouth Rd protected bike lane plan", "kind": "civic", "when": "Wed 6:30 PM hearing", "day": 2, "reasons": ["Affects North Campus, where you live or travel"], "action": "Sign up for public comment or email Council: Wed 6:30 PM hearing."},
    {"name": "Folk Songwriters Round", "kind": "event", "when": "Sat 7:30 PM", "day": 5, "reasons": ["Matches your interest in music"], "action": "RSVP and grab a ticket ($15) for Sat 7:30 PM."}
];

def brief -> str {
    return narrative_brief("Jordan", ITEMS, TODAY);
}

test "opens with a greeting and a line that sets up the week, closes warmly" {
    out = brief();
    assert out.startswith("Good morning, Jordan. It's a pretty easy week"), out;
    assert re.search(r"(Have a good week|Enjoy the week|Have a great week out there)\.$", out), out;
    assert "That's your Monday" not in out;
}

test "no list labels or ordinals" {
    out = brief();
    assert re.search(r"Why it matters|The reason:|Why it's here|Why you'd care|Why it made the list", out) is None, out;
    assert re.search(r"\b(First|Second|Third|Fourth|Fifth|And finally),", out) is None, out;
}

test "groups run getting around, then fun, then civic" {
    out = brief();
    a = out.index("Plymouth Road lane closure");
    f = out.index("Free Jazz Night");
    c = out.index("protected bike lane plan");
    assert a < f < c, out;
    assert out.index("Free Jazz Night") < out.index("North Campus Pizza"), "fun items go in day order";
}

test "reasons are woven in and never repeated" {
    out = brief();
    assert "since you follow University of Michigan Jazz Collective" in out or "since you follow University of Michigan Career Center" in out, out;
    for stem in ["since you follow", "who you follow", "since you're into", "close to home", "right on your", "your part of town"] {
        assert out.count(stem) <= 1, f"{stem!r} repeated: {out}";
    }
}

test "natural times, prices only from the item, whole-brief length" {
    out = brief();
    assert "Friday evening at eight" in out and "Saturday evening at seven thirty" in out, out;
    assert "hearing on Wednesday evening at six thirty" in out, out;
    assert "15 dollars" in out;
    assert 130 <= word_count(out) <= 180, word_count(out);
    assert speakable(out, TODAY) == out;
}

test "natural_when handles the seed and live formats" {
    assert natural_when("Sun 2:00 PM", TODAY) == "Sunday afternoon at two";
    assert natural_when("Fri 10:00 PM", TODAY) == "Friday night at ten";
    assert natural_when("Sat 12:00 PM", TODAY) == "Saturday at noon";
    assert natural_when("Sun 11:00 AM", TODAY) == "Sunday morning at eleven";
    assert natural_when("Mon 7:00 PM, public comment sign-up by Mon noon", TODAY) == "Monday evening at seven, with public comment sign-up by Monday at noon";
    assert natural_when("2026-10-10 19:30", TODAY) == "Saturday, October 10th, at seven thirty in the evening";
    assert natural_when("All week", TODAY) == "all week";
    assert natural_when("Thu all day", TODAY) == "Thursday all day";
}

test "a quiet week still reads naturally" {
    assert narrative_brief("You", [], TODAY).startswith("Good morning. It's a quiet week");
}
