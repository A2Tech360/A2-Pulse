"""Real calendar dates for Pulse items, and the Monday brief's week window.

Seed items only name a weekday of the brief week ("Fri 8:00 PM"); live listings
carry a real date ("2026-10-10 19:30:00", "Saturday, October 10, 2026").
"""

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
