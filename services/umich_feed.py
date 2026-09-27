"""Happening @ Michigan (events.umich.edu) feed for services.event_ingest.

Fetches the week JSON, keeps upcoming events, and geocodes each building so
events land at real coordinates. Rows match event_ingest's raw-row shape plus
lat / lng / address / ext_id.
"""

import html
import urllib.request
import urllib.parse
import json
import os
import re
import ssl
import time
from datetime import date, datetime, timedelta
from typing import Any

# Known Ann Arbor venues (mirrors seed_data VENUES) so common buildings skip geocoding.
KNOWN_VENUES = {
    "hill auditorium": (42.2791, -83.7383, "825 N University Ave"),
    "michigan union": (42.2750, -83.7416, "530 S State St"),
    "pierpont commons": (42.2913, -83.7171, "2101 Bonisteel Blvd"),
    "the ark": (42.2793, -83.7485, "316 S Main St"),
    "larcom city hall": (42.2820, -83.7460, "301 E Huron St"),
}

# Geocoded building lookups persist across runs; Nominatim allows ~1 request/second.
GEOCACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".geocache.json")
MAX_NEW_LOOKUPS = 60
# Last good Happening @ Michigan response, used when the feed is blocked.
UM_FEED_CACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".um_feed_cache.json")
# Nominatim viewbox (lon1, lat1, lon2, lat2): Ann Arbor plus Ypsilanti.
A2_VIEWBOX = "-83.85,42.35,-83.55,42.18"
# Nominatim result types too coarse to pin an event on.
COARSE_TYPES = {"city", "town", "village", "administrative", "county", "state", "postcode", "suburb", "neighbourhood"}
# Feed placeholders that name no real building.
PLACEHOLDER_BUILDINGS = {"off campus location", "tba", "tbd", "various locations"}

ONLINE_HINTS = ("virtual", "zoom", "online", "livestream", "teams", "webinar")

# Keyword -> app category, matched against event_type, tags and title.
CATEGORY_KEYWORDS = [
    ("music", ("music", "concert", "recital", "carillon", "band", "orchestra", "choir", "jazz", "opera")),
    ("arts", ("exhibit", "art", "gallery", "performance", "theater", "theatre", "dance", "film", "screening", "museum")),
    ("sports", ("sport", "athletic", "volleyball", "tennis", "football", "basketball", "soccer", "hockey", "vs")),
    ("academic", ("lecture", "seminar", "colloquium", "symposium", "talk", "workshop", "class", "training", "conference", "info session", "information session")),
    ("networking", ("career", "job", "recruit", "networking", "employer", "internship", "meet & greet")),
    ("food", ("food", "lunch", "dinner", "breakfast", "snack", "pizza", "donut", "coffee")),
    ("social", ("social", "mixer", "party", "meeting", "club", "game night", "reception")),
    ("outdoor", ("outdoor", "hike", "garden", "arboretum", "nature")),
    ("community", ("community", "volunteer", "service", "fundraiser", "clinic", "wellness")),
]


