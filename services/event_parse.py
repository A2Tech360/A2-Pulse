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


# Category keywords, matched as whole words (case-insensitive) against the event
# title. Substring matching mis-tagged "Shroom Tour" as music ("tour"), "party" as
# arts ("art"), "Gathering" as music ("rap") and a sailing club as nightlife ("club").
_CAT_RULES: list[tuple[str, list[str]]] = [
    ("music", [
        r"concerts?", r"jazz", r"symphon(?:y|ies)", r"orchestras?", r"choirs?", r"chorale",
        r"bands?", r"pianos?", r"pianists?", r"guitars?", r"guitarists?", r"violins?", r"cellos?",
        r"clarinets?", r"percussion", r"quartets?", r"recitals?", r"mariachi", r"sopranos?",
        r"mezzo-soprano", r"requiem", r"messiah", r"albums?", r"dj", r"reggaeton", r"hip[- ]hop",
        r"rap", r"rock", r"folk", r"bluegrass", r"blues", r"open stage", r"open mic",
        r"songwriters?", r"music", r"musical", r"ukulele", r"singers?", r"sing-?along",
        r"chimes?", r"live music", r"disko", r"disco",
    ]),
    ("nightlife", [
        r"night ?clubs?", r"club nights?", r"bar crawl", r"pub crawl", r"nightlife",
        r"dance party", r"disco", r"disko", r"late[- ]night", r"after ?party", r"lounge",
        r"latin fridays?",
    ]),
    ("comedy", [r"comedy", r"comedians?", r"stand-?up", r"improv", r"open mic"]),
    ("arts", [
        r"theaters?", r"theatres?", r"galler(?:y|ies)", r"exhibits?", r"exhibitions?",
        r"museums?", r"ballet", r"dance", r"opera", r"films?", r"screenings?", r"crafts?",
        r"photography", r"arts?", r"artists?", r"paintings?", r"sculptures?", r"poetry",
        r"premiere", r"planetarium",
    ]),
    ("food", [
        r"food", r"foodies", r"dinners?", r"brunch", r"breakfast", r"lunch", r"tastings?",
        r"wine", r"beer", r"brewer(?:y|ies)", r"markets?", r"pizza", r"cheese", r"eats",
    ]),
    ("academic", [
        r"lectures?", r"talks?", r"symposium", r"forum", r"class(?:es)?", r"workshops?",
        r"seminars?", r"panels?", r"conferences?", r"campus tours?", r"book launch", r"labs?",
    ]),
    ("social", [
        r"fest(?:ival)?s?", r"fairs?", r"part(?:y|ies)", r"socials?", r"open house",
        r"homecoming", r"mixers?", r"meet-?ups?", r"trivia", r"games?", r"game nights?",
        r"scavenger hunt", r"pregame", r"crawl", r"new friends", r"giveaway",
        r"magic: the gathering",
    ]),
    ("community", [
        r"librar(?:y|ies)", r"book sales?", r"seed swap", r"mending", r"volunteers?",
        r"fundraisers?", r"charit(?:y|ies)", r"open hours", r"famil(?:y|ies)", r"kids",
        r"community", r"support group", r"walk for", r"meals on wheels",
    ]),
    ("outdoor", [
        r"hikes?", r"hiking", r"walks?", r"parks?", r"nature", r"gardens?", r"farms?",
        r"orchards?", r"corn maze", r"trails?", r"rides?", r"river", r"lakes?", r"parkrun",
        r"wildflowers?", r"flowers?", r"shrooms?", r"mushrooms?", r"foraging", r"regatta",
        r"sailing", r"outdoors?",
    ]),
    ("networking", [
        r"careers?", r"networking", r"entrepreneurs?", r"founders?", r"co-founders?",
        r"1 million cups", r"startups?", r"professionals?", r"alumn(?:i|ae|us|a)",
    ]),
    ("sports", [
        r"football", r"soccer", r"basketball", r"hockey", r"volleyball", r"baseball",
        r"softball", r"tailgates?", r"regatta", r"races?", r"5k", r"10k", r"marathon",
        r"group runs?", r"parkrun", r"game day", r"sports",
    ]),
    ("civic", [
        r"city council", r"council (?:vote|meeting)", r"public comment", r"town hall",
        r"votes?", r"voting", r"elections?", r"ordinance", r"civic", r"racism", r"democracy",
    ]),
]
_CAT_RES: list[tuple[str, re.Pattern[str]]] = [
    (cat, re.compile(r"(?<![\w-])(?:" + "|".join(keys) + r")(?![\w-])", re.IGNORECASE))
    for cat, keys in _CAT_RULES
]
# Descriptions are noisy; only these strong phrases may add a category from them.
_DESC_RES: list[tuple[str, re.Pattern[str]]] = [
    ("comedy", re.compile(r"\b(?:improv|stand-?up|comedy show|comedian)\b", re.IGNORECASE)),
    ("music", re.compile(r"\b(?:live music|concert)\b", re.IGNORECASE)),
    ("arts", re.compile(r"\b(?:play|theater|theatre|dance performance|exhibition)\b", re.IGNORECASE)),
]
# Venues/presenters whose listings are one kind of thing.
_SOURCE_RULES: dict[str, dict[str, list[str]]] = {
    "the ark": {"always": ["music"], "allowed": ["music", "comedy", "nightlife"], "default": ["music"]},
    "university musical society": {"always": [], "allowed": ["music", "arts", "comedy"], "default": ["arts"]},
}


