"""Which week a Monday brief is for. Shared by the Editor, the template, the
relevance "due soon" bonus and the eval, and meant for any other week window.

Rule: Monday to Friday, the brief is for this week's Monday; on Saturday or
Sunday it is already for the upcoming week, so the next Monday. Item days
(0 = Monday ... 6 = Sunday) are days of that brief week.
"""

import from datetime { date, datetime, timedelta }

def _as_date(now: date | datetime | None) -> date {
    if now is None {
        return date.today();
    }
    if isinstance(now, datetime) {
        return now.date();
    }
    return now;
}

"""The Monday the brief is for: this week's Monday on weekdays, next Monday on weekends."""
def brief_monday(now: date | datetime | None = None) -> date {
    d = _as_date(now);
    wd = d.weekday();
    if wd >= 5 {
        return d + timedelta(days=7 - wd);
    }
    return d - timedelta(days=wd);
}

"""Days from the brief's Monday to `now`: 0..4 Monday to Friday, -2 on Saturday,
-1 on Sunday. An item on brief day d is (d - brief_day_index(now)) days away."""
def brief_day_index(now: date | datetime | None = None) -> int {
    d = _as_date(now);
    return (d - brief_monday(d)).days;
}

"""Spoken-style label for the brief week, e.g. "Monday, September 28, 2026"."""
def brief_week_label(now: date | datetime | None = None) -> str {
    m = brief_monday(now);
    return m.strftime("%A, %B ") + str(m.day) + m.strftime(", %Y");
}
