"""speakable(text): deterministic rewrite of anything sent to text-to-speech.

Expands abbreviations (road suffixes, directions, days, months, U-M), turns
symbols into words, reads times as "7 p.m." and dates as "Tuesday, September
29th", and strips URLs, emoji, markdown and parentheses. Idempotent, so it is
safe to apply to LLM output, template output, and again right before TTS.

Ambiguous cases: "St." / "Dr." after a street name (a capitalized word or a
number) are Street / Drive; before a capitalized name otherwise they are
Saint / Doctor ("St. Joseph" -> "Saint Joseph", "Dr. Lee" -> "Doctor Lee").
"""

import re;
import from datetime { date }

glob WEEKDAYS: list[str] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
glob MONTH_NAMES: list[str] = [
    "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December"
];
glob DAY_ABBR: dict[str, str] = {
    "Mon": "Monday", "Tue": "Tuesday", "Tues": "Tuesday", "Wed": "Wednesday",
    "Thu": "Thursday", "Thur": "Thursday", "Thurs": "Thursday", "Fri": "Friday",
    "Sat": "Saturday", "Sun": "Sunday"
};
glob MONTH_ABBR: dict[str, str] = {
    "Jan": "January", "Feb": "February", "Mar": "March", "Apr": "April", "Jun": "June",
    "Jul": "July", "Aug": "August", "Sep": "September", "Sept": "September",
    "Oct": "October", "Nov": "November", "Dec": "December"
};
# Unambiguous road suffixes (title-case, whole word).
glob ROAD_ALWAYS: dict[str, str] = {
    "Rd": "Road", "Ave": "Avenue", "Av": "Avenue", "Blvd": "Boulevard", "Hwy": "Highway",
    "Pkwy": "Parkway", "Fwy": "Freeway", "Expy": "Expressway"
};
# Road suffixes that collide with other words: only expanded right after a street name.
glob ROAD_AFTER_NAME: dict[str, str] = {
    "Ln": "Lane", "Ct": "Court", "Cir": "Circle", "Ter": "Terrace", "Pl": "Place",
    "Sq": "Square", "Trl": "Trail"
};
glob DIRECTIONS: dict[str, str] = {
    "N": "North", "S": "South", "E": "East", "W": "West",
    "NE": "Northeast", "NW": "Northwest", "SE": "Southeast", "SW": "Southwest"
};
# Capitalized words that are not street names, so "Meet Dr. Lee" stays Doctor.
glob NOT_STREET: list[str] = [
    "meet", "with", "ask", "join", "call", "email", "see", "hear", "thank", "thanks",
    "from", "by", "and", "or", "the", "a", "an", "our", "your", "my", "his", "her",
    "their", "professor", "dean", "says", "said", "featuring", "visit", "near", "at",
    "to", "on", "in", "for", "via", "off", "hosted", "welcome", "hi", "hello", "dear",
    "including", "plus", "then", "also", "both", "good", "morning", "today", "tonight",
    "tomorrow", "this", "next", "last", "every", "saint", "doctor", "is", "was", "if",
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    "january", "february", "march", "april", "may", "june", "july", "august",
    "september", "october", "november", "december"
];
# Whole-phrase expansions, applied in order (regex, replacement).
glob PHRASES: list[list[str]] = [
    [r"\bU-M\b", "University of Michigan"],
    [r"\bU of M\b", "University of Michigan"],
    [r"\bUofM\b", "University of Michigan"],
    [r"\bUMich\b", "University of Michigan"],
    [r"\bAADL\b", "Ann Arbor District Library"],
    [r"\bDDA\b", "Downtown Development Authority"],
    [r"\bUMS\b", "University Musical Society"],
    [r"\bSEAS\b", "School for Environment and Sustainability"],
    [r"\bA2\b", "Ann Arbor"],
    [r",\s*MI\b", ", Michigan"],
    [r"\be\.g\.,?", "for example"],
    [r"\bi\.e\.,?", "that is"],
    [r"\betc\.", "and so on"],
    [r"\bvs\.?(?=\s)", "versus"],
    [r"\bapprox\.?(?=\s)", "about"],
    [r"\bw/(?=\s)", "with"],
    [r"\band/or\b", "or"],
    [r"\b24/7\b", "around the clock"],
    [r"\bMt\.?(?=\s+[A-Z])", "Mount"],
    [r"\bMr\.(?=\s)", "Mister"],
    [r"\bProf\.(?=\s)", "Professor"],
    [r"\bNo\.\s*(?=\d)", "number "],
    [r"\bSte\.?\s*(?=\d)", "Suite "],
    [r"\bRte\.?(?=\s+\d)", "Route"]
];