def _load_geocache():
    try:
        with open(GEOCACHE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save_geocache(cache):
    try:
        with open(GEOCACHE_PATH, "w") as f:
            json.dump(cache, f, indent=1, sort_keys=True)
    except OSError as ex:
        print(f"[umich_feed] could not save geocache: {ex}")


def _nominatim(query):
    params = urllib.parse.urlencode({
        "q": query, "format": "json", "limit": 1,
        "viewbox": A2_VIEWBOX, "bounded": 1,
    })
    req = urllib.request.Request(
        "https://nominatim.openstreetmap.org/search?" + params,
        headers={"User-Agent": "A2-Pulse/0.1 (Ann Arbor local events map)"},
    )
    with urllib.request.urlopen(req, timeout=8) as r:
        rows = json.loads(r.read())
    if not rows:
        return None
    row = rows[0]
    if row.get("addresstype") in COARSE_TYPES or row.get("type") in COARSE_TYPES:
        return None
    return [float(row["lat"]), float(row["lon"]), row.get("display_name", "")]


class _Geocoder:
    """Resolves a building name to (lat, lng, address); None when unknown."""

    def __init__(self):
        self.cache = _load_geocache()
        self.lookups = 0
        self.dirty = False

    def resolve(self, building):
        name = building.strip().lower()
        if not name:
            return None
        if name in KNOWN_VENUES:
            return KNOWN_VENUES[name]
        if name in self.cache:
            hit = self.cache[name]
            return tuple(hit) if hit else None
        if self.lookups >= MAX_NEW_LOOKUPS:
            return None
        hit = None
        if re.search(r"\d|ann arbor|ypsilanti", name):
            # Already an address or names its city. Nominatim misses "Place, 201 S Division St, ...",
            # so also try from the house number on.
            street = re.search(r"\b\d+\s+\D.*", building)
            queries = (building, street.group()) if street and street.start() > 0 else (building,)
        else:
            queries = (f"{building}, University of Michigan, Ann Arbor, MI", f"{building}, Ann Arbor, MI")
        for q in queries:
            if self.lookups > 0:
                time.sleep(1.1)
            self.lookups += 1
            try:
                hit = _nominatim(q)
            except Exception as ex:
                print(f"[umich_feed] geocode failed for {building!r}: {ex}")
                return None  # don't cache transient failures
            if hit:
                break
        # Cache misses too, so unknown buildings aren't re-queried every run.
        self.cache[name] = hit
        self.dirty = True
        return tuple(hit) if hit else None

    def flush(self):
        if self.dirty:
            _save_geocache(self.cache)
            self.dirty = False


def _fmt_when(date_s, time_s):
    """('2026-09-28', '18:30:00') -> ('Mon Sep 28, 6:30 PM', 0). Day is Mon=0, like seed data."""
    try:
        d = datetime.strptime(date_s, "%Y-%m-%d")
    except (TypeError, ValueError):
        return (time_s or "", 0)
    label = d.strftime("%a %b ") + str(d.day)
    try:
        t = datetime.strptime(time_s, "%H:%M:%S")
    except (TypeError, ValueError):
        return (label, d.weekday())
    if t.hour == 0 and t.minute == 0:
        return (label + ", all day", d.weekday())
    clock = t.strftime("%I:%M %p").lstrip("0")
    return (f"{label}, {clock}", d.weekday())


def _venue_label(venue):
    """'Stamps Gallery, 201 S Division St, ...' -> 'Stamps Gallery'; keeps plain building names."""
    label = re.split(r"[,(]", venue, maxsplit=1)[0].strip()
    return label if label and not label[0].isdigit() else venue


def _parse_price(cost):
    m = re.search(r"\d+(?:\.\d+)?", str(cost or ""))
    return float(m.group()) if m else 0.0


def _categories(e):
    tags = e.get("tags") or []
    if isinstance(tags, dict):
        tags = list(tags.values())
    hay = " ".join([str(e.get("event_type", "")), " ".join(str(t) for t in tags), str(e.get("event_title", ""))]).lower()
    cats = [cat for cat, words in CATEGORY_KEYWORDS
            if any(re.search(r"\b" + re.escape(w.strip()) + r"s?\b", hay) for w in words)]
    return cats[:3] or ["community"]


def _is_online(e, building):
    if building:
        return False
    loc = str(e.get("location_name", "")).lower()
    return not loc or any(h in loc for h in ONLINE_HINTS)


UM_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://events.umich.edu/",
    "Cookie": ""
}


def _fetch_week(day: date) -> list[dict[str, Any]]:
    """The Sunday-Saturday week containing `day` (week/json alone is the current week only)."""
    url = f"http://events.umich.edu/week/{day.isoformat()}/json?v=2"
    req = urllib.request.Request(url, headers=UM_HEADERS)
    with urllib.request.urlopen(req, timeout=10, context=ssl._create_unverified_context()) as r:
        return json.loads(r.read())


