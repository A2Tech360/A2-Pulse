"""Template fallback that sounds like a friend who knows Ann Arbor talking you
through the week, not a numbered list.

Structure: greeting and one line that sets up the week; then grouped sections
(getting around, things worth your time, civic), each skipped when empty; the
strongest reason woven into each sentence with rotating phrasings so no reason
phrase repeats; one naturally worded action per item, varied by kind; human
times ("Friday evening at eight"); a short warm closing. Aims for 130-180
spoken words. Returns speakable text.
"""

import re;
import from datetime { date }
import from services.speakable { speakable, word_count }

glob MIN_WORDS: int = 130;
glob MAX_WORDS: int = 178;

glob DAY_NAMES: dict[str, str] = {
    "mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday",
    "fri": "Friday", "sat": "Saturday", "sun": "Sunday"
};
glob HOUR_WORDS: list[str] = [
    "twelve", "one", "two", "three", "four", "five", "six", "seven", "eight",
    "nine", "ten", "eleven", "twelve"
];
glob MINUTE_WORDS: dict[int, str] = {15: "fifteen", 30: "thirty", 45: "forty-five"};

# Reason text from the relevance agent -> spoken phrasings. Each pattern rotates
# through its variants so the same phrase is never used twice in one brief.
glob REASON_PATTERNS: list[list[any]] = [
    ["home", r"Near your home in (.+)", ["close to home in {0}", "near your place in {0}", "just by your home in {0}"]],
    ["route", r"On your (\w+) route via (.+)", ["right on your {0} route through {1}", "along your {0} route via {1}", "in the way of your {0} ride through {1}"]],
    ["area", r"Affects (.+), where you live or travel", ["and it touches {0}, your part of town", "and it affects {0}, where you get around", "and it lands in {0}, close to you"]],
    ["near", r"Close by at (.+)", ["just around the corner at {0}", "a short trip to {0}", "close by at {0}"]],
    ["interest", r"Matches your interest in (.+)", ["since you're into {0}", "right up your alley if you like {0}", "a good pick for your {0} side"]],
    ["follow", r"From (.+), which you follow", ["since you follow {0}", "from {0}, who you follow", "hosted by {0}, one of your follows"]]
];

glob FREE_ACTIONS: list[str] = [
    "and it's free, an easy one to add to your calendar",
    "and it's free, so it's worth a spot on your calendar",
    "and it's free if you want to drop by"
];
glob PAID_ACTIONS: list[str] = [
    "and tickets are {0} dollars if you want to go",
    "and it's {0} dollars, so grab a ticket if it sounds good",
    "worth the {0} dollars if you're around"
];
glob OPEN_ACTIONS: list[str] = ["worth adding to your calendar", "an easy one to pencil in", "worth a look"];
glob FUN_LEADS_FIRST: list[str] = ["On the fun side, ", "For things worth your time, "];
glob CIVIC_LEADS: list[str] = ["And on the civic side, ", "One more thing: "];
glob CIVIC_ASKS: list[str] = [
    "so sign up to comment or email the council if you have opinions",
    "and it's a good one to weigh in on if you want a say",
    "worth a look if you care how it goes"
];
glob CLOSINGS: list[str] = ["Have a good week.", "Enjoy the week.", "Have a great week out there."];

def _group(kind: str) -> str {
    if kind == "alert" {
        return "around";
    }
    if kind == "civic" {
        return "civic";
    }
    return "fun";
}

def _part_of_day(h24: int) -> str {
    if h24 < 12 {
        return "morning";
    }
    if h24 < 17 {
        return "afternoon";
    }
    if h24 < 21 {
        return "evening";
    }
    return "night";
}

def _clock(h24: int, minute: int) -> str {
    if h24 == 12 and minute == 0 {
        return "noon";
    }
    words = HOUR_WORDS[h24 % 12];
    if minute == 0 {
        return words;
    }
    return words + " " + MINUTE_WORDS.get(minute, f"{minute:02d}");
}

"""A time the way a person says it: "Fri 8:00 PM" -> "Friday evening at eight";
"2026-10-10 19:30" -> "Saturday, October 10th, at seven thirty in the evening".
Anything else goes through speakable() (lowercased when it starts mid-sentence)."""
def natural_when(when: str, ref: date | None = None) -> str {
    w = when.strip();
    parts = w.split(", ", 1);
    head = parts[0];
    tail = ", with " + speakable(parts[1], ref) if len(parts) > 1 else "";
    m: any = re.fullmatch(r"(?i)(mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?\s+(\d{1,2}):(\d{2})\s*([AaPp])\.?\s*[Mm]\.?(?:\s+([a-z][a-z ]*))?", head);
    if m is not None {
        h = int(m.group(2)) % 12 + (12 if m.group(4).lower() == "p" else 0);
        minute = int(m.group(3));
        day = DAY_NAMES[m.group(1).lower()];
        clock = _clock(h, minute);
        spoken = f"{day} at noon" if clock == "noon" else f"{day} {_part_of_day(h)} at {clock}";
        # "Wed 6:30 PM hearing" -> "hearing on Wednesday evening at six thirty" (callers say "has a ...").
        if m.group(5) {
            spoken = f"{m.group(5).strip()} on {spoken}";
        }
        return spoken + tail;
    }
    iso: any = re.fullmatch(r"(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})", head);
    if iso is not None {
        h = int(iso.group(2));
        minute = int(iso.group(3));
        day = speakable(iso.group(1), ref);
        clock = _clock(h, minute);
        spoken = f"{day}, at noon" if clock == "noon" else f"{day}, at {clock} in the {_part_of_day(h)}";
        return spoken + tail;
    }
    s = speakable(w, ref);
    first = s.split(" ")[0].rstrip(",") if s else "";
    if first and first not in DAY_NAMES.values() and not first[:1].isdigit() {
        s = s[:1].lower() + s[1:];
    }
    return s;
}

