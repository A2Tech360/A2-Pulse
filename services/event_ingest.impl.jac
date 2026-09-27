"""Implementation for live calendar fetch + graph upsert."""

import os;
import hashlib;
import from urllib.request { Request, urlopen }
import from datetime { datetime }
import from services.seed_data { CATEGORIES }
import from services.event_parse {
    strip_html,
    extract_for_feed,
    event_key,
    parse_day,
    guess_cats,
    guess_price,
    clip
}

glob INGEST_FEEDS: list[dict[str, any]] = [
    {
        "key": "src-ark-live",
        "name": "The Ark",
        "url": "https://theark.org/wp-json/tribe/events/v1/events?per_page=40",
        "kind": "tribe"
    },
    {
        "key": "src-observer-api",
        "name": "Ann Arbor Observer",
        "url": "https://annarborobserver.com/wp-json/tribe/events/v1/events?per_page=40",
        "kind": "tribe"
    },
    {
        "key": "src-eb-live",
        "name": "Eventbrite Ann Arbor",
        "url": "https://www.eventbrite.com/d/mi--ann-arbor/events/",
        "kind": "eventbrite"
    },
    {
        "key": "src-ums-live",
        "name": "University Musical Society",
        "url": "https://ums.org/events/",
        "kind": "ums"
    },
    {
        "key": "src-um-live",
        "name": "Happening @ Michigan",
        "url": "https://events.umich.edu/list",
        "kind": "generic"
    },
    {
        "key": "src-aadl-live",
        "name": "Ann Arbor District Library",
        "url": "https://www.aadl.org/events",
        "kind": "generic"
    },
    {
        "key": "src-marquee",
        "name": "Marquee Arts",
        "url": "https://marquee-arts.org/calendar/",
        "kind": "generic"
    }
];

glob VENUE_ALIASES: dict[str, str] = {
    "hill auditorium": "v-hill",
    "hill": "v-hill",
    "the ark": "v-ark",
    "ark": "v-ark",
    "blue llama": "v-llama",
    "blue llama jazz": "v-llama",
    "michigan union": "v-union",
    "union": "v-union",
    "pierpont": "v-pier",
    "pierpont commons": "v-pier",
    "aadl": "v-aadl",
    "downtown library": "v-aadl",
    "ann arbor district library": "v-aadl",
    "farmers market": "v-market",
    "gallup": "v-gallup",
    "city hall": "v-cityhall",
    "larcom": "v-cityhall",
    "power center": "v-power",
    "rackham": "v-rackham",
    "blind pig": "v-blindpig",
    "the blind pig": "v-blindpig",
    "michigan theater": "v-michtheater",
    "michigan theatre": "v-michtheater",
    "club above": "v-clubabove",
    "liminal lounge": "v-liminal",
    "a2 funhouse": "v-funhouse",
    "ann arbor funhouse": "v-funhouse",
    "literati": "v-literati",
    "ziggy": "v-blindpig",
    "ypsi freighthouse": "v-freighthouse",
    "marquee": "v-michtheater"
};

glob _last_sync_ts: float = 0.0;
glob SYNC_COOLDOWN_SEC: float = 180.0;

def _llm_ready -> bool {
    for k in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"] {
        v = os.environ.get(k, "");
        if v and len(v.strip()) > 8 {
            return True;
        }
    }
    return False;
}

def _hub -> Hub {
    seed_pulse();
    hubs = [root -->][?:Hub];
    return hubs[0];
}

