"""Calendar-date matching for Pulse events (when strings + weekday fallback)."""

from __future__ import annotations

import re
from datetime import date, datetime, timedelta
from typing import Optional

MONTH_NUM = {
    "january": 1,
    "jan": 1,
    "february": 2,
    "feb": 2,
    "march": 3,
    "mar": 3,
    "april": 4,
    "apr": 4,
    "may": 5,
    "june": 6,
    "jun": 6,
    "july": 7,
    "jul": 7,
    "august": 8,
    "aug": 8,
    "september": 9,
    "sep": 9,
    "sept": 9,
    "october": 10,
    "oct": 10,
    "november": 11,
    "nov": 11,
    "december": 12,
    "dec": 12,
}


def parse_iso_date(raw: str) -> Optional[date]:
    s = (raw or "").strip()
    if not s:
        return None
    try:
        return date.fromisoformat(s[:10])
    except Exception:
        return None


def extract_event_date(when: str, fallback_year: int | None = None) -> Optional[date]:
    """Best-effort absolute calendar date from a free-form when string."""
    text = (when or "").strip()
    if not text:
        return None
    year = fallback_year if fallback_year is not None else date.today().year

    m = re.search(r"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b", text)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except Exception:
            pass

    m = re.search(
        r"\b(January|February|March|April|May|June|July|August|September|"
        r"October|November|December|"
        r"Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\s+"
        r"(\d{1,2})(?:st|nd|rd|th)?(?:,?\s*(20\d{2}))?\b",
        text,
        re.IGNORECASE,
    )
    if m:
        mon = MONTH_NUM.get(m.group(1).lower())
        day = int(m.group(2))
        yr = int(m.group(3)) if m.group(3) else year
        if mon:
            try:
                return date(yr, mon, day)
            except Exception:
                pass

    m = re.search(r"\b(\d{1,2})/(\d{1,2})/(20\d{2})\b", text)
    if m:
        try:
            return date(int(m.group(3)), int(m.group(1)), int(m.group(2)))
        except Exception:
            pass

    return None


def event_matches_date(
    when: str, weekday: int, target_iso: str
) -> tuple[bool, str]:
    """
    Returns (matches, confidence) where confidence is
    'exact' | 'weekday' | 'none'.
    """
    target = parse_iso_date(target_iso)
    if target is None:
        return True, "none"

    absolute = extract_event_date(when, fallback_year=target.year)
    if absolute is not None:
        # If year was omitted and we landed in the past vs target, try next year.
        if absolute.year == target.year and absolute < target - timedelta(days=180):
            try:
                absolute = date(target.year + 1, absolute.month, absolute.day)
            except Exception:
                pass
        return absolute == target, "exact"

    if 0 <= int(weekday) <= 6:
        return int(weekday) == target.weekday(), "weekday"

    return False, "none"


def future_iso_dates(count: int = 14, start: date | None = None) -> list[str]:
    base = start or date.today()
    return [(base + timedelta(days=i)).isoformat() for i in range(max(count, 1))]


def label_for_iso(iso: str, today: date | None = None) -> str:
    d = parse_iso_date(iso)
    if d is None:
        return iso
    now = today or date.today()
    if d == now:
        return "Today"
    if d == now + timedelta(days=1):
        return "Tomorrow"
    # Portable "Sat Oct 4" without leading zero issues.
    return f"{d.strftime('%a')} {d.strftime('%b')} {d.day}"