"""The strongest reason that still has an unused phrasing, spoken; "" if none."""
def _reason(reasons: list[str], used: dict[str, int], offset: int = 0) -> str {
    found = 0;
    for r in reasons {
        text = str(r).strip().rstrip(".");
        for pat in REASON_PATTERNS {
            m: any = re.fullmatch(pat[1], text);
            if m is None {
                continue;
            }
            n = used.get(pat[0], 0);
            if n >= len(pat[2]) {
                break;
            }
            if found < offset {
                found += 1;
                break;
            }
            used[pat[0]] = n + 1;
            phrase = pat[2][n].format(*m.groups());
            return re.sub(r"\bin ((?:[\w'.-]+ )*(?:Street|St|Avenue|Ave|Road|Rd|corridor))$", r"on \1", phrase);
        }
    }
    return "";
}

"""The imperative part of a to-do: "Stops may move (All week). Check The Ride alerts
and allow 10 extra minutes." -> "check The Ride alerts and allow 10 extra minutes"."""
def _imperative(action: str, when: str = "") -> str {
    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", action.strip()) if s.strip()];
    verbs = r"(?i)^(check|leave|plan|shift|sign|save|rsvp|allow|give|take|use|avoid|expect|email|comment)\b";
    pick: str = sentences[-1] if sentences else "";
    for s in sentences {
        if re.match(verbs, s) {
            pick = s;
            break;
        }
    }
    pick = pick.rstrip(".");
    if when.strip() and when.strip() in pick {
        pick = pick.replace(when.strip(), "those hours");
    }
    if re.match(r"(?i)^plan around it", pick) {
        return "plan around it";
    }
    if re.match(r"(?i)^sign up for public comment", pick) {
        return "sign up to comment";
    }
    return pick[:1].lower() + pick[1:];
}

def _price_phrase(action: str, k: int) -> str {
    m: any = re.search(r"\$(\d+)", action);
    if m is not None {
        return PAID_ACTIONS[k % len(PAID_ACTIONS)].format(m.group(1));
    }
    if re.match(r"(?i)^free\b", action.strip()) {
        return FREE_ACTIONS[k % len(FREE_ACTIONS)];
    }
    return OPEN_ACTIONS[k % len(OPEN_ACTIONS)];
}

def _the(name: str) -> str {
    n = name.strip();
    if n.lower().startswith(("the", "a ")) {
        return n;
    }
    return "the " + n;
}

def _opening(n_around: int, n_fun: int, n_civic: int) -> str {
    if n_around >= 2 {
        return "It's a busy week for getting around, so there's a bit to plan for.";
    }
    if n_around == 1 {
        return "It's a pretty easy week, with one thing to plan around.";
    }
    if n_fun >= 3 {
        return "It's a good week to get out, with a few things worth your time.";
    }
    return "It's a quiet week, with a couple of things worth knowing about.";
}

"""'is' before a day or time, 'has a' before a noun phrase like 'comment deadline'."""
def _verb_when(when: str) -> str {
    first = when.split(" ")[0].rstrip(",") if when else "";
    if not first or first in DAY_NAMES.values() or first[:1].isdigit() or first in ["all", "on", "this", "every"] {
        return "is " + when;
    }
    return "has a " + when;
}

def _around_sentence(it: dict[str, any], i: int, reason: str, ref: date | None) -> str {
    lead = "Heads up on getting around: " if i == 0 else ["Also on the roads, ", "One more for your commute: "][(i - 1) % 2];
    subject = _the(str(it["name"]));
    if i == 0 {
        subject = subject[:1].lower() + subject[1:];
    }
    when = natural_when(str(it.get("when", "")), ref);
    out = f"{lead}{subject} runs {when}" if when else f"{lead}{subject} is in place";
    if reason {
        out += f", {reason}";
    }
    act = _imperative(str(it.get("action", "")), str(it.get("when", "")));
    if act {
        out += f", so {act}";
    }
    return out + ".";
}