def _load_cache() -> list[dict[str, Any]]:
    try:
        with open(UM_FEED_CACHE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def fetch_happening_umich() -> list[dict[str, Any]]:
    # Optional offline feed (a saved week/<date>/json response) for demos and tests.
    fixture = os.environ.get("UM_EVENTS_FIXTURE", "")
    if fixture:
        with open(fixture) as f:
            return parse_happening_umich(json.load(f))
    # This week plus next week, so ~7 days of upcoming events whatever the weekday.
    today = date.today()
    by_id: dict[str, dict[str, Any]] = {}
    fetched_any = False
    for day in (today, today + timedelta(days=7)):
        try:
            for e in _fetch_week(day):
                by_id[str(e.get("id", ""))] = e
            fetched_any = True
        except Exception as ex:
            # Cloudflare intermittently 403s this feed.
            print(f"[umich_feed] fetch of week {day} failed: {ex}")
    cached = _load_cache()
    if not fetched_any:
        if not cached:
            return []
        saved = datetime.fromtimestamp(os.path.getmtime(UM_FEED_CACHE_PATH)).strftime("%a %b %d %I:%M %p")
        print(f"[umich_feed] using cached feed from {saved}")
        return parse_happening_umich(cached)
    # A partial fetch keeps cached events for the week that was blocked.
    for e in cached:
        by_id.setdefault(str(e.get("id", "")), e)
    data = [e for e in by_id.values() if _end_date(e) >= today.isoformat()]
    try:
        with open(UM_FEED_CACHE_PATH, "w") as f:
            json.dump(data, f)
    except OSError as ex:
        print(f"[umich_feed] could not cache feed: {ex}")
    return parse_happening_umich(data)


def _end_date(e: dict[str, Any]) -> str:
    return e.get("date_end") or e.get("date_start") or ""


def parse_happening_umich(data: list[dict[str, Any]]) -> list[dict[str, Any]]:
    geo = _Geocoder()
    events = []
    today = datetime.now().strftime("%Y-%m-%d")
    skipped_past = 0
    try:
        for e in data:
            # Keep anything not yet over; multi-day events can start before today.
            if (_end_date(e) or today) < today:
                skipped_past += 1
                continue
            title = html.unescape(e.get("event_title", "") or "")
            if re.match(r"cancell?ed\b", title.strip(), re.I):
                continue
            building = html.unescape(e.get("building_name") or "").strip()
            if building.lower() in PLACEHOLDER_BUILDINGS:
                building = ""
            location = html.unescape(e.get("location_name") or "").strip()
            room = html.unescape(e.get("room") or "").strip()
            venue = building or location
            lat, lng, address = 0.0, 0.0, ""
            # Online or unplaceable events keep 0,0 so the map skips them instead of faking a pin.
            if not _is_online(e, building):
                hit = geo.resolve(venue)
                if hit:
                    lat, lng, address = hit[0], hit[1], hit[2]
            # An ongoing event is listed under today so the day filter finds it.
            when, day = _fmt_when(max(e.get("date_start") or today, today), e.get("time_start"))
            desc = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(e.get("description", "") or ""))).strip()
            events.append({
                "ext_id": str(e.get("id", "")),
                "name": title,
                "desc": desc[:280],
                "when": when,
                "day": day,
                "price": _parse_price(e.get("cost")),
                "lat": lat,
                "lng": lng,
                "venue": _venue_label(venue) if lat != 0.0 else "",
                "address": ", ".join(p for p in (room, location if location != venue else "", address) if p),
                "categories": _categories(e),
                "organizer": "",
                "source_url": e.get("permalink", "https://events.umich.edu")
            })
    finally:
        geo.flush()
    placed = sum(1 for ev in events if ev["lat"] != 0.0)
    print(f"[umich_feed] placed {placed}/{len(events)} upcoming events "
          f"({skipped_past} past skipped, {geo.lookups} new geocodes)")
    return events