def _ordinal(n: int) -> str {
    if 11 <= n % 100 <= 13 {
        return f"{n}th";
    }
    return f"{n}" + {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th");
}

"""Spoken date: "Tuesday, September 29th" (year only when it is not this year)."""
def _spoken_date(y: int, m: int, d: int, today: date) -> str {
    try {
        dt = date(y, m, d);
    } except ValueError {
        return f"{MONTH_NAMES[m - 1]} {_ordinal(d)}";
    }
    out = f"{WEEKDAYS[dt.weekday()]}, {MONTH_NAMES[m - 1]} {_ordinal(d)}";
    if y != today.year {
        out += f", {y}";
    }
    return out;
}

"""Year for a month/day with no year: the one closest to today."""
def _nearest_year(m: int, d: int, today: date) -> int {
    best = today.year;
    best_gap = 9999;
    for y in [today.year - 1, today.year, today.year + 1] {
        try {
            gap = abs((date(y, m, d) - today).days);
        } except ValueError {
            continue;
        }
        if gap < best_gap {
            best = y;
            best_gap = gap;
        }
    }
    return best;
}

"""Is the word right before position `end` a street name (so St/Dr mean Street/Drive)?"""
def _street_before(text: str, end: int) -> bool {
    m = re.search(r"(\S+)\s+$", text[:end]);
    if m is None {
        return False;
    }
    prev = m.group(1);
    if re.search(r"[,.;:!?)\]]$", prev) {
        return False;
    }
    if re.fullmatch(r"\d+(st|nd|rd|th)?", prev) {
        return True;
    }
    return bool(re.fullmatch(r"[A-Z][\w'’.-]*", prev)) and prev.lower() not in NOT_STREET;
}

"""Keep an abbreviation's period only when it also ends the sentence."""
def _tail_dot(dot: str, after: str) -> str {
    if not dot {
        return "";
    }
    if after.strip() == "" or re.match(r"\s+[A-Z]", after) {
        return ".";
    }
    return "";
}

def _road_sub(m: re.Match[str]) -> str {
    word = m.group(1);
    dot = m.group(2);
    text = m.string;
    after = text[m.end():];
    street = _street_before(text, m.start());
    next_cap = re.match(r"\s+[A-Z]", after) is not None;
    full = "";
    if word == "St" {
        full = "Street" if street or not next_cap else "Saint";
    } elif word == "Dr" {
        full = "Drive" if street or not next_cap else "Doctor";
    } elif word in ROAD_ALWAYS {
        full = ROAD_ALWAYS[word];
    } elif street {
        full = ROAD_AFTER_NAME[word];
    } else {
        return m.group(0);
    }
    if full == "Saint" or full == "Doctor" {
        return full;
    }
    return full + _tail_dot(dot, after);
}

def _day_sub(m: re.Match[str]) -> str {
    return DAY_ABBR[m.group(1)] + _tail_dot(m.group(2), m.string[m.end():]);
}

def _dir_sub(m: re.Match[str]) -> str {
    return DIRECTIONS[m.group(1)];
}

def _time_sub(m: re.Match[str]) -> str {
    h = int(m.group(1));
    mm = m.group(2) or "00";
    ap = m.group(3).lower();
    if h > 12 or int(mm) > 59 {
        return m.group(0);
    }
    if h == 12 and mm == "00" {
        return "noon" if ap == "p" else "midnight";
    }
    clock = str(h) if mm == "00" else f"{h}:{mm}";
    return clock + (" p.m." if ap == "p" else " a.m.");
}

def _money_sub(m: re.Match[str]) -> str {
    dollars = int(m.group(1).replace(",", ""));
    cents = int(m.group(2)) if m.group(2) else 0;
    out = f"{dollars} dollar" + ("" if dollars == 1 else "s");
    if cents > 0 {
        out += f" and {cents} cent" + ("" if cents == 1 else "s");
    }
    return out;
}

def _distance_sub(m: re.Match[str]) -> str {
    num: str = m.group(1);
    if num.endswith(".0") {
        num = num[:-2];
    }
    unit: str = {"mi": "mile", "min": "minute", "mins": "minute", "hr": "hour", "hrs": "hour", "ft": "foot"}[m.group(2)];
    if num != "1" {
        unit = "feet" if unit == "foot" else unit + "s";
    }
    return num + " " + unit;
}

"""Line-by-line markdown flattening: drop headings, bullets and list numbers;
end each line with punctuation so flattened lines stay separate sentences."""
def _flatten_lines(text: str) -> str {
    out: list[str] = [];
    for raw in text.splitlines() {
        line: str = raw.strip();
        line = re.sub(r"^#{1,6}\s*", "", line);
        line = re.sub(r"^>\s?", "", line);
        line = re.sub(r"^[-*•+]\s+", "", line);
        line = re.sub(r"^\d{1,2}[.)]\s+", "", line);
        line = line.strip();
        if line {
            out.append(line);
        }
    }
    for i in range(len(out) - 1) {
        if not re.search(r"[.!?:;,]$", out[i]) {
            out[i] = out[i] + ".";
        }
    }
    return " ".join(out);
}

"""Rewrite `text` so it reads naturally out loud. `today` anchors dates (tests pass it)."""
def speakable(text: str, today: date | None = None) -> str {
    if not text {
        return "";
    }
    ref = today or date.today();
    t: str = str(text);

    # Links, URLs, markdown, emoji.
    t = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", t);
    t = re.sub(r"https?://\S+", " ", t);
    t = re.sub(r"\bwww\.\S+", " ", t);
    t = re.sub(r"\b[\w-]+\.(?:com|org|edu|gov|net|io|ai)(?:/\S*)?(?=[\s,;:!?]|\.?$|\.\s)", " ", t);
    t = _flatten_lines(t);
    t = re.sub(r"\*\*|__|~~|`+", "", t);
    t = re.sub(r"(?<!\w)[*_]|[*_](?!\w)", "", t);
    t = re.sub(r"[\U0001F000-\U0001FAFF☀-➿⬀-⯿⌀-⏿️‍⃣]", " ", t);
    t = t.replace("→", " to ").replace("…", ".").replace("·", ", ").replace("•", ", ");

    # Names and fixed phrases.
    for pr in PHRASES {
        t = re.sub(pr[0], pr[1], t);
    }

    # Symbols.
    t = t.replace("&amp;", " and ").replace("&", " and ").replace("@", " at ");
    t = re.sub(r"\$(\d[\d,]*)(?:\.(\d{2}))?", _money_sub, t);
    t = t.replace("$", "");
    t = re.sub(r"(\d)\s*%", r"\1 percent", t);
    t = re.sub(r"#(?=\d)", "number ", t);
    t = re.sub(r"(\d)\+", r"\1 plus", t);
    t = t.replace("+", " plus ");
    t = re.sub(r"\b(\d+(?:\.\d+)?)\s?(mi|mins|min|hrs|hr|ft)\b\.?", _distance_sub, t);

    # Dates (before "/" and "-" are touched).
    t = re.sub(
        r"\b(\d{4})-(\d{2})-(\d{2})\b",
        lambda (m: re.Match[str]) -> str { return _spoken_date(int(m.group(1)), int(m.group(2)), int(m.group(3)), ref); },
        t
    );
    t = re.sub(
        r"(?<![\d/])(1[0-2]|0?[1-9])/(3[01]|[12]\d|0?[1-9])(?:/(\d{4}|\d{2}))?(?![\d/])",
        lambda (m: re.Match[str]) -> str {
            mo = int(m.group(1));
            d = int(m.group(2));
            y = _nearest_year(mo, d, ref);
            if m.group(3) {
                y = int(m.group(3)) if len(m.group(3)) == 4 else 2000 + int(m.group(3));
            }
            return _spoken_date(y, mo, d, ref);
        },
        t
    );
    t = re.sub(
        r"(?<![\w'’-])(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)\.?(?=\s+\d)",
        lambda (m: re.Match[str]) -> str { return MONTH_ABBR[m.group(1)]; },
        t
    );
    t = re.sub(
        r"(?<![\w'’])(Mon|Tues|Tue|Wed|Thurs|Thur|Thu|Fri|Sat|Sun)(\.?)(?![\w'’])",
        _day_sub,
        t
    );
    month_alt = "|".join(MONTH_NAMES);
    day_alt = "|".join(WEEKDAYS);
    t = re.sub(
        r"(?:\b(" + day_alt + r"),?\s+)?\b(" + month_alt + r")\s+(\d{1,2})(?:st|nd|rd|th)?\b(?![:\d])(?:,?\s+(\d{4})\b)?",
        lambda (m: re.Match[str]) -> str {
            mo = MONTH_NAMES.index(m.group(2)) + 1;
            d = int(m.group(3));
            y = int(m.group(4)) if m.group(4) else _nearest_year(mo, d, ref);
            return _spoken_date(y, mo, d, ref);
        },
        t
    );

    # Times: 7:00 PM -> 7 p.m.; 12 PM -> noon; ranges and "Monday 7 p.m." -> "Monday at 7 p.m.".
    t = re.sub(r"\b(\d{1,2})(?::(\d{2}))?\s*([AaPp])\.?\s*[Mm]\b\.?", _time_sub, t);
    t = re.sub(r"(\d)\s*[-–—]\s*(\d{1,2}(?::\d{2})? [ap]\.m\.)", r"\1 to \2", t);
    t = re.sub(r"(\d [ap]\.m\.)\s*[-–—]\s*(\d)", r"\1 to \2", t);
    t = re.sub(r"\b(" + day_alt + r")\s*[-–—]\s*(" + day_alt + r")\b", r"\1 to \2", t);
    t = re.sub(r"\b(" + day_alt + r") (\d{1,2}(?::\d{2})? [ap]\.m\.|noon|midnight)", r"\1 at \2", t);

    # Directions, then road suffixes (Street/Saint, Drive/Doctor).
    t = re.sub(r"(?<![\w'’.-])(NE|NW|SE|SW|N|S|E|W)\.?(?=\s+(?:[A-Z]|\d))", _dir_sub, t);
    road_alt = "|".join(["St", "Dr"] + list(ROAD_ALWAYS.keys()) + list(ROAD_AFTER_NAME.keys()));
    t = re.sub(r"(?<![\w'’-])(" + road_alt + r")(\.?)(?![\w'’])", _road_sub, t);

    # Parentheses and leftover symbols become pauses or disappear.
    t = re.sub(r"[(\[{]", ", ", t);
    t = re.sub(r"[)\]}]", ", ", t);
    t = t.replace("—", ", ").replace("–", ", ");
    t = re.sub(r"(\w)/(\w)", r"\1 or \2", t);
    t = re.sub(r"[<>|^=~*_#\\/]", " ", t);
    t = t.replace("\"", "").replace("“", "").replace("”", "");

    # Whitespace and punctuation tidy-up.
    t = re.sub(r"\s+", " ", t);
    t = re.sub(r"\s+([,.;:!?])", r"\1", t);
    for _ in range(3) {
        t = re.sub(r",\s*,", ",", t);
        t = re.sub(r",\s*([.;:!?])", r"\1", t);
        t = re.sub(r"([;:!?])\s*,", r"\1", t);
        t = re.sub(r"(?<![ap]\.m)\.\s*,", ".", t);
        t = re.sub(r":\s*\.", ".", t);
    }
    t = re.sub(r"\.{2,}", ".", t);
    t = re.sub(r"([,;:!?])(?=[A-Za-z])", r"\1 ", t);
    t = re.sub(r"\s+", " ", t);
    return t.strip(" ,;:");
}

"""Word count used for the 140-160 word target."""
def word_count(text: str) -> int {
    return len([w for w in re.split(r"\s+", text.strip()) if w]);
}
