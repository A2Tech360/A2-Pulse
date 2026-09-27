"""Real calendar dates for Pulse items, and the Monday brief's week window.

Seed items only name a weekday of the brief week ("Fri 8:00 PM"); live listings
carry a real date ("2026-10-10 19:30:00", "Saturday, October 10, 2026").
"""

import re;
import from datetime { date, timedelta }
import from services.event_dates { extract_event_date, parse_iso_date }

"""ISO date (YYYY-MM-DD) an item happens on, or "" when its text names no calendar
date. `stored` (PulseNode.on_date) wins; otherwise the when text is parsed, with the
year taken from `ref` when the text has none."""
def item_iso_date(when: str, stored: str = "", ref: date | None = None) -> str {
    if stored {
        d = parse_iso_date(stored);
        if d is not None {
            return d.isoformat();
        }
    }
    year = (ref if ref is not None else date.today()).year;
    found = extract_event_date(when or "", year);
    return found.isoformat() if found is not None else "";
}

"""True when an item belongs in the brief for the week starting `monday` (Monday
to Sunday). Dated items must fall inside that week. Undated live listings are
dropped (we can't place them in a week); undated seed items are weekday items of
the brief week, so they stay."""
def in_brief_week(when: str, stored: str, is_live: bool, monday: date) -> bool {
    iso = item_iso_date(when, stored, monday);
    if not iso {
        return not is_live;
    }
    d = date.fromisoformat(iso);
    return monday <= d and d <= monday + timedelta(days=6);
}

glob _ISO_WHEN: str = r"^\s*(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?)?\s*(?:[+-]\d{2}:?\d{2}|Z)?\s*$";
glob _WD_SHORT: list[str] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
glob _MON_SHORT: list[str] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

"""Card-friendly when text: "2026-10-10 19:30:00" -> "Sat, Oct 10 · 7:30 PM",
"2026-10-10" -> "Sat, Oct 10". Anything that isn't a bare ISO date/time (e.g. seed
"Fri 8:00 PM", "Wed to Fri, 7 AM to 5 PM") is returned unchanged."""
def friendly_when(when: str) -> str {
    m = re.match(_ISO_WHEN, when or "");
    if not m {
        return when or "";
    }
    try {
        d = date(int(m.group(1)), int(m.group(2)), int(m.group(3)));
    } except ValueError {
        return when;
    }
    label = _WD_SHORT[d.weekday()] + ", " + _MON_SHORT[d.month - 1] + " " + str(d.day);
    if m.group(4) is None {
        return label;
    }
    h = int(m.group(4));
    mm = m.group(5);
    if h > 23 or int(mm) > 59 {
        return label;
    }
    ap = "PM" if h >= 12 else "AM";
    h12 = h % 12 or 12;
    return label + " · " + str(h12) + ":" + mm + " " + ap;
}