def _fun_sentence(it: dict[str, any], i: int, prev_day: int, used_leads: list[str], reason: str, ref: date | None) -> str {
    day = int(it.get("day", 0) or 0);
    if i == 0 {
        lead = FUN_LEADS_FIRST[0];
    } elif day >= 5 and prev_day < 5 and "weekend" not in used_leads {
        lead = "Over the weekend, ";
        used_leads.append("weekend");
    } elif day > prev_day and "later" not in used_leads {
        lead = "Later in the week, ";
        used_leads.append("later");
    } else {
        options = ["If you want more, ", "Also worth a look, ", "And "];
        lead = options[len(used_leads) % len(options)];
        used_leads.append(lead);
    }
    when = natural_when(str(it.get("when", "")), ref);
    out = f"{lead}{it['name']} {_verb_when(when)}" if when else f"{lead}there's {it['name']}";
    if reason {
        out += f", {reason}";
    }
    out += ", " + _price_phrase(str(it.get("action", "")), i);
    return out + ".";
}

def _civic_sentence(it: dict[str, any], i: int, reason: str, ref: date | None) -> str {
    lead = CIVIC_LEADS[i % len(CIVIC_LEADS)];
    name = str(it["name"]);
    if ": " in name {
        (head, rest) = name.split(": ", 1);
        name = f"{head} on {rest}";
    }
    subject = _the(name) if i == 0 else _the(name)[:1].upper() + _the(name)[1:];
    when = natural_when(str(it.get("when", "")), ref);
    out = f"{lead}{subject} {_verb_when(when)}" if when else f"{lead}{subject} is coming up";
    if reason {
        out += f", {reason}";
    }
    act = _imperative(str(it.get("action", "")), str(it.get("when", "")));
    if act.startswith("sign up to comment") {
        ask = CIVIC_ASKS[i % len(CIVIC_ASKS)];
        out += ", " + ask;
    } elif act {
        out += f", so {act}";
    } else {
        out += ", " + CIVIC_ASKS[(i + 1) % len(CIVIC_ASKS)];
    }
    return out + ".";
}

def _build(first_name: str, items: list[dict[str, any]], reasons_per_item: dict[int, int], ref: date | None) -> str {
    around = [(i, it) for (i, it) in enumerate(items) if _group(str(it["kind"])) == "around"];
    fun = sorted([(i, it) for (i, it) in enumerate(items) if _group(str(it["kind"])) == "fun"], key=lambda (p: tuple) -> int { return int(p[1].get("day", 0) or 0); });
    civic = [(i, it) for (i, it) in enumerate(items) if _group(str(it["kind"])) == "civic"];
    hello = "Good morning." if first_name.strip().lower() in ["", "you"] else f"Good morning, {first_name.strip()}.";
    parts: list[str] = [hello, _opening(len(around), len(fun), len(civic))];
    used: dict[str, int] = {};
    def reason_for(idx: int, it: dict[str, any]) -> str {
        n = reasons_per_item.get(idx, 1);
        if n <= 0 {
            return "";
        }
        first = _reason(list(it.get("reasons", [])), used);
        if n >= 2 and first {
            second = _reason(list(it.get("reasons", [])), used, 1);
            if second {
                return first + (", and " if not second.startswith("and ") else ", ") + second;
            }
        }
        return first;
    }
    for (k, pair) in enumerate(around) {
        parts.append(_around_sentence(pair[1], k, reason_for(pair[0], pair[1]), ref));
    }
    prev = -99;
    fun_leads: list[str] = [];
    for (k, pair) in enumerate(fun) {
        parts.append(_fun_sentence(pair[1], k, prev, fun_leads, reason_for(pair[0], pair[1]), ref));
        prev = int(pair[1].get("day", 0) or 0);
    }
    for (k, pair) in enumerate(civic) {
        parts.append(_civic_sentence(pair[1], k, reason_for(pair[0], pair[1]), ref));
    }
    parts.append(CLOSINGS[sum([ord(c) for c in first_name]) % len(CLOSINGS)]);
    return speakable(" ".join(parts), ref);
}

"""The narrative template brief. Starts with one reason per item; adds a second
reason where it fits when short, drops reasons from the end when long."""
def narrative_brief(first_name: str, items: list[dict[str, any]], ref: date | None = None) -> str {
    if len(items) == 0 {
        hello = "Good morning." if first_name.strip().lower() in ["", "you"] else f"Good morning, {first_name.strip()}.";
        return speakable(f"{hello} It's a quiet week, and nothing in Ann Arbor needs your attention yet. Enjoy the calm.", ref);
    }
    per: dict[int, int] = {i: 1 for i in range(len(items))};
    text = _build(first_name, items, per, ref);
    i = 0;
    while word_count(text) < MIN_WORDS and i < len(items) {
        per[i] = 2;
        longer = _build(first_name, items, per, ref);
        if word_count(longer) <= MAX_WORDS {
            text = longer;
        } else {
            per[i] = 1;
        }
        i += 1;
    }
    j = len(items) - 1;
    while word_count(text) > MAX_WORDS and j >= 0 {
        per[j] = 0;
        text = _build(first_name, items, per, ref);
        j -= 1;
    }
    return text;
}
