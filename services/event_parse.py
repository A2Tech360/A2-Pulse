"""Deterministic HTML/text parsers for Ann Arbor public calendars."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime
from html import unescape
from typing import Any

CATEGORIES = [
    "music",
    "food",
    "sports",
    "academic",
    "social",
    "arts",
    "community",
    "outdoor",
    "civic",
    "networking",
    "nightlife",
    "comedy",
]

MONTH_NUM = {
    "january": 1,
    "february": 2,
    "march": 3,
    "april": 4,
    "may": 5,
    "june": 6,
    "july": 7,
    "august": 8,
    "september": 9,
    "october": 10,
    "november": 11,
    "december": 12,
}


def strip_html(html: str) -> str:
    text = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", html)
    text = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", text)
    text = re.sub(r"(?is)<noscript[^>]*>.*?</noscript>", " ", text)
    text = re.sub(r"(?s)<!--.*?-->", " ", text)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</(p|div|h1|h2|h3|h4|li|tr|section|article)>", "\n", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = (
        text.replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&quot;", '"')
        .replace("&#39;", "'")
    )
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def clip(text: str, n: int) -> str:
    t = (text or "").strip()
    if len(t) <= n:
        return t
    return t[: n - 1] + "…"


def event_key(name: str, when: str, source_key: str) -> str:
    base = f"{source_key}|{name.strip().lower()}|{when.strip().lower()}"
    digest = hashlib.md5(base.encode("utf-8")).hexdigest()[:12]
    return "live-" + digest


def parse_day(when: str) -> int:
    if not when:
        return -1
    m = re.search(
        r"(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})",
        when,
        re.IGNORECASE,
    )
    if not m:
        return -1
    try:
        month = MONTH_NUM[m.group(1).lower()]
        day = int(m.group(2))
        year = int(m.group(3))
        return datetime(year, month, day).weekday()
    except Exception:
        return -1


def guess_cats(blob: str) -> list[str]:
    low = (blob or "").lower()
    found: list[str] = []
    rules = [
        (
            "music",
            [
                "concert",
                "jazz",
                "symphony",
                "choir",
                "band",
                "piano",
                "orchestra",
                "folk",
                "song",
                "music",
                "vocal",
                "singer",
                "mariachi",
                "quartet",
                "recital",
                "tour",
                "dj",
                "indie",
                "rock",
                "hip hop",
                "rap",
            ],
        ),
        (
            "nightlife",
            [
                "club",
                "nightlife",
                "dance night",
                "late night",
                "disco",
                "amapiano",
                "afrobeats",
                "afterparty",
            ],
        ),
        (
            "comedy",
            ["comedy", "comedian", "stand-up", "standup", "improv", "open mic"],
        ),
        (
            "arts",
            ["dance", "theater", "theatre", "gallery", "opera", "ballet", "film", "art"],
        ),
        ("food", ["brunch", "tasting", "farmers", "market", "dinner", "food", "brewery", "wine"]),
        (
            "academic",
            ["lecture", "workshop", "seminar", "school day", "panel", "academic"],
        ),
        ("social", ["mixer", "festival", "fair", "party", "night", "social"]),
        ("community", ["library", "family", "kids", "community"]),
        ("outdoor", ["hike", "park", "river", "nature", "outdoor"]),
        ("networking", ["career", "networking", "meetup", "1 million cups"]),
        ("sports", ["football", "soccer", "game", "sports"]),
        ("civic", ["council", "vote", "democracy", "civic"]),
    ]
    for cat, keys in rules:
        if cat in CATEGORIES and any(k in low for k in keys) and cat not in found:
            found.append(cat)
    if not found:
        found.append("community")
    return found[:3]


def guess_price(blob: str) -> float:
    low = (blob or "").lower()
    if "free" in low or "pay what you wish" in low or "pwyw" in low:
        return 0.0
    m = re.search(r"\$(\d+(?:\.\d+)?)", blob or "")
    if m:
        try:
            return float(m.group(1))
        except Exception:
            return 0.0
    return 0.0


def _row(
    name: str,
    desc: str,
    when: str,
    venue: str,
    organizer: str,
    source_url: str,
) -> dict[str, Any]:
    name = unescape(name or "").strip()
    desc = unescape(desc or "").strip()
    venue = unescape(venue or "").strip()
    blob = f"{name} {desc} {when} {venue}"
    return {
        "name": clip(name, 90),
        "desc": clip(desc, 220),
        "when": clip(when, 80),
        "venue": venue,
        "organizer": organizer,
        "price": guess_price(blob),
        "categories": guess_cats(blob),
        "source_url": source_url,
        "day": parse_day(when),
    }


def parse_ums(text: str, page_url: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    date_re = re.compile(
        r"(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s+"
        r"(January|February|March|April|May|June|July|August|September|October|November|December)\s+"
        r"(\d{1,2}),\s+(\d{4})",
        re.IGNORECASE,
    )
    matches = list(date_re.finditer(text or ""))
    for i, m in enumerate(matches):
        when = m.group(0)
        start = matches[i - 1].end() if i > 0 else 0
        chunk = text[start : m.start()]
        lines = [ln.strip() for ln in chunk.split("\n") if ln.strip()]
        title = ""
        for cand in reversed(lines):
            cand = cand.lstrip("#").strip()
            low = cand.lower()
            if len(cand) < 4 or len(cand) > 100:
                continue
            if low in {"past events", "upcoming events", "get tickets", "learn more"}:
                continue
            if re.match(
                r"^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b",
                low,
            ):
                continue
            if re.match(
                r"^(january|february|march|april|may|june|july|august|september|october|november|december)\b",
                low,
            ):
                continue
            if cand.endswith(" -") or cand.endswith(" –"):
                continue
            title = cand
            break
        end = matches[i + 1].start() if i + 1 < len(matches) else min(len(text), m.end() + 400)
        after = text[m.end() : end]
        desc_lines = [ln.strip() for ln in after.split("\n") if ln.strip()]
        desc = desc_lines[0] if desc_lines else ""
        if title:
            venue = "Hill Auditorium" if "hill" in (title + desc).lower() else "UMS venue"
            out.append(_row(title, desc, when, venue, "UMS", page_url))
        if len(out) >= 24:
            break
    return out


def parse_observer(text: str, page_url: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    line_re = re.compile(
        r"^(.{8,140}?)\(([^)]{2,60})\),\s*(\d{1,2}\s+[A-Za-z]{3}\.?.*)$",
        re.MULTILINE,
    )
    for m in line_re.finditer(text or ""):
        name = m.group(1).strip(" \t-–—")
        venue = m.group(2).strip()
        when = m.group(3).strip()
        if len(name) < 4:
            continue
        out.append(
            _row(
                name,
                "Listed in the Ann Arbor Observer events calendar.",
                when,
                venue,
                venue,
                page_url,
            )
        )
        if len(out) >= 24:
            break
    return out


def parse_generic(text: str, page_url: str, source_name: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    date_re = re.compile(
        r"(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}",
        re.IGNORECASE,
    )
    for m in date_re.finditer(text or ""):
        when = m.group(0)
        window = text[max(0, m.start() - 180) : m.start()]
        lines = [ln.strip() for ln in window.split("\n") if ln.strip()]
        title = lines[-1] if lines else ""
        if len(title) < 5 or len(title) > 100:
            continue
        after = text[m.end() : m.end() + 220]
        desc = " ".join([ln.strip() for ln in after.split("\n") if ln.strip()][:2])
        out.append(_row(title, desc, when, "", source_name, page_url))
        if len(out) >= 20:
            break
    return out


def extract_for_feed(kind: str, text: str, url: str, name: str) -> list[dict[str, Any]]:
    if kind == "ums":
        return parse_ums(text, url)
    if kind == "observer":
        return parse_observer(text, url)
    if kind == "tribe":
        try:
            payload = json.loads(text)
        except Exception:
            return []
        return parse_tribe(payload, url, name)
    if kind == "eventbrite":
        return parse_eventbrite(text, url)
    return parse_generic(text, url, name)


def parse_tribe(payload: dict[str, Any], page_url: str, source_name: str) -> list[dict[str, Any]]:
    """WordPress Tribe Events REST JSON → RawEvent rows."""
    out: list[dict[str, Any]] = []
    events = payload.get("events") or []
    for e in events:
        if not isinstance(e, dict):
            continue
        title = unescape(str(e.get("title") or "")).strip()
        if len(title) < 3:
            continue
        when = str(e.get("start_date") or e.get("utc_start_date") or "")
        venue_obj = e.get("venue") or {}
        venue = ""
        if isinstance(venue_obj, dict):
            venue = str(venue_obj.get("venue") or venue_obj.get("name") or "")
        desc = strip_html(str(e.get("description") or e.get("excerpt") or ""))
        link = str(e.get("url") or page_url)
        out.append(_row(title, desc, when, venue, source_name, link))
        if len(out) >= 40:
            break
    return out


def parse_eventbrite(html: str, page_url: str) -> list[dict[str, Any]]:
    """Pull Eventbrite destination-page buckets from window.__SERVER_DATA__."""
    out: list[dict[str, Any]] = []
    marker = "window.__SERVER_DATA__"
    idx = (html or "").find(marker)
    if idx < 0:
        return out
    start = html.find("=", idx)
    if start < 0:
        return out
    start += 1
    while start < len(html) and html[start] in " \n\r\t":
        start += 1
    try:
        data, _ = json.JSONDecoder().raw_decode(html, start)
    except Exception:
        return out
    seen: set[str] = set()
    for bucket in data.get("buckets") or []:
        if not isinstance(bucket, dict):
            continue
        for e in bucket.get("events") or []:
            if not isinstance(e, dict):
                continue
            if e.get("is_online_event"):
                continue
            name = str(e.get("name") or "").strip()
            eid = str(e.get("id") or e.get("eid") or name)
            if len(name) < 3 or eid in seen:
                continue
            seen.add(eid)
            venue_obj = e.get("primary_venue") or {}
            venue = ""
            if isinstance(venue_obj, dict):
                venue = str(venue_obj.get("name") or "")
                addr = venue_obj.get("address") or {}
                if isinstance(addr, dict) and addr.get("city"):
                    city = str(addr.get("city") or "")
                    # Keep Ann Arbor / Ypsi metro; drop far-away spills.
                    if city and city.lower() not in {
                        "ann arbor",
                        "ypsilanti",
                        "saline",
                        "dexter",
                        "chelsea",
                        "milan",
                    }:
                        continue
            when = str(e.get("start_date") or "")
            st = str(e.get("start_time") or "")
            if when and st:
                when = f"{when} {st}"
            desc = str(e.get("summary") or e.get("full_description") or "")
            if desc and "<" in desc:
                desc = strip_html(desc)
            link = str(e.get("url") or page_url)
            org = "Eventbrite host"
            tags = e.get("tags") or []
            tag_blob = " ".join(
                str(t.get("display_name") or t.get("prefix") or "")
                for t in tags
                if isinstance(t, dict)
            )
            row = _row(name, desc or tag_blob, when, venue, org, link)
            # Prefer nightlife/music tags from Eventbrite buckets when present.
            bkey = str(bucket.get("key") or bucket.get("type") or "")
            if "nightlife" in bkey and "nightlife" not in row["categories"]:
                row["categories"] = ["nightlife"] + [
                    c for c in row["categories"] if c != "nightlife"
                ]
            elif "music" in bkey and "music" not in row["categories"]:
                row["categories"] = ["music"] + [
                    c for c in row["categories"] if c != "music"
                ]
            elif "food" in bkey and "food" not in row["categories"]:
                row["categories"] = ["food"] + [
                    c for c in row["categories"] if c != "food"
                ]
            out.append(row)
            if len(out) >= 50:
                return out
    return out