def _http_get(url: str, accept: str = "") -> str {
    headers: dict[str, any] = {
        "User-Agent": "A2Pulse/1.0 (+https://github.com/muriloapparecido/A2-Pulse; event sync)",
        "Accept": (
            accept
            if accept
            else "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ),
        "Accept-Language": "en-US,en;q=0.8"
    };
    req = Request(url, headers=headers);
    resp = urlopen(req, timeout=18);
    raw = resp.read();
    resp.close();
    try {
        return raw.decode("utf-8");
    } except Exception {
        return raw.decode("latin-1", errors="ignore");
    }
}

def _ensure_categories(hub: Hub) {
    have: dict[str, bool] = {};
    for cat in [hub -->][?:Category] {
        have[cat.key] = True;
    }
    for c in CATEGORIES {
        ckey = "cat-" + c;
        if ckey in have {
            continue;
        }
        n = Category(
            key=ckey,
            name=c,
            kind="category",
            desc="Everything in Ann Arbor tagged " + c + "."
        );
        hub ++> n;
        have[ckey] = True;
    }
}

def _nearest_place(hub: Hub, lat: float, lng: float) -> Place | None {
    best: Place | None = None;
    best_d: float = 1.0e9;
    for p in [hub -->][?:Place] {
        dx: float = p.lat - lat;
        dy: float = p.lng - lng;
        if dx < 0.0 {
            dx = 0.0 - dx;
        }
        if dy < 0.0 {
            dy = 0.0 - dy;
        }
        d: float = dx + dy;
        if d < best_d {
            best_d = d;
            best = p;
        }
    }
    return best;
}

def _ensure_venue(hub: Hub, hint: str) -> Venue {
    found = _find_venue_key(hub, hint);
    if found {
        return found;
    }
    clean = hint.strip();
    if len(clean) < 2 {
        return _default_venue(hub);
    }
    # Cap dynamic venues so unknown strings don't explode the graph.
    live_count: int = 0;
    for v in [hub -->][?:Venue] {
        if v.key.startswith("v-live-") {
            live_count += 1;
        }
    }
    if live_count >= 40 {
        return _default_venue(hub);
    }
    key = "v-live-" + hashlib.md5(clean.lower().encode("utf-8")).hexdigest()[:10];
    for v in [hub -->][?:Venue] {
        if v.key == key {
            return v;
        }
    }
    # Pin near Main Street until we have geocodes; Near-edge still works for browse.
    lat: float = 42.2800;
    lng: float = -83.7480;
    address: str = clean + ", Ann Arbor";
    low = clean.lower();
    if "ypsi" in low {
        lat = 42.2411;
        lng = -83.6130;
        address = clean + ", Ypsilanti";
    }
    v = Venue(
        key=key,
        name=clip(clean, 60),
        kind="venue",
        address=address,
        lat=lat,
        lng=lng,
        desc="Live venue synced from calendars."
    );
    hub ++> v;
    place = _nearest_place(hub, lat, lng);
    if place {
        v +>:Near():+> place;
    }
    return v;
}

def _dict_to_raw(d: dict[str, any]) -> RawEvent {
    cats_any: any = d.get("categories", []);
    cats: list[str] = [];
    if cats_any {
        for c in (cats_any as list) {
            cs = str(c);
            if cs in CATEGORIES {
                cats.append(cs);
            }
        }
    }
    return RawEvent(
        name=str(d.get("name", "")),
        desc=str(d.get("desc", "")),
        when=str(d.get("when", "")),
        venue=str(d.get("venue", "")),
        organizer=str(d.get("organizer", "")),
        price=float(d.get("price", 0.0) if d.get("price", 0.0) is not None else 0.0),
        categories=cats,
        source_url=str(d.get("source_url", "")),
        day=int(d.get("day", -1) if d.get("day", -1) is not None else -1)
    );
}

def _ensure_source(hub: Hub, key: str, name: str, url: str) -> SourceDoc {
    for n in [hub -->][?:SourceDoc] {
        if n.key == key {
            return n;
        }
    }
    n = SourceDoc(
        key=key,
        name=name,
        kind="source",
        source_name=name,
        source_url=url,
        desc="Live feed synced into A2 Pulse."
    );
    hub ++> n;
    return n;
}

def _find_event(hub: Hub, key: str) -> Event | None {
    for n in [hub -->][?:Event] {
        if n.key == key {
            return n;
        }
    }
    return None;
}

def _find_venue_key(hub: Hub, hint: str) -> Venue | None {
    if not hint {
        return None;
    }
    low = hint.lower().strip();
    for alias in VENUE_ALIASES {
        vkey = VENUE_ALIASES[alias];
        if alias in low {
            for v in [hub -->][?:Venue] {
                if v.key == vkey {
                    return v;
                }
            }
        }
    }
    for v in [hub -->][?:Venue] {
        vn = v.name.lower();
        if vn and (vn in low or low in vn) {
            return v;
        }
    }
    return None;
}

def _ensure_organizer(hub: Hub, name: str, venue: Venue) -> Organizer {
    clean = name.strip() if name.strip() else "Community host";
    key = "org-live-" + hashlib.md5(clean.lower().encode("utf-8")).hexdigest()[:10];
    for o in [hub -->][?:Organizer] {
        if o.key == key or o.name.lower() == clean.lower() {
            return o;
        }
    }
    o = Organizer(
        key=key,
        name=clean,
        kind="organizer",
        sub="community",
        lat=venue.lat,
        lng=venue.lng,
        address=venue.address,
        desc=clean + " (synced)."
    );
    hub ++> o;
    o +>:HostedAt():+> venue;
    return o;
}

def _default_venue(hub: Hub) -> Venue {
    for v in [hub -->][?:Venue] {
        if v.key == "v-union" {
            return v;
        }
    }
    vs = [hub -->][?:Venue];
    return vs[0];
}

def _upsert_event(hub: Hub, raw: RawEvent, src: SourceDoc) -> str {
    name = clip(raw.name, 90);
    if len(name) < 3 {
        return "skip";
    }
    when = clip(raw.when, 80);
    key = event_key(name, when, src.key);
    day = raw.day if raw.day >= 0 else parse_day(when);
    if day < 0 {
        day = datetime.now().weekday();
    }
    cats = [c for c in raw.categories if c in CATEGORIES];
    if len(cats) == 0 {
        cats = guess_cats(name + " " + raw.desc + " " + when);
    }
    price = raw.price if raw.price >= 0.0 else guess_price(name + " " + raw.desc);
    ven = _ensure_venue(hub, raw.venue + " " + name + " " + raw.desc);
    org_name = raw.organizer if raw.organizer else src.name;
    org = _ensure_organizer(hub, org_name, ven);
    desc = clip(raw.desc if raw.desc else ("Listed on " + src.name + "."), 280);
    url = raw.source_url if raw.source_url else src.source_url;
    existing = _find_event(hub, key);
    if existing {
        existing.name = name;
        existing.desc = desc;
        existing.when = when if when else existing.when;
        existing.day = day;
        existing.price = price;
        existing.lat = ven.lat;
        existing.lng = ven.lng;
        existing.address = ven.address;
        existing.source_name = src.name;
        existing.source_url = url;
        existing.sub = "free" if price == 0.0 else "paid";
        return "updated";
    }
    ev = Event(
        key=key,
        name=name,
        kind="event",
        desc=desc,
        when=(when if when else "Upcoming"),
        day=day,
        price=price,
        lat=ven.lat,
        lng=ven.lng,
        address=ven.address,
        source_name=src.name,
        source_url=url,
        sub=("free" if price == 0.0 else "paid")
    );
    hub ++> ev;
    ev +>:HostedAt():+> ven;
    ev +>:OrganizedBy():+> org;
    ev +>:SourcedFrom():+> src;
    for c in cats {
        ckey = "cat-" + c;
        for cat in [hub -->][?:Category] {
            if cat.key == ckey {
                ev +>:TaggedAs():+> cat;
            }
        }
    }
    return "created";
}

def _collect_raws(kind: str, text: str, url: str, name: str) -> list[RawEvent] {
    rows = extract_for_feed(kind, text, url, name);
    raws: list[RawEvent] = [];
    for d in rows {
        raws.append(_dict_to_raw(d));
    }
    # Structured feeds already return solid rows — skip LLM (HTML/JSON noise).
    if kind == "tribe" or kind == "eventbrite" {
        return raws;
    }
    if _llm_ready() and len(text) > 200 {
        try {
            clipped = text[:14000];
            llm_rows = llm_extract_events(name, clipped, CATEGORIES);
            seen: list[str] = [r.name.lower() for r in raws];
            for row in llm_rows {
                nm = row.name.strip();
                if len(nm) < 3 {
                    continue;
                }
                if nm.lower() in seen {
                    continue;
                }
                if not row.source_url {
                    row.source_url = url;
                }
                if len(row.categories) == 0 {
                    row.categories = guess_cats(nm + " " + row.desc);
                }
                raws.append(row);
                seen.append(nm.lower());
                if len(raws) >= 30 {
                    break;
                }
            }
        } except Exception {
        }
    }
    return raws;
}

impl sync_online_events(force: bool) -> SyncReport {
    now = float(datetime.now().timestamp());
    rep = SyncReport(ok=True, message="");
    if not force and _last_sync_ts > 0.0 and (now - _last_sync_ts) < SYNC_COOLDOWN_SEC {
        rep.message = "Skipped - synced recently. Use Sync live events to force.";
        rep.ok = True;
        return rep;
    }
    hub = _hub();
    _ensure_categories(hub);
    for feed in INGEST_FEEDS {
        key = str(feed["key"]);
        name = str(feed["name"]);
        url = str(feed["url"]);
        kind = str(feed["kind"]);
        try {
            accept = "application/json" if kind == "tribe" else "";
            body = _http_get(url, accept);
            if len(body) < 40 {
                rep.errors.append(name + ": empty page (blocked or changed)");
                continue;
            }
            # Tribe/Eventbrite need raw body (JSON / __SERVER_DATA__).
            # HTML feeds get stripped text for title heuristics + LLM.
            parse_body = body;
            if kind != "tribe" and kind != "eventbrite" {
                parse_body = strip_html(body);
                if len(parse_body) < 80 {
                    rep.errors.append(name + ": empty page (blocked or changed)");
                    continue;
                }
            }
            low = parse_body.lower() if kind != "tribe" else body[:400].lower();
            if "security verification" in low or "enable javascript and cookies" in low {
                rep.errors.append(name + ": Cloudflare blocked automated fetch");
                continue;
            }
            src = _ensure_source(hub, key, name, url);
            raws = _collect_raws(kind, parse_body, url, name);
            rep.fetched = rep.fetched + len(raws);
            rep.sources.append(name);
            for raw in raws {
                status = _upsert_event(hub, raw, src);
                if status == "created" {
                    rep.created = rep.created + 1;
                } elif status == "updated" {
                    rep.updated = rep.updated + 1;
                } else {
                    rep.skipped = rep.skipped + 1;
                }
            }
        } except Exception as e {
            rep.errors.append(name + ": " + str(e));
        }
    }
    _last_sync_ts = float(datetime.now().timestamp());
    if rep.created + rep.updated == 0 and len(rep.errors) > 0 {
        rep.ok = False;
        rep.message = "Could not ingest live events from public calendars.";
    } else {
        rep.message = (
            f"Synced {rep.created} new / {rep.updated} updated from "
            + str(len(rep.sources))
            + " sources."
        );
    }
    return rep;
}

impl list_live_events(limit: int) -> list[dict[str, any]] {
    hub = _hub();
    out: list[dict[str, any]] = [];
    for n in [hub -->][?:Event] {
        if n.key.startswith("live-") {
            out.append(
                {
                    "key": n.key,
                    "name": n.name,
                    "when": n.when,
                    "source": n.source_name,
                    "url": n.source_url,
                    "price": n.price
                }
            );
        }
        if len(out) >= limit {
            break;
        }
    }
    return out;
}