def split_host_title(title: str) -> tuple[str, str]:
    """Observer-style "Event: Host" titles -> (event, host). Other titles -> (title, "")."""
    t = (title or "").strip()
    if ": " not in t:
        return t, ""
    event, host = t.rsplit(": ", 1)
    event = event.strip().strip("\"“”'‘’ ")
    return event, host.strip()


def _match_cats(text: str) -> list[str]:
    return [cat for cat, rx in _CAT_RES if rx.search(text or "")]


def guess_cats(title: str, desc: str = "", source: str = "", fallback: list[str] | None = None) -> list[str]:
    """Categories for a listing: title first (event part of "Event: Host"), then strong
    description phrases, then the host part, then the source's default."""
    rules = _SOURCE_RULES.get((source or "").strip().lower(), {})
    allowed = rules.get("allowed") or []
    event, host = split_host_title(title)
    found = _match_cats(event)
    for cat, rx in _DESC_RES:
        if rx.search(desc or "") and cat not in found and (not found or cat == "comedy"):
            found.append(cat)
    if host:
        # The host names who performs or where ("Ann Arbor Symphony Orchestra",
        # "Nature Center"); only those kinds count, so "Kerrytown Market & Shops"
        # doesn't make a chime concert a food event.
        host_cats = _match_cats(host)
        for c in host_cats:
            if c not in found and (not found or c in ("music", "arts", "comedy", "outdoor")):
                found.append(c)
    if allowed:
        found = [c for c in found if c in allowed]
    for c in reversed(rules.get("always") or []):
        if c not in found:
            found.insert(0, c)
    if not found:
        found = list(fallback or rules.get("default") or ["community"])
    out: list[str] = []
    for c in found:
        if c in CATEGORIES and c not in out:
            out.append(c)
    return out[:3]


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
    source: str = "",
    fallback_cats: list[str] | None = None,
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
        "categories": guess_cats(name, desc, source, fallback_cats),
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
            out.append(_row(title, desc, when, venue, "UMS", page_url, "University Musical Society"))
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
        out.append(_row(title, desc, when, "", source_name, page_url, source_name))
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
        out.append(_row(title, desc, when, venue, source_name, link, source_name))
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
            # The destination-page bucket (music / nightlife / food) is only a fallback
            # when the title itself says nothing; it used to be forced onto every event.
            bkey = str(bucket.get("key") or bucket.get("type") or "").lower()
            bucket_cats = [c for c in ("nightlife", "music", "food") if c in bkey]
            row = _row(name, desc or tag_blob, when, venue, org, link, "Eventbrite Ann Arbor", bucket_cats or None)
            out.append(row)
            if len(out) >= 50:
                return out
    return out


def norm_title(title: str) -> str:
    """Title for duplicate checks: lowercase words only, no quotes/punctuation, no leading "the"."""
    t = unescape(title or "").lower()
    t = re.sub(r"[^a-z0-9]+", " ", t).strip()
    t = re.sub(r"^the ", "", t)
    return re.sub(r"\s+", " ", t)


def time_slot(when: str) -> str:
    """When text reduced to a comparable slot: "2026-10-10 19:30" for ISO date-times,
    the ISO date when only a date is known, else the lowercased text."""
    text = (when or "").strip()
    m = re.match(r"^(\d{4}-\d{2}-\d{2})(?:[T ](\d{1,2}):(\d{2}))?", text)
    if m:
        if m.group(2) is not None:
            return f"{m.group(1)} {int(m.group(2)):02d}:{m.group(3)}"
        return m.group(1)
    return re.sub(r"\s+", " ", text.lower())
