import urllib.request
import urllib.parse
import json
import os
import re
import ssl
import time
from datetime import datetime

# Known Ann Arbor venues (mirrors seed_data VENUES) so common buildings skip geocoding.
KNOWN_VENUES = {
    "hill auditorium": (42.2791, -83.7383, "825 N University Ave"),
    "michigan union": (42.2750, -83.7416, "530 S State St"),
    "pierpont commons": (42.2913, -83.7171, "2101 Bonisteel Blvd"),
    "the ark": (42.2793, -83.7485, "316 S Main St"),
    "larcom city hall": (42.2820, -83.7460, "301 E Huron St"),
}
SEED_VENUE_KEYS = {
    "hill auditorium": "v-hill", "michigan union": "v-union", "pierpont commons": "v-pier",
    "the ark": "v-ark", "larcom city hall": "v-cityhall",
}

# Geocoded building lookups persist across runs; Nominatim allows ~1 request/second.
GEOCACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".geocache.json")
MAX_NEW_LOOKUPS = 40
# Nominatim viewbox (lon1, lat1, lon2, lat2) around Ann Arbor.
A2_VIEWBOX = "-83.80,42.33,-83.65,42.22"

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
        print(f"[ingestion] could not save geocache: {ex}")


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
        for q in (f"{building}, University of Michigan, Ann Arbor, MI", f"{building}, Ann Arbor, MI"):
            if self.lookups > 0:
                time.sleep(1.1)
            self.lookups += 1
            try:
                hit = _nominatim(q)
            except Exception as ex:
                print(f"[ingestion] geocode failed for {building!r}: {ex}")
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


def _venue_key(venue):
    name = venue.strip().lower()
    if not name:
        return ""
    return SEED_VENUE_KEYS.get(name) or "v-live-" + re.sub(r"[^a-z0-9]+", "-", name).strip("-")


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
    return cats[:3] or ["academic"]


def _is_online(e, building):
    if building:
        return False
    loc = str(e.get("location_name", "")).lower()
    return not loc or any(h in loc for h in ONLINE_HINTS)


def fetch_happening_umich():
    # Optional offline feed (a saved day/json response) for demos and tests.
    fixture = os.environ.get("UM_EVENTS_FIXTURE", "")
    if fixture:
        with open(fixture) as f:
            return parse_happening_umich(json.load(f))
    try:
        url = "http://events.umich.edu/day/json?v=2"
        ctx = ssl._create_unverified_context()
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://events.umich.edu/",
            "Cookie": ""
        })
        with urllib.request.urlopen(req, timeout=10, context=ctx) as r:
            data = json.loads(r.read())
    except Exception as ex:
        print(f"[ingestion] happening@umich failed: {ex}")
        return []
    return parse_happening_umich(data)


def parse_happening_umich(data):
    geo = _Geocoder()
    events = []
    try:
        for e in data:
            building = (e.get("building_name") or "").strip()
            location = (e.get("location_name") or "").strip()
            room = (e.get("room") or "").strip()
            venue = building or location
            lat, lng, address = 0.0, 0.0, ""
            # Online or unplaceable events keep 0,0 so the map skips them instead of faking a pin.
            if not _is_online(e, building):
                hit = geo.resolve(venue)
                if hit:
                    lat, lng, address = hit[0], hit[1], hit[2]
            when, day = _fmt_when(e.get("date_start"), e.get("time_start"))
            events.append({
                "key": f"um-{e.get('id', '')}",
                "name": e.get("event_title", ""),
                "desc": (e.get("description", "") or "")[:200],
                "when": when,
                "day": day,
                "price": _parse_price(e.get("cost")),
                "lat": lat,
                "lng": lng,
                "venue": venue if lat != 0.0 else "",
                "venue_key": _venue_key(venue) if lat != 0.0 else "",
                "address": ", ".join(p for p in (room, location if location != venue else "", address) if p),
                "cats": _categories(e),
                "src": "src-um",
                "source_url": e.get("permalink", "https://events.umich.edu")
            })
    finally:
        geo.flush()
    placed = sum(1 for ev in events if ev["lat"] != 0.0)
    print(f"[ingestion] umich placed {placed}/{len(events)} events ({geo.lookups} new geocodes)")
    return events


def fetch_legistar():
    try:
        url = "https://webapi.legistar.com/v1/a2gov/events?$top=10&$orderby=EventDate+desc"
        with urllib.request.urlopen(url, timeout=5) as r:
            data = json.loads(r.read())
            if not isinstance(data, list):
                return []
            items = []
            for e in data:
                if not e:
                    continue
                when, day = _fmt_when((e.get("EventDate") or "")[:10], None)
                if e.get("EventTime"):
                    when = f"{when}, {e['EventTime']}"
                items.append({
                    "key": f"leg-{e.get('EventId', '')}",
                    "name": e.get("EventBodyName") or "City Council Meeting",
                    "desc": (e.get("EventComment") or "Ann Arbor City Council meeting.")[:200],
                    "when": when,
                    "day": day,
                    "price": 0.0,
                    "lat": 42.2820,
                    "lng": -83.7460,
                    "venue": "Larcom City Hall",
                    "venue_key": "v-cityhall",
                    "address": e.get("EventLocation") or "301 E Huron St",
                    "cats": ["civic", "community"],
                    "src": "src-leg",
                    "source_url": e.get("EventAgendaFile") or "https://a2gov.legistar.com/Calendar.aspx"
                })
            return items
    except Exception as ex:
        print(f"[ingestion] legistar failed: {ex}")
        return []


def fetch_all():
    results = []
    umich = fetch_happening_umich()
    print(f"[ingestion] umich returned: {len(umich)}")
    legistar = fetch_legistar()
    print(f"[ingestion] legistar returned: {len(legistar)}")
    results.extend(umich)
    results.extend(legistar)
    print(f"[ingestion] total: {len(results)}")
    return results
