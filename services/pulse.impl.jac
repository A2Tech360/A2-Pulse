"""Bodies for pulse.jac: seeding, filters, traversal and ranking."""

import from services.event_dates { event_matches_date, parse_iso_date, label_for_iso }
import from services.road_snap { snap_path }

glob KIND_TOGGLES: list[str] = ["event", "organizer", "alert", "civic"];
# Run seed migrations once per process — rescanning every MapSnapshot after live ingest was ~60s+.
glob _SEED_MIGRATED: bool = False;
glob MAX_NODES: int = 90;
glob MAX_BROWSE_CHILDREN: int = 24;
# GenerateBrief: reverse TaggedAs over live ingest is huge (Map skipped it for ~40s).
# Cap edge loads so My Monday returns on a seeded+synced graph.
glob MAX_BRIEF_PER_INTEREST: int = 36;
glob MAX_BRIEF_NEAR_EVENTS: int = 24;
glob MAX_BRIEF_CANDIDATES: int = 80;
glob BROWSE_LENSES: list[dict] = [
    {
        "key": "lens-places",
        "name": "Places",
        "sub": "places",
        "desc": "Neighborhoods and corridors — drill into buildings, then events."
    },
    {
        "key": "lens-topics",
        "name": "Topics",
        "sub": "topics",
        "desc": "Music, nightlife, comedy, food — pick a topic, then a venue."
    },
    {
        "key": "lens-who",
        "name": "Hosts",
        "sub": "who",
        "desc": "Clubs, venues and orgs — see what they're hosting."
    },
    {
        "key": "lens-city",
        "name": "City",
        "sub": "city",
        "desc": "Road closures, detours and council items."
    }
];

glob POSTED_LENS: dict = {
    "key": "lens-community",
    "name": "Posted",
    "sub": "community"
};

impl _has_llm -> bool {
    return pulse_llm.llm_enabled();
}

impl _hub -> Hub {
    return _ensure_seed();
}

impl _migrate_seed_extras(hub: Hub) {
    # Existing persisted graphs miss nightlife venues/categories added later.
    have: dict[str, PulseNode] = {};
    for existing in [hub -->][?:PulseNode] {
        if existing.key {
            have[existing.key] = existing;
        }
    }
    n: PulseNode = PulseNode();
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
        have[ckey] = n;
    }
    for p in PLACES {
        if p["key"] in have {
            continue;
        }
        n = Place(
            key=p["key"],
            name=p["name"],
            kind="place",
            lat=p["lat"],
            lng=p["lng"],
            desc="A neighborhood or route waypoint."
        );
        hub ++> n;
        have[p["key"]] = n;
    }
    for v in VENUES {
        if v["key"] in have {
            continue;
        }
        n = Venue(
            key=v["key"],
            name=v["name"],
            kind="venue",
            address=v["address"],
            lat=v["lat"],
            lng=v["lng"],
            desc="Venue at " + str(v["address"]) + "."
        );
        hub ++> n;
        have[v["key"]] = n;
        pk = str(v["place"]);
        if pk in have {
            n +>:Near():+> have[pk];
        }
    }
    for o in ORGANIZERS {
        if o["key"] in have {
            continue;
        }
        vk = str(o["venue"]);
        if vk not in have {
            continue;
        }
        ven = have[vk];
        n = Organizer(
            key=o["key"],
            name=o["name"],
            kind="organizer",
            sub=o["org_type"],
            lat=ven.lat,
            lng=ven.lng,
            address=ven.address,
            desc=str(o["name"]) + " (" + str(o["org_type"]) + ")."
        );
        hub ++> n;
        have[o["key"]] = n;
        n +>:HostedAt():+> ven;
    }
    src_names: dict[str, str] = {};
    src_urls: dict[str, str] = {};
    for s in SOURCES {
        src_names[s["key"]] = s["name"];
        src_urls[s["key"]] = s["url"];
    }
    for e in EVENTS {
        if e["key"] in have {
            continue;
        }
        vk = str(e["venue"]);
        ok = str(e["org"]);
        sk = str(e["src"]);
        if vk not in have or ok not in have or sk not in have {
            continue;
        }
        ven = have[vk];
        n = Event(
            key=e["key"],
            name=e["name"],
            kind="event",
            desc=e["desc"],
            when=e["time"],
            day=e["day"],
            price=e["price"],
            lat=ven.lat,
            lng=ven.lng,
            address=ven.address,
            source_name=src_names[sk],
            source_url=src_urls[sk],
            sub=("free" if e["price"] == 0.0 else "paid")
        );
        hub ++> n;
        have[e["key"]] = n;
        n +>:HostedAt():+> ven;
        n +>:OrganizedBy():+> have[ok];
        for c in (e["cats"] as list[str]) {
            ckey = "cat-" + c;
            if ckey in have {
                n +>:TaggedAs():+> have[ckey];
            }
        }
        n +>:SourcedFrom():+> have[sk];
    }
    # Refresh closure / detour geometries so map lines follow streets.
    for a in ALERTS {
        ak = str(a["key"]);
        if ak not in have {
            continue;
        }
        alert_n = have[ak];
        if alert_n.kind == "alert" {
            alert_n.path = a["path"];
        }
    }
}

impl _ensure_seed -> Hub {
    hubs = [root -->][?:Hub];
    if len(hubs) > 0 {
        hub = hubs[0];
        if not _SEED_MIGRATED {
            _migrate_seed_extras(hub);
            _SEED_MIGRATED = True;
        }
        return hub;
    }
    hub = Hub();
    root ++> hub;
    by_key: dict[str, PulseNode] = {};
    src_names: dict[str, str] = {};
    src_urls: dict[str, str] = {};
    n: PulseNode = PulseNode();
    for s in SOURCES {
        n = SourceDoc(key=s["key"], name=s["name"], kind="source", source_name=s["name"], source_url=s["url"], desc="Where this fact came from. Cached fixture refreshed for the demo week.");
        hub ++> n;
        by_key[s["key"]] = n;
        src_names[s["key"]] = s["name"];
        src_urls[s["key"]] = s["url"];
    }
    for c in CATEGORIES {
        n = Category(key="cat-" + c, name=c, kind="category", desc="Everything in Ann Arbor tagged " + c + ".");
        hub ++> n;
        by_key["cat-" + c] = n;
    }
    for p in PLACES {
        n = Place(key=p["key"], name=p["name"], kind="place", lat=p["lat"], lng=p["lng"], desc="A neighborhood or route waypoint.");
        hub ++> n;
        by_key[p["key"]] = n;
    }
    for v in VENUES {
        n = Venue(key=v["key"], name=v["name"], kind="venue", address=v["address"], lat=v["lat"], lng=v["lng"], desc="Venue at " + str(v["address"]) + ".");
        hub ++> n;
        by_key[v["key"]] = n;
        n +>:Near():+> by_key[v["place"]];
    }
    for o in ORGANIZERS {
        ven = by_key[o["venue"]];
        n = Organizer(key=o["key"], name=o["name"], kind="organizer", sub=o["org_type"], lat=ven.lat, lng=ven.lng, address=ven.address, desc=str(o["name"]) + " (" + str(o["org_type"]) + ").");
        hub ++> n;
        by_key[o["key"]] = n;
        n +>:HostedAt():+> ven;
    }
    for e in EVENTS {
        ven = by_key[e["venue"]];
        n = Event(key=e["key"], name=e["name"], kind="event", desc=e["desc"], when=e["time"], day=e["day"], price=e["price"], lat=ven.lat, lng=ven.lng, address=ven.address, source_name=src_names[e["src"]], source_url=src_urls[e["src"]], sub=("free" if e["price"] == 0.0 else "paid"));
        hub ++> n;
        by_key[e["key"]] = n;
        n +>:HostedAt():+> ven;
        n +>:OrganizedBy():+> by_key[e["org"]];
        for c in (e["cats"] as list[str]) {
            n +>:TaggedAs():+> by_key["cat-" + c];
        }
        n +>:SourcedFrom():+> by_key[e["src"]];
    }
    for e in EVENTS {
        for r in (e["related"] as list[str]) {
            by_key[e["key"]] +>:Related():+> by_key[r];
        }
    }
    for a in ALERTS {
        n = Alert(key=a["key"], name=a["name"], kind="alert", sub=a["alert_type"], desc=a["desc"], when=a["when"], day=a["day"], lat=a["lat"], lng=a["lng"], source_name=src_names[a["src"]], source_url=src_urls[a["src"]], path=a["path"]);
        hub ++> n;
        by_key[a["key"]] = n;
        n +>:OrganizedBy():+> by_key[a["org"]];
        for c in (a["cats"] as list[str]) {
            n +>:TaggedAs():+> by_key["cat-" + c];
        }
        for p in (a["places"] as list[str]) {
            n +>:AffectsRoute():+> by_key[p];
        }
        n +>:SourcedFrom():+> by_key[a["src"]];
    }
    for c in CIVIC {
        n = CivicItem(key=c["key"], name=c["name"], kind="civic", sub="council", desc=c["desc"], when=c["when"], day=c["day"], lat=c["lat"], lng=c["lng"], source_name=src_names[c["src"]], source_url=src_urls[c["src"]]);
        hub ++> n;
        by_key[c["key"]] = n;
        n +>:OrganizedBy():+> by_key[c["org"]];
        for cat in (c["cats"] as list[str]) {
            n +>:TaggedAs():+> by_key["cat-" + cat];
        }
        for p in (c["places"] as list[str]) {
            n +>:AffectsRoute():+> by_key[p];
        }
        n +>:SourcedFrom():+> by_key[c["src"]];
    }
    for pr in PERSONAS {
        prof = UserProfile(persona=pr["persona"], name=pr["name"], commute=pr["commute"], weights={});
        root ++> prof;
        prof +>:LivesAt():+> by_key[pr["home"]];
        for p in (pr["via"] as list[str]) {
            prof +>:CommutesVia():+> by_key[p];
        }
        for c in (pr["interests"] as list[str]) {
            prof +>:InterestedIn():+> by_key["cat-" + c];
        }
        for o in (pr["follows"] as list[str]) {
            prof +>:Follows():+> by_key[o];
        }
    }
    _SEED_MIGRATED = True;
    return hub;
}

impl _miles(lat1: float, lng1: float, lat2: float, lng2: float) -> float {
    r = 3958.8;
    p1 = math.radians(lat1);
    p2 = math.radians(lat2);
    dp = math.radians(lat2 - lat1);
    dl = math.radians(lng2 - lng1);
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2;
    return 2 * r * math.asin(math.sqrt(a));
}

impl _cats_of(n: PulseNode) -> list[str] {
    return [c.name for c in [n ->:TaggedAs:->][?:Category]];
}

impl _venue_of(n: PulseNode) -> PulseNode | None {
    vs = [n ->:HostedAt:->][?:Venue];
    return vs[0] if len(vs) > 0 else None;
}

impl _is_neighbors_board(n: PulseNode) -> bool {
    # Synthetic organizer used to hang community posts — never show on the graph.
    return n.key == "o-community" or (
        n.kind == "organizer" and n.sub == "community" and n.name == "Neighbors"
    );
}

impl _org_matches_categories(n: PulseNode, cats: list[str]) -> bool {
    if len(cats) == 0 {
        return True;
    }
    for e in [n <-:OrganizedBy:<-][?:Event] {
        for c in _cats_of(e) {
            if c in cats {
                return True;
            }
        }
    }
    for a in [n <-:OrganizedBy:<-][?:Alert] {
        for c in _cats_of(a) {
            if c in cats {
                return True;
            }
        }
    }
    for c in [n <-:OrganizedBy:<-][?:CivicItem] {
        for cat in _cats_of(c) {
            if cat in cats {
                return True;
            }
        }
    }
    return False;
}

impl _pin_haystack(n: PulseNode) -> str {
    bits: str = (n.name or "") + " " + (n.desc or "") + " " + (n.address or "");
    ven = _venue_of(n);
    if ven is not None {
        bits = bits + " " + (ven.name or "") + " " + (ven.address or "");
    }
    return bits.lower();
}

impl _is_generic_city_address(addr: str) -> bool {
    a = (addr or "").strip().lower();
    return a == "" or a == "ann arbor" or a == "ann arbor, mi" or a == "ann arbor michigan";
}

impl _match_landmark(hay: str) -> dict | None {
    # Longer aliases first so "the diag" wins over bare fragments.
    best: dict | None = None;
    best_len: int = 0;
    for lm in LANDMARKS {
        for alias in (lm["aliases"] as list[str]) {
            a = alias.lower().strip();
            if not a {
                continue;
            }
            if a in hay and len(a) > best_len {
                best = lm;
                best_len = len(a);
            }
        }
    }
    if best is not None {
        return {
            "lat": float(best["lat"]),
            "lng": float(best["lng"]),
            "label": str(best["name"])
        };
    }
    for v in VENUES {
        name = str(v["name"]).lower();
        if name and name in hay {
            return {
                "lat": float(v["lat"]),
                "lng": float(v["lng"]),
                "label": str(v["name"])
            };
        }
    }
    for p in PLACES {
        name = str(p["name"]).lower();
        if name and name in hay {
            return {
                "lat": float(p["lat"]),
                "lng": float(p["lng"]),
                "label": str(p["name"])
            };
        }
    }
    return None;
}

impl _resolve_pin_coords(n: PulseNode) -> dict | None {
    # Prefer clear place language in the listing ("Burns Park", "the Diag")
    # over a loosely linked venue that may not match the title.
    text_hay = ((n.name or "") + " " + (n.desc or "") + " " + (n.address or "")).lower();
    hit = _match_landmark(text_hay);
    if hit is not None {
        return hit;
    }
    ven = _venue_of(n);
    if ven is not None and ven.lat != 0.0 and ven.lng != 0.0 {
        return {"lat": ven.lat, "lng": ven.lng, "label": ven.name or ven.address};
    }
    hay = _pin_haystack(n);
    hit2 = _match_landmark(hay);
    if hit2 is not None {
        return hit2;
    }
    # Keep seeded / ingested coords when they are real (not the community placeholder).
    if n.lat != 0.0 and n.lng != 0.0 {
        if n.posted_by and _is_generic_city_address(n.address) {
            return None;
        }
        return {
            "lat": n.lat,
            "lng": n.lng,
            "label": n.address if n.address else n.name
        };
    }
    return None;
}

impl _passes(n: PulseNode, spec: FilterSpec, clat: float, clng: float) -> bool {
    if n.kind == "source" or n.kind == "place" {
        return False;
    }
    if _is_neighbors_board(n) {
        return False;
    }
    if len(spec.kinds) > 0 and n.kind in KIND_TOGGLES and n.kind not in spec.kinds {
        return False;
    }
    if n.kind == "category" {
        return len(spec.categories) == 0 or n.name in spec.categories;
    }
    if n.kind == "organizer" {
        if len(spec.categories) > 0 and not _org_matches_categories(n, spec.categories) {
            return False;
        }
    }
    if n.kind in ["event", "alert", "civic"] {
        if len(spec.categories) > 0 {
            hit = False;
            for c in _cats_of(n) {
                if c in spec.categories { hit = True; }
            }
            if not hit { return False; }
        }
        # A concrete calendar day overrides the coarse time bucket.
        if spec.date {
            if not _node_on_date(n, spec.date) {
                return False;
            }
        } else {
            today = datetime.now().weekday();
            if spec.time == "today" and n.day != today { return False; }
            if spec.time == "weekend" and n.day < 4 { return False; }
        }
    }
    if n.kind == "event" {
        # Posted lane: only neighbor posts. Elsewhere: include them when community is on.
        if spec.community_only {
            if not n.posted_by {
                return False;
            }
        } elif n.posted_by and not spec.community {
            return False;
        }
        # Unknown prices (-1) match neither "Free" nor "Under $10".
        if spec.price == "free" and n.price != 0.0 { return False; }
        if spec.price == "under10" and (n.price < 0.0 or n.price >= 10.0) { return False; }
    }
    if spec.distance > 0.0 and n.lat != 0.0 {
        if _miles(clat, clng, n.lat, n.lng) > spec.distance { return False; }
    }
    return True;
}

impl _node_on_date(n: PulseNode, date_iso: str) -> bool {
    if not date_iso {
        return True;
    }
    if parse_iso_date(date_iso) is None {
        return True;
    }
    res: any = event_matches_date(n.when, n.day, date_iso);
    matched: bool = bool(res[0]);
    conf: str = str(res[1]);
    if conf == "exact" {
        return matched;
    }
    # Ambiguous when-text: ask the model when available, else weekday soft match.
    if conf == "none" and _has_llm() and len((n.when or "").strip()) >= 4 {
        try {
            return bool(llm_event_on_date(n.when, n.name, date_iso));
        } except Exception {
        }
    }
    return matched;
}

impl _has_dated_event(host: PulseNode, spec: FilterSpec, clat: float, clng: float) -> bool {
    # True if this venue/organizer/category connects to an event that passes date filters.
    if host.kind == "venue" {
        for e in [host <-:HostedAt:<-][?:Event] {
            if _passes(e, spec, clat, clng) {
                return True;
            }
        }
        return False;
    }
    if host.kind == "organizer" {
        for e in [host <-:OrganizedBy:<-][?:Event] {
            if _passes(e, spec, clat, clng) {
                return True;
            }
        }
        return False;
    }
    if host.kind == "category" {
        for e in [host <-:TaggedAs:<-][?:Event] {
            if _passes(e, spec, clat, clng) {
                return True;
            }
        }
        return False;
    }
    if host.kind == "place" {
        for v in [host <-:Near:<-][?:Venue] {
            if _has_dated_event(v, spec, clat, clng) {
                return True;
            }
        }
        return False;
    }
    return True;
}

impl _edge_label(a: PulseNode, b: PulseNode) -> str {
    ks = sorted([a.kind, b.kind]);
    pair = ks[0] + "-" + ks[1];
    labels: dict[str, str] = {
        "event-venue": "hosted at", "event-organizer": "organized by",
        "category-event": "tagged as", "alert-category": "tagged as",
        "category-civic": "tagged as", "alert-organizer": "issued by",
        "civic-organizer": "on agenda of", "organizer-venue": "based at",
        "event-event": "related", "place-venue": "near",
        "alert-place": "affects route", "civic-place": "affects"
    };
    return labels.get(pair, "linked");
}

impl _gnode(n: PulseNode, depth: int) -> GNode {
    return GNode(
        id=jid(n),
        key=n.key,
        name=n.name,
        kind=n.kind,
        sub=n.sub,
        depth=depth,
        expandable=_is_expandable(n.kind)
    );
}

impl _is_expandable(kind: str) -> bool {
    return kind not in ["event", "alert", "civic", "source"];
}

impl _radial_layout(nodes: list[GNode]) {
    cx = 600.0;
    cy = 400.0;
    rings: list[float] = [0.0, 190.0, 310.0, 390.0];
    by_depth: dict[int, list[GNode]] = {};
    for g in nodes {
        if g.depth not in by_depth {
            by_depth[g.depth] = [];
        }
        by_depth[g.depth].append(g);
    }
    for (dep, group) in by_depth.items() {
        cnt: float = float(max(len(group), 1));
        rad: float = rings[min(dep, 3)];
        offset: float = 0.4 * float(dep);
        two_pi: float = 6.283185307;
        i: int = 0;
        for g in group {
            if dep == 0 and len(group) == 1 {
                g.x = cx;
                g.y = cy;
            } elif dep == 0 {
                ang0: float = (two_pi * float(i)) / cnt - 1.2;
                g.x = round(cx + 120.0 * math.cos(ang0), 1);
                g.y = round(cy + 90.0 * math.sin(ang0), 1);
            } else {
                ang: float = offset + (two_pi * float(i)) / cnt;
                wobble: float = 14.0 * math.sin(float(i) * 1.7) if dep > 1 else 0.0;
                g.x = round(cx + (rad + wobble) * math.cos(ang) * 1.2, 1);
                g.y = round(cy + (rad + wobble) * math.sin(ang) * 0.95, 1);
            }
            i += 1;
        }
    }
}

impl _browse_child_nodes(
    focus_key: str, spec: FilterSpec, clat: float, clng: float
) -> list[PulseNode] {
    hub = _hub();
    out: list[PulseNode] = [];
    seen: list[str] = [];

    if focus_key == "lens-places" {
        for n in [hub -->][?:Place] {
            if spec.date and not _has_dated_event(n, spec, clat, clng) {
                continue;
            }
            k = n.key if n.key else jid(n);
            if k not in seen {
                seen.append(k);
                out.append(n);
            }
        }
        return out;
    }
    if focus_key == "lens-topics" {
        for n in [hub -->][?:Category] {
            if len(spec.categories) > 0 and n.name not in spec.categories {
                continue;
            }
            if spec.date and not _has_dated_event(n, spec, clat, clng) {
                continue;
            }
            k = n.key if n.key else jid(n);
            if k not in seen {
                seen.append(k);
                out.append(n);
            }
        }
        return out;
    }
    if focus_key == "lens-who" {
        for n in [hub -->][?:Organizer] {
            if len(out) >= MAX_BROWSE_CHILDREN {
                break;
            }
            if _is_neighbors_board(n) {
                continue;
            }
            if spec.date and not _has_dated_event(n, spec, clat, clng) {
                continue;
            }
            k = n.key if n.key else jid(n);
            if k not in seen {
                seen.append(k);
                out.append(n);
            }
        }
        return out;
    }
    if focus_key == "lens-city" {
        for n in [hub -->][?:Alert] {
            if len(out) >= MAX_BROWSE_CHILDREN {
                break;
            }
            if not _passes(n, spec, clat, clng) {
                continue;
            }
            k = n.key if n.key else jid(n);
            if k not in seen {
                seen.append(k);
                out.append(n);
            }
        }
        for n in [hub -->][?:CivicItem] {
            if len(out) >= MAX_BROWSE_CHILDREN {
                break;
            }
            if not _passes(n, spec, clat, clng) {
                continue;
            }
            k = n.key if n.key else jid(n);
            if k not in seen {
                seen.append(k);
                out.append(n);
            }
        }
        return out;
    }
    if focus_key == "lens-community" {
        # Posted tab: only topics that already have neighbor posts.
        for n in [hub -->][?:Category] {
            has_post = False;
            for e in [n <-:TaggedAs:<-][?:Event] {
                if e.posted_by and _passes(e, spec, clat, clng) {
                    has_post = True;
                    break;
                }
            }
            if not has_post {
                continue;
            }
            k = n.key if n.key else jid(n);
            if k not in seen {
                seen.append(k);
                out.append(n);
            }
        }
        return out;
    }

    focus = _find_key(focus_key);
    if focus is None {
        return out;
    }

    if focus.kind == "place" {
        for v in [focus <-:Near:<-][?:Venue] {
            if spec.date and not _has_dated_event(v, spec, clat, clng) {
                continue;
            }
            k = v.key if v.key else jid(v);
            if k not in seen {
                seen.append(k);
                out.append(v);
            }
        }
        return out;
    }
    if focus.kind == "venue" {
        for e in [focus <-:HostedAt:<-][?:Event] {
            if len(out) >= MAX_BROWSE_CHILDREN {
                break;
            }
            if not _passes(e, spec, clat, clng) {
                continue;
            }
            k = e.key if e.key else jid(e);
            if k not in seen {
                seen.append(k);
                out.append(e);
            }
        }
        return out;
    }
    if focus.kind == "category" {
        for e in [focus <-:TaggedAs:<-][?:Event] {
            if not _passes(e, spec, clat, clng) {
                continue;
            }
            if spec.community_only {
                # Posted topics: events hang directly on the category node.
                k = e.key if e.key else jid(e);
                if k not in seen {
                    seen.append(k);
                    out.append(e);
                }
                continue;
            }
            ven = _venue_of(e);
            if ven is not None {
                k = ven.key if ven.key else jid(ven);
                if k not in seen {
                    seen.append(k);
                    out.append(ven);
                }
            }
        }
        if len(out) == 0 and not spec.community_only {
            for e in [focus <-:TaggedAs:<-][?:Event] {
                if not _passes(e, spec, clat, clng) {
                    continue;
                }
                k = e.key if e.key else jid(e);
                if k not in seen {
                    seen.append(k);
                    out.append(e);
                }
            }
            for a in [focus <-:TaggedAs:<-][?:Alert] {
                if not _passes(a, spec, clat, clng) {
                    continue;
                }
                k = a.key if a.key else jid(a);
                if k not in seen {
                    seen.append(k);
                    out.append(a);
                }
            }
            for c in [focus <-:TaggedAs:<-][?:CivicItem] {
                if not _passes(c, spec, clat, clng) {
                    continue;
                }
                k = c.key if c.key else jid(c);
                if k not in seen {
                    seen.append(k);
                    out.append(c);
                }
            }
        }
        return out;
    }
    if focus.kind == "organizer" {
        if _is_neighbors_board(focus) {
            return out;
        }
        for e in [focus <-:OrganizedBy:<-][?:Event] {
            if not _passes(e, spec, clat, clng) {
                continue;
            }
            k = e.key if e.key else jid(e);
            if k not in seen {
                seen.append(k);
                out.append(e);
            }
        }
        for a in [focus <-:OrganizedBy:<-][?:Alert] {
            if not _passes(a, spec, clat, clng) {
                continue;
            }
            k = a.key if a.key else jid(a);
            if k not in seen {
                seen.append(k);
                out.append(a);
            }
        }
        for c in [focus <-:OrganizedBy:<-][?:CivicItem] {
            if not _passes(c, spec, clat, clng) {
                continue;
            }
            k = c.key if c.key else jid(c);
            if k not in seen {
                seen.append(k);
                out.append(c);
            }
        }
        return out;
    }
    if focus.kind in ["event", "alert", "civic"] {
        nbrs = [focus -->][?:PulseNode] + [focus <--][?:PulseNode];
        for nb in nbrs {
            if nb.kind == "source" or _is_neighbors_board(nb) {
                continue;
            }
            if nb.kind in ["event", "alert", "civic"] and not _passes(nb, spec, clat, clng) {
                continue;
            }
            k = nb.key if nb.key else jid(nb);
            if k not in seen {
                seen.append(k);
                out.append(nb);
            }
        }
    }
    return out;
}

impl _find_key(key: str) -> PulseNode | None {
    hub = _hub();
    for n in [hub -->][?:PulseNode] {
        if n.key == key or jid(n) == key {
            return n;
        }
    }
    return None;
}

impl _action_for(n: PulseNode, reasons: list[str], commute: str) -> str {
    when_txt = friendly_when(n.when);
    if commute == "bus" {
        return _bus_action_for(n, reasons);
    }
    if n.kind == "alert" {
        if n.sub == "detour" {
            return "Check TheRide trip planner and give yourself 10 extra minutes.";
        }
        if commute == "car" {
            return "Shift deliveries and parking outside " + when_txt + ".";
        }
        if commute == "bike" {
            return "Leave 10 minutes early or take the Fuller Rd path instead.";
        }
        return "Plan around it: " + when_txt + ".";
    }
    if n.kind == "civic" {
        return "Sign up for public comment or email Council: " + when_txt + ".";
    }
    if n.price < 0.0 {
        return "Check the listing for tickets, then save it for " + when_txt + ".";    # price unknown
    }
    if n.price == 0.0 {
        return "Free. Save it to your calendar for " + when_txt + ".";
    }
    return "RSVP and grab a ticket ($" + str(int(n.price)) + ") for " + when_txt + ".";
}

# Bus riders: closures and detours change where the bus goes, not just traffic.
impl _bus_action_for(n: PulseNode, reasons: list[str]) -> str {
    when_txt = friendly_when(n.when);
    # Kept short: to-dos are read aloud and the whole brief must stay near one minute.
    near_home = len([r for r in reasons if r.startswith("Near your home")]) > 0;
    if n.kind == "alert" {
        if n.sub == "detour" {
            return "Your bus is detouring (" + when_txt + "). Check TheRide's live map and allow 15 extra minutes.";
        }
        if near_home {
            return "Stops near home may move (" + when_txt + "). Check TheRide alerts and allow 10 extra minutes.";
        }
        return "Your bus may detour around it (" + when_txt + "). Check TheRide alerts before you leave.";
    }
    if n.kind == "civic" {
        return "Sign up for public comment or email Council: " + when_txt + ".";
    }
    if n.price < 0.0 {
        return "Check the listing for tickets, then plan the bus for " + when_txt + ".";    # price unknown
    }
    if n.price == 0.0 {
        return "Free. Save it for " + when_txt + " and check the bus times.";
    }
    return "RSVP and grab a ticket ($" + str(int(n.price)) + ") for " + when_txt + ".";
}

impl _heuristic_filters(text: str, prior: FilterSpec) -> FilterSpec {
    t = text.lower();
    spec = FilterSpec(query=text, categories=list(prior.categories), kinds=list(prior.kinds), price=prior.price, time=prior.time, date=prior.date, community=prior.community, community_only=prior.community_only, distance=prior.distance);
    if "reset" in t or "start over" in t or "clear" in t {
        spec = FilterSpec(query=text);
    }
    words: dict[str, list[str]] = {
        "music": ["music", "jazz", "concert", "band", "show", "folk", "symphony"],
        "food": ["food", "eat", "pizza", "brunch", "coffee", "dinner", "cheese", "market"],
        "sports": ["sport", "soccer", "game", "run"],
        "academic": ["lecture", "talk", "learn", "study", "maker"],
        "social": ["social", "meet people", "meeting people", "friends", "hang out"],
        "arts": ["art", "gallery", "theater"],
        "community": ["community", "neighbor"],
        "outdoor": ["outdoor", "hike", "park", "outside", "river"],
        "civic": ["council", "vote", "civic", "city hall", "ordinance"],
        "networking": ["career", "network", "job", "intern", "mixer"]
    };
    added: list[str] = [];
    for (cat, keys) in words.items() {
        for k in keys {
            if k in t and cat not in spec.categories and cat not in added {
                added.append(cat);
            }
        }
    }
    spec.categories = spec.categories + added;
    if "free" in t { spec.price = "free"; }
    elif "cheap" in t or "under $10" in t or "under 10" in t { spec.price = "under10"; }
    if "saturday" in t or "sunday" in t or "weekend" in t or "friday" in t { spec.time = "weekend"; }
    elif "tonight" in t or "today" in t {
        spec.time = "today";
        spec.date = datetime.now().date().isoformat();
    }
    elif "tomorrow" in t {
        spec.date = (datetime.now().date() + timedelta(days=1)).isoformat();
        spec.time = "week";
    }
    elif "this week" in t { spec.time = "week"; }
    if "near campus" in t or "nearby" in t or "walk" in t or "near me" in t { spec.distance = 1.0; }
    new_kinds: list[str] = [];
    if "closure" in t or "detour" in t or "road" in t or "bus" in t { new_kinds.append("alert"); }
    if "council" in t or "vote" in t or "civic" in t { new_kinds.append("civic"); }
    if "club" in t or "org" in t { new_kinds.append("organizer"); }
    if "event" in t or len(added) > 0 and len(new_kinds) == 0 { new_kinds.append("event"); }
    if len(new_kinds) > 0 {
        merged = list(spec.kinds);
        for k in new_kinds {
            if k not in merged { merged.append(k); }
        }
        spec.kinds = merged;
    }
    bits: list[str] = [];
    if spec.price == "free" { bits.append("free"); }
    if len(spec.categories) > 0 { bits.append(", ".join(spec.categories)); }
    if spec.time == "weekend" { bits.append("this weekend"); }
    elif spec.time == "today" { bits.append("today"); }
    if spec.distance > 0.0 { bits.append("within " + str(spec.distance) + " mi of campus"); }
    spec.reply = "Showing " + (" / ".join(bits) if len(bits) > 0 else "everything this week") + ".";
    return spec;
}

# ---------------------------------------------------------------- EgoSnapshot
impl EgoSnapshot.start {
    _ensure_seed();
    center = _find_key(self.center_key);
    if center is None {
        return;
    }
    self.depth_of[jid(center)] = 0;
    self.out_nodes.append(_gnode(center, 0));
    visit center;
}

impl EgoSnapshot.expand {
    my_id = jid(here);
    depth = self.depth_of.get(my_id, 0);
    if depth >= self.hops {
        return;
    }
    spec = FilterSpec(categories=self.categories, kinds=self.kinds, price=self.price, time=self.time, date=self.date, community=self.community, community_only=self.community_only, distance=self.distance);
    nbrs = [here -->][?:PulseNode] + [here <--][?:PulseNode];
    fresh: list[PulseNode] = [];
    for nb in nbrs {
        if _is_neighbors_board(nb) {
            continue;
        }
        nid = jid(nb);
        if nid not in self.depth_of {
            if len(self.out_nodes) >= MAX_NODES { continue; }
            if not _passes(nb, spec, self.clat, self.clng) { continue; }
            self.depth_of[nid] = depth + 1;
            self.out_nodes.append(_gnode(nb, depth + 1));
            fresh.append(nb);
        }
        ek = my_id + "|" + nid if my_id < nid else nid + "|" + my_id;
        if ek not in self.edge_seen {
            self.edge_seen.append(ek);
            self.out_edges.append(GEdge(source=my_id, target=nid, label=_edge_label(here, nb)));
        }
    }
    if len(fresh) > 0 {
        visit fresh;
    }
}

impl EgoSnapshot.finish {
    # Radial layout on a 1200 x 800 canvas: center slightly right, one ring per hop.
    cx = 760.0;
    cy = 400.0;
    rings: list[float] = [0.0, 170.0, 300.0, 390.0];
    by_depth: dict[int, list[GNode]] = {};
    for g in self.out_nodes {
        if g.depth not in by_depth { by_depth[g.depth] = []; }
        by_depth[g.depth].append(g);
    }
    for (dep, group) in by_depth.items() {
        cnt: float = float(max(len(group), 1));
        rad: float = rings[min(dep, 3)];
        offset: float = 0.35 * float(dep);
        two_pi: float = 6.283185307;
        i: int = 0;
        for g in group {
            if dep == 0 {
                g.x = cx;
                g.y = cy;
            } else {
                ang: float = offset + (two_pi * float(i)) / cnt;
                wobble: float = 18.0 * math.sin(float(i) * 1.7) if dep > 1 else 0.0;
                g.x = round(cx + (rad + wobble) * math.cos(ang) * 1.35, 1);
                g.y = round(cy + (rad + wobble) * math.sin(ang) * 0.95, 1);
            }
            i += 1;
        }
    }
    report Snapshot(center=self.center_key, nodes=self.out_nodes, edges=self.out_edges);
}

# ---------------------------------------------------------------- NetworkBrowse
impl NetworkBrowse.start {
    _ensure_seed();
    spec = FilterSpec(
        categories=self.categories,
        kinds=self.kinds,
        price=self.price,
        time=self.time,
        date=self.date,
        community=self.community,
        community_only=self.community_only,
        distance=self.distance
    );
    fk = self.focus_key if self.focus_key else "root";
    nodes: list[GNode] = [];
    edges: list[GEdge] = [];

    # Posted tab: only topic nodes (no Posted hub). User posts live under each topic.
    if fk == "lens-community" {
        kids = _browse_child_nodes(fk, spec, self.clat, self.clng);
        for ch in kids {
            nodes.append(_gnode(ch, 0));
        }
        report Snapshot(center=fk, nodes=nodes, edges=edges);
        return;
    }

    if fk == "root" {
        nodes.append(
            GNode(
                id="root",
                key="root",
                name="Ann Arbor",
                kind="lens",
                sub="root",
                depth=0,
                expandable=False
            )
        );
        for lens in BROWSE_LENSES {
            kid = str(lens["key"]);
            nodes.append(
                GNode(
                    id=kid,
                    key=kid,
                    name=str(lens["name"]),
                    kind="lens",
                    sub=str(lens["sub"]),
                    depth=1,
                    expandable=True
                )
            );
            edges.append(GEdge(source="root", target=kid, label="explore"));
        }
    } else {
        focus_g: GNode | None = None;
        for lens in BROWSE_LENSES {
            if str(lens["key"]) == fk {
                focus_g = GNode(
                    id=fk,
                    key=fk,
                    name=str(lens["name"]),
                    kind="lens",
                    sub=str(lens["sub"]),
                    depth=0,
                    expandable=True
                );
            }
        }
        if focus_g is None {
            pn = _find_key(fk);
            if pn is not None {
                focus_g = _gnode(pn, 0);
            }
        }
        if focus_g is None {
            nodes.append(
                GNode(
                    id="root",
                    key="root",
                    name="Ann Arbor",
                    kind="lens",
                    sub="root",
                    depth=0,
                    expandable=False
                )
            );
            for lens in BROWSE_LENSES {
                kid = str(lens["key"]);
                nodes.append(
                    GNode(
                        id=kid,
                        key=kid,
                        name=str(lens["name"]),
                        kind="lens",
                        sub=str(lens["sub"]),
                        depth=1,
                        expandable=True
                    )
                );
                edges.append(GEdge(source="root", target=kid, label="explore"));
            }
            fk = "root";
        } else {
            center_id = focus_g.id;
            nodes.append(focus_g);
            kids = _browse_child_nodes(fk, spec, self.clat, self.clng);
            for ch in kids {
                if len(nodes) >= MAX_NODES {
                    break;
                }
                g = _gnode(ch, 1);
                nodes.append(g);
                edge_lbl = "in";
                if focus_g.kind == "lens" {
                    edge_lbl = "explore";
                } elif focus_g.kind == "category" {
                    edge_lbl = "hosts";
                } elif focus_g.kind == "organizer" {
                    edge_lbl = "puts on";
                } elif focus_g.kind == "venue" {
                    edge_lbl = "hosted at";
                } elif focus_g.kind == "place" {
                    edge_lbl = "in";
                }
                edges.append(GEdge(source=center_id, target=g.id, label=edge_lbl));
            }
        }
    }

    _radial_layout(nodes);
    report Snapshot(center=fk, nodes=nodes, edges=edges);
}

# ---------------------------------------------------------------- MapSnapshot
impl MapSnapshot.start {
    hub = _ensure_seed();
    self.route_keys = [];
    if self.persona {
        for prof in [root -->][?:UserProfile] {
            if prof.persona != self.persona {
                continue;
            }
            for place in [prof ->:LivesAt:->][?:Place] {
                for n in [place <-:AffectsRoute:<-][?:PulseNode] {
                    if n.key and n.key not in self.route_keys {
                        self.route_keys.append(n.key);
                    }
                }
            }
            for place in [prof ->:CommutesVia:->][?:Place] {
                for n in [place <-:AffectsRoute:<-][?:PulseNode] {
                    if n.key and n.key not in self.route_keys {
                        self.route_keys.append(n.key);
                    }
                }
            }
        }
    }
    visit hub;
}

impl MapSnapshot.scan {
    # Category filter: reverse-walk from Category nodes so we don't visit every live event.
    if len(self.categories) > 0 {
        for cat in [here -->][?:Category] {
            if cat.name not in self.categories {
                continue;
            }
            if len(self.kinds) == 0 or "event" in self.kinds {
                visit [cat <-:TaggedAs:<-][?:Event];
            }
            if len(self.kinds) == 0 or "alert" in self.kinds {
                visit [cat <-:TaggedAs:<-][?:Alert];
            }
            if len(self.kinds) == 0 or "civic" in self.kinds {
                visit [cat <-:TaggedAs:<-][?:CivicItem];
            }
        }
        if len(self.kinds) == 0 or "organizer" in self.kinds {
            visit [here -->][?:Organizer];
        }
        return;
    }
    # Only walk map-relevant node types — visiting every PulseNode (venues, sources,
    # categories, places) plus schema-drift reloads made MapSnapshot take 60s+.
    visit [here -->][?:Event];
    visit [here -->][?:Alert];
    visit [here -->][?:CivicItem];
    if len(self.kinds) == 0 or "organizer" in self.kinds {
        visit [here -->][?:Organizer];
    }
}

impl MapSnapshot.pin {
    if here.kind not in KIND_TOGGLES {
        return;
    }
    # Upsert always copies venue coords onto the event. lat/lng == 0 means
    # online / unplaceable live listings — skip without edge walks.
    if here.kind == "event" and here.lat == 0.0 and here.lng == 0.0 {
        return;
    }
    on_route = here.key in self.route_keys;
    spec = FilterSpec(categories=self.categories, kinds=self.kinds, price=self.price, time=self.time, date=self.date, community=self.community, community_only=self.community_only, distance=self.distance);
    if on_route {
        # Always surface commute / home route impacts; still respect kind toggles.
        if len(self.kinds) > 0 and here.kind not in self.kinds {
            return;
        }
        if len(self.categories) > 0 and here.kind == "organizer" and not _org_matches_categories(here, self.categories) {
            return;
        }
        if len(self.categories) > 0 and here.kind in ["event", "alert", "civic"] {
            hit = False;
            for c in _cats_of(here) {
                if c in self.categories {
                    hit = True;
                }
            }
            if not hit {
                return;
            }
        }
    } elif not _passes(here, spec, self.clat, self.clng) {
        return;
    }
    # Prefer already-stored coords (ingest copies venue lat/lng). Skip landmark/venue
    # edge walks — those dominated MapSnapshot time after live sync.
    plat: float = here.lat;
    plng: float = here.lng;
    where_lbl: str = here.address if here.address else here.name;
    if plat == 0.0 and plng == 0.0 {
        # "coords", not "pin": a local named pin shadowed this ability (jac check E1001).
        coords: dict | None = _resolve_pin_coords(here);
        if coords is None {
            return;
        }
        plat = float(str(coords["lat"]));
        plng = float(str(coords["lng"]));
        where_lbl = str(coords["label"]) if coords["label"] else where_lbl;
    }
    if not on_route and spec.distance > 0.0 {
        if _miles(self.clat, self.clng, plat, plng) > spec.distance {
            return;
        }
    }
    # Stickers: when filtering by category, tags match the filter. Otherwise skip the
    # TaggedAs edge walk (408 live events × edge load was ~40s).
    pin_cats: list[str] = list(self.categories) if len(self.categories) > 0 else [];
    # cache_only: never block the map walker on Roads/OSRM HTTP.
    draw_path: list = here.path;
    if here.kind == "alert" and len(draw_path) > 1 {
        try {
            draw_path = snap_path(draw_path, True);
        } except Exception {
            draw_path = here.path;
        }
    }
    self.items.append(MapItem(
        id=jid(here), key=here.key, name=here.name, kind=here.kind, desc=here.desc,
        when=friendly_when(here.when), price=here.price, lat=plat, lng=plng,
        venue=where_lbl, categories=pin_cats,
        source_name=here.source_name, source_url=here.source_url, path=draw_path,
        dist=round(_miles(self.clat, self.clng, plat, plng), 2)
    ));
}

impl MapSnapshot.finish {
    report self.items;
}

# ---------------------------------------------------------------- SearchArchive
impl SearchArchive.start {
    hub = _ensure_seed();
    visit hub;
}

impl SearchArchive.scan {
    q = self.query.lower().strip();
    for n in [here -->][?:PulseNode] {
        if n.kind == "source" {
            continue;
        }
        hay = (n.name + " " + n.kind + " " + n.sub + " " + n.desc).lower();
        if q == "" or q in hay {
            self.found.append(_gnode(n, 0));
        }
    }
    order: dict[str, int] = {
        "place": 0,
        "category": 1,
        "venue": 2,
        "organizer": 3,
        "event": 4,
        "alert": 5,
        "civic": 6
    };
    self.found.sort(key=lambda (g: GNode) -> int { return order.get(g.kind, 9); });
    self.found = self.found[:14];
}

impl SearchArchive.finish {
    report self.found;
}

# ---------------------------------------------------------------- GetDossier
impl GetDossier.start {
    _ensure_seed();
    n = _find_key(self.node_id);
    if n is not None {
        visit n;
    }
}

impl GetDossier.read {
    ven = _venue_of(here);
    orgs = [here ->:OrganizedBy:->][?:Organizer];
    nbrs: list[PulseNode] = [here -->][?:PulseNode] + [here <--][?:PulseNode];
    links: list[GNode] = [];
    for x in nbrs {
        if x.kind == "source" or _is_neighbors_board(x) {
            continue;
        }
        links.append(_gnode(x, 1));
    }
    real_orgs: list[Organizer] = [o for o in orgs if not _is_neighbors_board(o) and not is_platform(o.name)];
    report Dossier(
        id=jid(here), key=here.key, name=here.name, kind=here.kind, desc=here.desc,
        when=friendly_when(here.when), venue=(ven.name if ven else ""), address=here.address,
        organizer=(
            here.posted_by
            if here.posted_by
            else (real_orgs[0].name if len(real_orgs) > 0 else "")
        ),
        posted_by=here.posted_by,
        price=here.price,
        categories=_cats_of(here), source_name=here.source_name, source_url=here.source_url,
        lat=here.lat, lng=here.lng, links=links[:12]
    );
    return;
}

# ---------------------------------------------------------------- GenerateBrief
impl GenerateBrief.start {
    _ensure_seed();
    visit [root -->][?:UserProfile][?persona == self.persona];
}

impl GenerateBrief.rank {
    t_start = time.perf_counter();
    trace = new_trace(here.persona);
    # Day index within the brief week (-2 Sat, -1 Sun: weekend briefs are for next week).
    today = brief_day_index(datetime.now());
    spec = FilterSpec(
        categories=self.categories,
        kinds=self.kinds,
        price=self.price,
        time=self.time,
        date=self.date,
        community=self.community,
        community_only=self.community_only,
        distance=self.distance
    );
    # Profile agent: read the persona node and its edges.
    homes = [here ->:LivesAt:->][?:Place];
    route = [here ->:CommutesVia:->][?:Place];
    interests = [here ->:InterestedIn:->][?:Category];
    follows = [here ->:Follows:->][?:Organizer];
    w = here.weights;
    t_profile = time.perf_counter();

    # Relevance agent: every point is recorded with the rule that earned it.
    scores: dict[str, float] = {};
    reasons: dict[str, list[str]] = {};
    nodes: dict[str, PulseNode] = {};
    rules: dict[str, list[dict]] = {};
    # Categories learned while scoring — avoid a second TaggedAs walk per candidate.
    known_cats: dict[str, list[str]] = {};
    # "Your week" is the brief's Monday through Sunday; anything dated outside it is skipped.
    monday = brief_monday(datetime.now());
    week_ok: dict[str, bool] = {};
    dropped: list[str] = [];

    def in_week(n: PulseNode) -> bool {
        if n.key not in week_ok {
            week_ok[n.key] = in_brief_week(n.when, n.on_date, n.key.startswith("live-"), monday);
            if not week_ok[n.key] {
                dropped.append(n.key);
            }
        }
        return week_ok[n.key];
    }

    def remember_cat(k: str, cat: str) -> None {
        if not cat {
            return;
        }
        if k not in known_cats {
            known_cats[k] = [];
        }
        if cat not in known_cats[k] {
            known_cats[k].append(cat);
        }
    }

    def bump(n: PulseNode, pts: float, why: str, rule: str) -> None {
        if not _passes(n, spec, self.clat, self.clng) {
            return;
        }
        k = n.key;
        if not in_week(n) {
            return;
        }
        if k not in scores {
            if len(scores) >= MAX_BRIEF_CANDIDATES {
                return;
            }
            scores[k] = 0.0;
            reasons[k] = [];
            nodes[k] = n;
            rules[k] = [];
        }
        scores[k] = scores[k] + pts;
        rules[k].append({"rule": rule, "points": round(pts, 3), "detail": why});
        if why not in reasons[k] { reasons[k].append(why); }
    }

    for p in homes + [r for r in route if r not in homes] {    # home counts once, not also as route
        is_home = p in homes;
        for x in [p <-:AffectsRoute:<-][?:PulseNode] {
            if x.kind == "alert" {
                bump(x, 3.0 if is_home else 2.6, ("Near your home in " if is_home else "On your " + here.commute + " route via ") + p.name, "home_alert" if is_home else "route_alert");
            } else {
                bump(x, 2.2, "Affects " + p.name + ", where you live or travel", "affects_place");
            }
        }
        near_n: int = 0;
        for v in [p <-:Near:<-][?:Venue] {
            if near_n >= MAX_BRIEF_NEAR_EVENTS {
                break;
            }
            for e in [v <-:HostedAt:<-][?:Event] {
                if near_n >= MAX_BRIEF_NEAR_EVENTS {
                    break;
                }
                near_n = near_n + 1;
                bump(e, 1.0, "Close by at " + v.name, "near_venue");
            }
        }
    }
    for c in interests {
        if len(scores) >= MAX_BRIEF_CANDIDATES {
            break;
        }
        seen: int = 0;
        for x in [c <-:TaggedAs:<-][?:PulseNode] {
            if seen >= MAX_BRIEF_PER_INTEREST or len(scores) >= MAX_BRIEF_CANDIDATES {
                break;
            }
            seen = seen + 1;
            bump(x, 1.5 * w.get(c.name, 1.0), "Matches your interest in " + c.name, "interest");
            if x.key in scores {
                remember_cat(x.key, c.name);
            }
        }
    }
    for o in follows {
        if is_platform(o.name) {
            continue;    # a ticketing/listing platform is not a host you follow
        }
        if len(scores) >= MAX_BRIEF_CANDIDATES {
            break;
        }
        for x in [o <-:OrganizedBy:<-][?:PulseNode] {
            if len(scores) >= MAX_BRIEF_CANDIDATES {
                break;
            }
            bump(x, 2.0, "From " + o.name + ", which you follow", "follows");
        }
    }
    for (k, n) in nodes.items() {
        # Use cats collected during interest scoring — _cats_of per node was another full edge walk.
        for c in (known_cats[k] if k in known_cats else []) {
            before = scores[k];
            scores[k] = scores[k] * w.get(c, 1.0);
            if scores[k] != before {
                rules[k].append({"rule": "weight", "points": round(scores[k] - before, 3), "detail": "x" + str(w.get(c, 1.0)) + " " + c + " weight from feedback"});
            }
        }
        delta = n.day - today;
        if delta >= 0 and delta <= 2 and n.kind in ["civic", "alert"] {
            scores[k] = scores[k] + 0.6;
            reasons[k].append("Coming up in the next " + str(delta + 1) + " days");
            rules[k].append({"rule": "soon", "points": 0.6, "detail": reasons[k][-1]});
        }
    }
    ranked_all = sorted(list(scores.keys()), key=lambda (k: str) -> float { return scores[k]; }, reverse=True);
    # One item per listing: the same title at the same place (address on the node —
    # skip HostedAt venue walks over every candidate).
    ranked: list[str] = [];
    seen_listing: list[str] = [];
    for k in ranked_all {
        place_lbl: str = nodes[k].address if nodes[k].address else "";
        lk = nodes[k].kind + "|" + norm_title(nodes[k].name) + "|" + place_lbl;
        if lk in seen_listing {
            continue;
        }
        seen_listing.append(lk);
        ranked.append(k);
    }
    t_score = time.perf_counter();

    # Action agent: a to-do for each of the top five.
    items: list[BriefItem] = [];
    for k in ranked[:5] {
        n = nodes[k];
        cats: list[str] = known_cats[k] if k in known_cats else [];
        if len(cats) == 0 {
            cats = _cats_of(n);
        }
        items.append(BriefItem(
            id=jid(n), key=n.key, name=n.name, kind=n.kind, when=friendly_when(n.when),
            why=". ".join(reasons[k][:2]) + ".",
            action=_action_for(n, reasons[k], here.commute),
            category=(cats[0] if len(cats) > 0 else n.kind),
            source_name=n.source_name, source_url=n.source_url,
            score=round(scores[k], 2)
        ));
    }
    home_name = homes[0].name if len(homes) > 0 else "Ann Arbor";
    interest_names = [c.name for c in interests];
    t_actions = time.perf_counter();

    trace["profile"] = {
        "name": here.name, "commute": here.commute,
        "home": [{"key": p.key, "name": p.name} for p in homes],
        "via": [{"key": p.key, "name": p.name} for p in route],
        "interests": interest_names,
        "follows": [{"key": o.key, "name": o.name} for o in follows],
        "weights": dict(w)
    };
    trace["scored"] = [
        {"rank": r + 1, "key": k, "name": nodes[k].name, "kind": nodes[k].kind, "score": round(scores[k], 3), "selected": r < 5, "by_rule": sum_by_rule(rules[k]), "rules": rules[k]}
        for (r, k) in enumerate(ranked)
    ];
    trace["actions"] = [{"key": it.key, "name": it.name, "action": it.action} for it in items];
    trace["llm"] = {"on": pulse_llm.llm_enabled(), "model": pulse_llm.llm_model_label()};
    # The "soon" rule and date wording depend on the weekday the brief ran.
    trace["today"] = {"date": datetime.now().date().isoformat(), "weekday": today};
    trace["week"] = {"monday": monday.isoformat(), "dropped_outside_week": len(dropped)};
    trace["duplicates_collapsed"] = len(ranked_all) - len(ranked);
    timing: dict[str, float] = {
        "profile_ms": ms(t_start, t_profile), "relevance_ms": ms(t_profile, t_score), "actions_ms": ms(t_score, t_actions)
    };

    if self.score_only {
        timing["total_ms"] = ms(t_start);
        trace["timing_ms"] = timing;
        report Brief(
            persona=here.persona, profile_name=here.name, home=home_name, commute=here.commute,
            interests=interest_names, items=items, trace=(trace if self.debug else {})
        );
        return;
    }

    # Editor stage: LLM (8s deadline) or template, always passed through speakable().
    editor_items: list[dict] = [
        {"name": it.name, "kind": it.kind, "when": it.when, "day": nodes[it.key].day, "reasons": strongest_first(reasons[it.key], rules[it.key]), "action": it.action}
        for it in items
    ];
    profile = here.name + ", lives in " + home_name + ", commutes by " + here.commute + ", into " + ", ".join(interest_names);
    edited = edit_brief(here.name.split(",")[0], profile, editor_items, self.use_ai);
    summary: str = edited["spoken"];
    used_ai: bool = edited["mode"] == "llm";
    t_editor = time.perf_counter();
    here.last_summary = summary;
    here.last_summary_at = datetime.now().isoformat(timespec="seconds");
    t_persist = time.perf_counter();

    trace["editor"] = {
        "mode": edited["mode"], "model": edited["model"], "input": edited["input"],
        "raw_llm": edited["raw_llm"], "error": edited["error"], "words": edited["words"]
    };
    trace["spoken"] = summary;
    timing["editor_ms"] = ms(t_actions, t_editor);
    timing["llm_ms"] = edited["llm_ms"];
    timing["template_ms"] = edited["template_ms"];
    timing["speakable_ms"] = edited["speakable_ms"];
    timing["persist_ms"] = ms(t_editor, t_persist);
    timing["total_ms"] = ms(t_start, t_persist);
    trace["timing_ms"] = timing;
    append_trace(trace);
    report Brief(
        persona=here.persona, profile_name=here.name, home=home_name, commute=here.commute,
        interests=interest_names, summary=summary, ai=used_ai, items=items,
        trace=(trace if self.debug else {})
    );
    return;
}

# ---------------------------------------------------------------- Feedback
impl Feedback.start {
    _ensure_seed();
    visit [root -->][?:UserProfile][?persona == self.persona];
}

impl Feedback.adjust {
    n = _find_key(self.item_key);
    if n is None {
        report {"ok": False};
        return;
    }
    w: dict[str, float] = dict(here.weights);
    for c in _cats_of(n) {
        cur = w.get(c, 1.0);
        nxt = cur + 0.35 if self.up else cur - 0.35;
        w[c] = max(0.2, min(3.0, round(nxt, 2)));
    }
    here.weights = w;
    report {"ok": True, "weights": w};
    return;
}

# ---------------------------------------------------------------- functions
impl update_custom_profile(home_key: str, commute: str, interests: list[str]) -> dict {
    _ensure_seed();
    profs = [root -->][?:UserProfile][?persona == "custom"];
    if len(profs) == 0 {
        return {"ok": False};
    }
    prof = profs[0];
    for e in [edge prof ->:InterestedIn:->] { del e; }
    for e in [edge prof ->:LivesAt:->] { del e; }
    for e in [edge prof ->:CommutesVia:->] { del e; }
    prof.commute = commute;
    home = _find_key(home_key);
    if home is not None {
        prof +>:LivesAt():+> home;
        prof +>:CommutesVia():+> home;
    }
    for c in interests {
        cat = _find_key("cat-" + c);
        if cat is not None {
            prof +>:InterestedIn():+> cat;
        }
    }
    return {"ok": True};
}

impl converse_query(text: str, prior: FilterSpec) -> FilterSpec {
    _ensure_seed();
    if _has_llm() {
        res = pulse_llm.call_with_deadline(llm_parse_filters, [text, prior, CATEGORIES]);
        spec: any = res["value"];
        if res["ok"] and isinstance(spec, FilterSpec) {
            spec.categories = [c for c in spec.categories if c in CATEGORIES];
            spec.kinds = [k for k in spec.kinds if k in KIND_TOGGLES];
            if spec.price not in ["any", "free", "under10"] { spec.price = "any"; }
            if spec.time not in ["today", "weekend", "week"] { spec.time = "week"; }
            # Safety net: where the LLM left a field at its prior value but plain
            # keywords clearly set it ("cheap", "saturday", "near campus",
            # "closure", "council"), keep the keyword result.
            kw = _heuristic_filters(text, prior);
            if spec.price == prior.price and kw.price != prior.price { spec.price = kw.price; }
            if spec.time == prior.time and kw.time != prior.time { spec.time = kw.time; }
            if spec.distance == prior.distance and kw.distance != prior.distance { spec.distance = kw.distance; }
            for k in ["alert", "civic"] {
                if k in kw.kinds and k not in prior.kinds and k not in spec.kinds {
                    spec.kinds = spec.kinds + [k];
                }
            }
            if "alert" in spec.kinds and len(spec.kinds) == 1 {
                # Alerts carry the community tag only; a topic filter would hide them.
                spec.categories = [c for c in spec.categories if c == "community"];
            }
            dval: any = spec.date;
            if not isinstance(dval, str) {
                spec.date = prior.date;
            }
            spec.community = prior.community;
            spec.query = text;
            if not spec.reply { spec.reply = "Updated your view."; }
            return spec;
        }
    }
    return _heuristic_filters(text, prior);
}

impl create_community_event(
    name: str,
    when: str,
    desc: str,
    category: str,
    posted_by: str,
    date: str,
    price: float
) -> dict {
    hub = _ensure_seed();
    title = name.strip();
    if not title {
        return {"ok": False, "error": "Give your event a name."};
    }
    when_txt = when.strip() if when else "TBA";
    who = posted_by.strip() if posted_by else "Neighbor";
    cat = category.strip().lower() if category else "social";
    if cat not in CATEGORIES {
        cat = "social";
    }
    day_n: int = datetime.now().weekday();
    if date {
        parsed = parse_iso_date(date);
        if parsed is not None {
            day_n = int(parsed.weekday());
            if not when.strip() {
                when_txt = label_for_iso(date);
            }
        }
    }
    slug_src = title.lower();
    slug = "";
    for ch in slug_src {
        if len(slug) >= 28 {
            break;
        }
        if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") {
            slug += ch;
        } elif ch == " " or ch == "-" {
            if len(slug) == 0 or slug[len(slug) - 1] != "-" {
                slug += "-";
            }
        }
    }
    if len(slug) > 0 and slug[len(slug) - 1] == "-" {
        slug = slug[: len(slug) - 1];
    }
    if not slug {
        slug = "meetup";
    }
    stamp = datetime.now().strftime("%H%M%S");
    ekey = f"user-evt-{slug}-{stamp}";
    body = desc.strip() if desc else ("Posted by " + who + ".");
    # Resolve clear landmarks (Diag, Burns Park, …); leave generic city pin otherwise.
    lat0: float = 0.0;
    lng0: float = 0.0;
    addr0: str = "Ann Arbor";
    hint = _match_landmark((title + " " + body).lower());
    if hint is not None {
        lat0 = float(hint["lat"]);
        lng0 = float(hint["lng"]);
        addr0 = str(hint["label"]);
    }
    evt = Event(
        key=ekey,
        name=title,
        kind="event",
        desc=body,
        when=when_txt,
        day=day_n,
        price=max(0.0, price),
        lat=lat0,
        lng=lng0,
        address=addr0,
        source_name="Posted",
        source_url="",
        posted_by=who,
        sub="community"
    );
    hub ++> evt;
    # Hang posts on their topic only — no synthetic "Neighbors" organizer hub.
    cat_n = _find_key("cat-" + cat);
    if cat_n is not None {
        evt +>:TaggedAs():+> cat_n;
    }
    try {
        grant(evt, level=ReadPerm);
    } except Exception {
    }
    return {
        "ok": True,
        "key": ekey,
        "id": jid(evt),
        "name": title,
        "category": cat
    };
}

impl list_personas() -> list[dict] {
    _ensure_seed();
    out: list[dict] = [];
    for p in [root -->][?:UserProfile] {
        if p.uid {
            continue;    # per-browser profiles are private
        }
        homes = [p ->:LivesAt:->][?:Place];
        out.append({
            "persona": p.persona, "name": p.name, "commute": p.commute,
            "home": (homes[0].name if len(homes) > 0 else ""),
            "home_key": (homes[0].key if len(homes) > 0 else ""),
            "interests": [c.name for c in [p ->:InterestedIn:->][?:Category]],
            "follows": [o.name for o in [p ->:Follows:->][?:Organizer]],
            "weights": p.weights
        });
    }
    return out;
}

# ---------------------------------------------------------------- per-browser profiles
impl _profile_for(uid: str) -> UserProfile | None {
    _ensure_seed();
    clean = uid.strip();
    if not clean or len(clean) > 64 or not clean.replace("-", "").isalnum() {
        return None;
    }
    pid = "u-" + clean;
    found = [root -->][?:UserProfile][?persona == pid];
    if len(found) > 0 {
        return found[0];
    }
    base: dict = {};
    for pr in PERSONAS {
        if pr["persona"] == "custom" {
            base = pr;
        }
    }
    prof = UserProfile(persona=pid, name="You", commute=base["commute"], weights={}, uid=clean, onboarded=False);
    root ++> prof;
    home = _find_key(base["home"]);
    if home is not None {
        prof +>:LivesAt():+> home;
    }
    for k in (base["via"] as list[str]) {
        pl = _find_key(k);
        if pl is not None {
            prof +>:CommutesVia():+> pl;
        }
    }
    for c in (base["interests"] as list[str]) {
        cat = _find_key("cat-" + c);
        if cat is not None {
            prof +>:InterestedIn():+> cat;
        }
    }
    for o in (base["follows"] as list[str]) {
        org = _find_key(o);
        if org is not None {
            prof +>:Follows():+> org;
        }
    }
    return prof;
}

impl _profile_dict(p: UserProfile) -> dict {
    homes = [p ->:LivesAt:->][?:Place];
    via = [p ->:CommutesVia:->][?:Place];
    return {
        "ok": True,
        "persona": p.persona,
        "uid": p.uid,
        "onboarded": p.onboarded,
        "name": p.name,
        "commute": p.commute,
        "home_key": (homes[0].key if len(homes) > 0 else ""),
        "home_name": (homes[0].name if len(homes) > 0 else ""),
        "via": [x.key for x in via],
        "via_names": [x.name for x in via],
        "interests": [c.name for c in [p ->:InterestedIn:->][?:Category]],
        "follows": [o.key for o in [p ->:Follows:->][?:Organizer]],
        "weights": p.weights,
        "home_label": p.home_label,
        "home_lat": p.home_lat,
        "home_lng": p.home_lng,
        "dest_key": p.dest_key,
        "dest_label": p.dest_label
    };
}

impl get_profile(uid: str) -> dict {
    prof = _profile_for(uid);
    if prof is None {
        return {"ok": False, "error": "Invalid profile id"};
    }
    return _profile_dict(prof);
}

glob ROUTE_BUFFER_MILES: float = 0.5;
glob COMMUTE_MODES: list[str] = ["walk", "bike", "car", "bus"];

impl _nearest_place_node(lat: float, lng: float) -> Place | None {
    best: Place | None = None;
    best_d = 1.0e9;
    for pl in [_hub() -->][?:Place] {
        d = _miles(lat, lng, pl.lat, pl.lng);
        if d < best_d {
            best_d = d;
            best = pl;
        }
    }
    return best;
}

impl nearest_place(lat: float, lng: float) -> dict {
    _ensure_seed();
    pl = _nearest_place_node(lat, lng);
    if pl is None {
        return {"key": "", "name": "", "dist": 0.0};
    }
    return {"key": pl.key, "name": pl.name, "dist": round(_miles(lat, lng, pl.lat, pl.lng), 2)};
}

impl route_places(home_key: str, dest_key: str) -> list[dict] {
    _ensure_seed();
    home = _find_key(home_key);
    dest = _find_key(dest_key);
    if home is None or home.kind != "place" {
        return [];
    }
    if dest is None or dest.kind != "place" or dest.key == home.key {
        return [{"key": home.key, "name": home.name}];
    }
    # Flat projection in miles around home; fine at city scale.
    kx = 69.17 * math.cos(math.radians(home.lat));
    ky = 69.0;
    bx = (dest.lng - home.lng) * kx;
    by = (dest.lat - home.lat) * ky;
    seg2 = bx * bx + by * by;
    hits: list[dict] = [];
    for pl in [_hub() -->][?:Place] {
        px = (pl.lng - home.lng) * kx;
        py = (pl.lat - home.lat) * ky;
        t = max(0.0, min(1.0, (px * bx + py * by) / seg2)) if seg2 > 0.0 else 0.0;
        dx = px - t * bx;
        dy = py - t * by;
        d = math.sqrt(dx * dx + dy * dy);
        if pl.key == home.key or pl.key == dest.key or d <= ROUTE_BUFFER_MILES {
            order = -1.0 if pl.key == home.key else (2.0 if pl.key == dest.key else t);
            hits.append({"key": pl.key, "name": pl.name, "t": order});
        }
    }
    hits.sort(key=lambda (h: dict) -> float { return h["t"]; });
    return [{"key": h["key"], "name": h["name"]} for h in hits];
}

impl onboarding_options() -> dict {
    hub = _ensure_seed();
    places = [{"key": pl.key, "name": pl.name, "lat": pl.lat, "lng": pl.lng} for pl in [hub -->][?:Place]];
    orgs: list[dict] = [];
    for o in [hub -->][?:Organizer] {
        if _is_neighbors_board(o) or is_platform(o.name) {
            continue;    # the neighbors board and ticketing/listing platforms aren't hosts to follow
        }
        cats: list[str] = [];
        for x in [o <-:OrganizedBy:<-][?:PulseNode] {
            for c in _cats_of(x) {
                if c not in cats {
                    cats.append(c);
                }
            }
        }
        orgs.append({"key": o.key, "name": o.name, "type": o.sub, "categories": cats});
    }
    return {"places": places, "categories": CATEGORIES, "organizers": orgs, "modes": COMMUTE_MODES};
}

impl save_profile(
    uid: str,
    home_key: str,
    home_lat: float = 0.0,
    home_lng: float = 0.0,
    home_label: str = "",
    commute: str = "walk",
    via: list[str] = [],
    dest_key: str = "",
    dest_label: str = "",
    interests: list[str] = [],
    follows: list[str] = []
) -> dict {
    prof = _profile_for(uid);
    if prof is None {
        return {"ok": False, "error": "Invalid profile id"};
    }
    home = _find_key(home_key) if home_key else None;
    if (home is None or home.kind != "place") and (home_lat != 0.0 or home_lng != 0.0) {
        home = _nearest_place_node(home_lat, home_lng);
    }
    if home is None or home.kind != "place" {
        return {"ok": False, "error": "Pick where you live"};
    }
    for e in [edge prof ->:LivesAt:->] { del e; }
    for e in [edge prof ->:CommutesVia:->] { del e; }
    for e in [edge prof ->:InterestedIn:->] { del e; }
    for e in [edge prof ->:Follows:->] { del e; }
    prof +>:LivesAt():+> home;
    route: list[str] = [k for k in via] if len(via) > 0 else [home.key];
    seen: list[str] = [];
    for k in route {
        pl = _find_key(k);
        if pl is not None and pl.kind == "place" and pl.key not in seen {
            prof +>:CommutesVia():+> pl;
            seen.append(pl.key);
        }
    }
    for c in interests {
        cat = _find_key("cat-" + c) if c in CATEGORIES else None;
        if cat is not None {
            prof +>:InterestedIn():+> cat;
        }
    }
    for k in follows {
        org = _find_key(k);
        if org is not None and org.kind == "organizer" and not is_platform(org.name) {
            prof +>:Follows():+> org;
        }
    }
    prof.commute = commute if commute in COMMUTE_MODES else "walk";
    prof.home_label = home_label[:200];
    prof.home_lat = home_lat;
    prof.home_lng = home_lng;
    prof.dest_key = dest_key if _find_key(dest_key) is not None else "";
    prof.dest_label = dest_label[:200];
    prof.onboarded = True;
    return _profile_dict(prof);
}

# Nominatim usage policy: max 1 request/second, identify the app, cache repeats.
glob NOMINATIM_UA: str = "A2Pulse/1.0 (Ann Arbor local graph demo; +https://github.com/muriloapparecido/A2-Pulse)";
glob NOMINATIM_MIN_GAP: float = 1.0;
glob _nominatim_lock: list[any] = [];    # created lazily: impl globs load before imports
glob _nominatim_last: list[float] = [0.0];
glob _nominatim_cache: dict[str, list[dict]] = {};

def _nominatim_search(query: str, limit: int) -> list[dict] {
    q = query.strip();
    if len(q) < 2 {
        return [];
    }
    cache_key = str(limit) + "|" + q.lower();
    if cache_key in _nominatim_cache {
        return _nominatim_cache[cache_key];
    }
    low = q.lower();
    if "ann arbor" not in low and "michigan" not in low and ", mi" not in low {
        q = q + ", Ann Arbor, MI";
    }
    params = {
        "format": "json",
        "addressdetails": "0",
        "limit": str(limit),
        "countrycodes": "us",
        "viewbox": "-83.90,42.36,-83.62,42.20",
        "bounded": "0",
        "q": q
    };
    url = "https://nominatim.openstreetmap.org/search?" + urlencode(params);
    req = Request(
        url,
        headers={
            "User-Agent": NOMINATIM_UA,
            "Accept": "application/json"
        }
    );
    try {
        if len(_nominatim_lock) == 0 {
            _nominatim_lock.append(threading.Lock());
        }
        lock: any = _nominatim_lock[0];
        lock.acquire();
        try {
            gap = NOMINATIM_MIN_GAP - (time.monotonic() - _nominatim_last[0]);
            if gap > 0.0 {
                time.sleep(gap);
            }
            _nominatim_last[0] = time.monotonic();
        } finally {
            lock.release();
        }
        resp = urlopen(req, timeout=6);
        raw = resp.read().decode("utf-8");
        resp.close();
        data = json.loads(raw);
        if isinstance(data, list) {
            if len(_nominatim_cache) > 300 {
                _nominatim_cache.clear();
            }
            _nominatim_cache[cache_key] = data;
            return data;
        }
    } except Exception {
        return [];
    }
    return [];
}

def _split_place_label(display: str) -> dict {
    parts = display.split(",");
    if len(parts) == 0 {
        return {"title": display, "sub": ""};
    }
    title = parts[0].strip();
    rest: list[str] = [];
    i = 1;
    while i < len(parts) and len(rest) < 3 {
        bit = parts[i].strip();
        if bit {
            rest.append(bit);
        }
        i += 1;
    }
    return {"title": title, "sub": ", ".join(rest)};
}

impl suggest_places(query: str) -> list[PlaceSuggestion] {
    rows = _nominatim_search(query, 3);
    out: list[PlaceSuggestion] = [];
    for row in rows {
        if len(out) >= 3 {
            break;
        }
        display = str(row["display_name"]) if "display_name" in row else "";
        if not display {
            continue;
        }
        bits = _split_place_label(display);
        pid = str(row["place_id"]) if "place_id" in row else str(len(out));
        lat_s = str(row["lat"]) if "lat" in row else "0";
        lon_s = str(row["lon"]) if "lon" in row else "0";
        out.append(
            PlaceSuggestion(
                id=pid,
                title=bits["title"],
                sub=bits["sub"],
                label=display,
                lat=float(lat_s),
                lng=float(lon_s)
            )
        );
    }
    return out;
}

impl geocode_address(query: str) -> PlaceSuggestion {
    rows = _nominatim_search(query, 1);
    if len(rows) == 0 {
        return PlaceSuggestion();
    }
    row = rows[0];
    display = str(row["display_name"]) if "display_name" in row else "";
    bits = _split_place_label(display);
    pid = str(row["place_id"]) if "place_id" in row else "";
    lat_s = str(row["lat"]) if "lat" in row else "0";
    lon_s = str(row["lon"]) if "lon" in row else "0";
    return PlaceSuggestion(
        id=pid,
        title=bits["title"],
        sub=bits["sub"],
        label=display,
        lat=float(lat_s),
        lng=float(lon_s)
    );
}

# ---------------------------------------------------------------- voice (ElevenLabs)
# Default voice "George" from the ElevenLabs library; override with ELEVENLABS_VOICE_ID.
glob TTS_DEFAULT_VOICE: str = "JBFqnCBsd6RMkjVDRZzb";
glob TTS_DEFAULT_MODEL: str = "eleven_flash_v2_5";
glob TTS_MAX_CHARS: int = 2500;
glob _tts_cache: dict[str, str] = {};
glob _voices_cache: list[dict] = [];
# When the key can't list voices (no voices_read), don't re-ask ElevenLabs on every
# page load (~3 s each); retry after VOICES_RETRY_SECS.
glob VOICES_RETRY_SECS: float = 600.0;
glob _voices_failed_at: list[float] = [0.0];

# Premade ElevenLabs voices, used when the key cannot list voices (no voices_read).
glob PREMADE_VOICES: list[dict] = [
    {"id": "JBFqnCBsd6RMkjVDRZzb", "name": "George", "desc": "Warm British narrator"},
    {"id": "nPczCjzI2devNBz1zQrb", "name": "Brian", "desc": "Deep, resonant American"},
    {"id": "onwK4e9ZLuTAKqWW03F9", "name": "Daniel", "desc": "Authoritative British newsreader"},
    {"id": "cjVigY5qzO86Huf0OWal", "name": "Eric", "desc": "Smooth, friendly American"},
    {"id": "TX3LPaxmHKxFdv7VOQHJ", "name": "Liam", "desc": "Energetic young American"},
    {"id": "IKne3meq5aSn9XLyUdCD", "name": "Charlie", "desc": "Casual Australian"},
    {"id": "SAz9YHcvj6GT2YYXdXww", "name": "River", "desc": "Relaxed, neutral"},
    {"id": "EXAVITQu4vr4xnSDxMaL", "name": "Sarah", "desc": "Soft, reassuring American"},
    {"id": "FGY2WhTYpPnrIDTdsKH5", "name": "Laura", "desc": "Upbeat American"},
    {"id": "cgSgspJ2msm6clMCkdW9", "name": "Jessica", "desc": "Bright, playful American"},
    {"id": "XrExE9yKIg1WjnnlVkGX", "name": "Matilda", "desc": "Warm, professional American"},
    {"id": "Xb7hH8MSUJpSbSDYk0k2", "name": "Alice", "desc": "Clear British presenter"},
    {"id": "XB0fDUnXU5powFXDhCwa", "name": "Charlotte", "desc": "Swedish-accented, calm"},
    {"id": "pFZP5JQG7iQjIQuC4Bku", "name": "Lily", "desc": "Velvety British"}
];

def _speak_error(code: str, message: str, retry_after: float = 0.0) -> dict {
    out: dict = {"audio": "", "error": message, "code": code};
    if retry_after > 0.0 {
        out["retry_after"] = retry_after;
    }
    return out;
}

impl speak_brief(persona: str = "", voice_id: str = "", profile_id: str = "", text: str = "") -> dict {
    # Async so the caller's IP can be read from the request on the event loop's
    # stack; the blocking work (graph lookup, TTS HTTP call) then runs off-loop.
    ip = client_ip();
    return await asyncio.to_thread(_speak_brief_for, persona, voice_id, profile_id, text, ip);
}

def _speak_brief_for(persona: str, voice_id: str, profile_id: str, text: str, ip: str) -> dict {
    if text {
        return _speak_error("text_not_accepted", "speak_brief only reads server-generated briefs; pass persona or profile_id");
    }
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip();
    if not key {
        return _speak_error("tts_unavailable", "ELEVENLABS_API_KEY is not set");
    }
    # Only server-generated briefs are spoken: find the profile node, never take text.
    _ensure_seed();
    matches: list[UserProfile] = [
        p for p in [root -->][?:UserProfile]
        if (profile_id and jid(p) == profile_id) or (not profile_id and persona and p.persona == persona)
    ];
    if len(matches) == 0 {
        return _speak_error("unknown_profile", "Unknown persona or profile id");
    }
    prof = matches[0];
    default_voice = os.environ.get("ELEVENLABS_VOICE_ID", "").strip() or TTS_DEFAULT_VOICE;
    voice = voice_id.strip() or default_voice;
    if not voice.isalnum() or len(voice) > 64 or (voice != default_voice and voice not in known_voice_ids(list_voices)) {
        return _speak_error("unknown_voice", "Unknown voice id");
    }
    retry_in = rate_check(["profile:" + jid(prof), "ip:" + ip], speak_limit(), speak_window_s());
    if retry_in > 0.0 {
        return _speak_error("rate_limited", f"Too many voice requests; try again in {int(retry_in) + 1}s", retry_in);
    }
    if not prof.last_summary.strip() {
        prof spawn GenerateBrief(persona=prof.persona, use_ai=True);
    }
    text = speakable(prof.last_summary)[:TTS_MAX_CHARS];
    if not text {
        return _speak_error("no_brief", "No brief to read");
    }
    model = os.environ.get("ELEVENLABS_MODEL", "").strip() or TTS_DEFAULT_MODEL;
    cache_key = model + "|" + voice + "|" + text;
    if cache_key in _tts_cache {
        return {"audio": _tts_cache[cache_key], "error": ""};
    }
    req = Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128",
        data=json.dumps({"text": text, "model_id": model}).encode("utf-8"),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
        method="POST"
    );
    try {
        resp: any = urlopen(req, timeout=60);
        mp3: bytes = resp.read();
        resp.close();
    } except urllib.error.HTTPError as e {
        detail = e.read().decode("utf-8", "replace")[:300];
        return _speak_error("tts_error", f"ElevenLabs {e.code}: {detail}");
    } except Exception as e {
        return _speak_error("tts_error", f"ElevenLabs request failed: {e}");
    }
    url = "data:audio/mpeg;base64," + base64.b64encode(mp3).decode("ascii");
    _tts_cache[cache_key] = url;
    return {"audio": url, "error": ""};
}

impl list_voices -> dict {
    if _voices_cache {
        return {"voices": _voices_cache, "source": "account"};
    }
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip();
    recently_failed = _voices_failed_at[0] > 0.0 and time.monotonic() - _voices_failed_at[0] < VOICES_RETRY_SECS;
    if key and not recently_failed {
        req = Request(
            "https://api.elevenlabs.io/v2/voices?page_size=100",
            headers={"xi-api-key": key, "Accept": "application/json"}
        );
        try {
            resp: any = urlopen(req, timeout=6);
            data: any = json.loads(resp.read().decode("utf-8"));
            resp.close();
            out: list[dict] = [];
            raw: list[any] = data.get("voices", []);
            for v in raw {
                labels: any = v.get("labels") or {};
                bits = [str(labels.get(k, "")) for k in ["descriptive", "accent", "gender"] if labels.get(k)];
                out.append({"id": v["voice_id"], "name": v["name"], "desc": ", ".join(bits) or str(v.get("category", ""))});
            }
            if out {
                _voices_cache.extend(out);
                return {"voices": out, "source": "account"};
            }
        } except Exception {
            # Typically 401 missing_permissions (voices_read); fall through to premade.
            _voices_failed_at[0] = time.monotonic();
        }
    }
    return {"voices": PREMADE_VOICES, "source": "premade"};
}

def _escape_popup(s: str) -> str {
    t = s.replace("&", "&amp;");
    t = t.replace("<", "&lt;");
    t = t.replace(">", "&gt;");
    t = t.replace('"', "&quot;");
    return t;
}

def _heuristic_map_overview(n: PulseNode) -> MapOverview {
    tip = friendly_when(n.when) if n.when else "";
    if n.kind == "alert" and not tip {
        tip = "Check before you leave.";
    } elif n.kind == "event" and n.price == 0.0 and n.sub == "free" {
        tip = "Free — good drop-in.";
    } elif n.kind == "event" and n.price > 0.0 {
        tip = "Ticketed · about $" + str(int(n.price));
    }
    blurb = n.desc.strip() if n.desc else (
        n.name + " is on the Ann Arbor pulse as a " + n.kind + "."
    );
    if len(blurb) > 220 {
        blurb = blurb[:217] + "...";
    }
    return MapOverview(headline=n.name, blurb=blurb, tip=tip, ai=False);
}

impl map_pin_overview(node_id: str) -> MapOverview {
    _ensure_seed();
    n = _find_key(node_id);
    if n is None {
        return MapOverview(
            headline="Unknown pin",
            blurb="We could not find that marker in the archive.",
            tip="",
            ai=False
        );
    }
    cats = ", ".join(_cats_of(n));
    ven = _venue_of(n);
    venue_name = ven.name if ven else "";
    if _has_llm() {
        try {
            ov = llm_map_overview(
                n.name, n.kind, n.when, venue_name, n.desc, cats
            );
            if not ov.headline {
                ov.headline = n.name;
            }
            if not ov.blurb {
                return _heuristic_map_overview(n);
            }
            ov.ai = True;
            return ov;
        } except Exception {
            return _heuristic_map_overview(n);
        }
    }
    return _heuristic_map_overview(n);
}

# ---------------------------------------------------------------- dossier images
glob _IMG_UA: str = "A2Pulse/1.0 (Ann Arbor local graph; educational demo)";

def _http_json(url: str, timeout: float = 8.0) -> dict {
    req = Request(url, headers={"User-Agent": _IMG_UA, "Accept": "application/json"});
    try {
        resp: any = urlopen(req, timeout=timeout);
        raw: bytes = resp.read();
        resp.close();
        parsed: any = json.loads(raw.decode("utf-8", "replace"));
        if isinstance(parsed, dict) {
            return parsed as dict;
        }
    } except Exception {
    }
    return {};
}

def _dedupe_images(imgs: list[DossierImage], limit: int = 4) -> list[DossierImage] {
    seen: dict[str, bool] = {};
    out: list[DossierImage] = [];
    for im in imgs {
        u = (im.url or "").strip();
        if not u or u in seen {
            continue;
        }
        if not (u.startswith("https://") or u.startswith("http://")) {
            continue;
        }
        seen[u] = True;
        out.append(im);
        if len(out) >= limit {
            break;
        }
    }
    return out;
}

def _wiki_images(query: str, limit: int = 3) -> list[DossierImage] {
    q = query.strip();
    if not q {
        return [];
    }
    url = "https://en.wikipedia.org/w/api.php?" + urlencode(
        {
            "action": "query",
            "format": "json",
            "generator": "search",
            "gsrsearch": q,
            "gsrlimit": str(limit + 2),
            "prop": "pageimages|pageterms",
            "piprop": "thumbnail",
            "pithumbsize": "900",
            "wbptterms": "description"
        }
    );
    data = _http_json(url);
    pages: any = {};
    try {
        pages = data["query"]["pages"];
    } except Exception {
        return [];
    }
    out: list[DossierImage] = [];
    try {
        for (pid, page) in pages.items() {
            th: any = None;
            try {
                th = page["thumbnail"];
            } except Exception {
                continue;
            }
            src = "";
            try {
                src = str(th["source"] or "");
            } except Exception {
                continue;
            }
            if not src {
                continue;
            }
            if "?" in src {
                src = src.split("?", 1)[0];
            }
            title: str = q;
            try {
                title = str(page["title"] or q);
            } except Exception {
            }
            # Drop fuzzy Wikipedia misses (query tokens must appear in the title).
            tokens: list[str] = [];
            for tok in q.replace(",", " ").split() {
                tl = tok.lower().strip();
                if len(tl) > 3 and tl not in ["ann", "arbor", "michigan", "with", "from", "club"] {
                    tokens.append(tl);
                }
            }
            title_l = title.lower();
            if len(tokens) > 0 {
                hit_tok = False;
                for tl in tokens {
                    if tl in title_l {
                        hit_tok = True;
                        break;
                    }
                }
                if not hit_tok {
                    continue;
                }
            }
            out.append(
                DossierImage(
                    url=src,
                    caption=title,
                    credit="Wikipedia / Wikimedia Commons",
                    source="wikipedia"
                )
            );
            if len(out) >= limit {
                break;
            }
        }
    } except Exception {
    }
    return out;
}

def _openverse_images(query: str, limit: int = 3) -> list[DossierImage] {
    q = query.strip();
    if not q {
        return [];
    }
    url = "https://api.openverse.org/v1/images/?" + urlencode(
        {"q": q, "page_size": str(limit + 1), "mature": "false"}
    );
    data = _http_json(url);
    rows: any = [];
    try {
        rows = data["results"];
    } except Exception {
        return [];
    }
    out: list[DossierImage] = [];
    try {
        for row in rows {
            src = "";
            try {
                src = str(row["url"] or "");
                if not src {
                    src = str(row["thumbnail"] or "");
                }
            } except Exception {
                continue;
            }
            if not src {
                continue;
            }
            title: str = q;
            creator: str = "";
            license: str = "CC";
            try {
                title = str(row["title"] or q);
            } except Exception {
            }
            # Soft preference: skip clearly off-city hits when query names Ann Arbor.
            q_l = q.lower();
            t_l = title.lower();
            if "ann arbor" in q_l and "lima" in t_l {
                continue;
            }
            try {
                creator = str(row["creator"] or "");
            } except Exception {
            }
            try {
                license = str(row["license"] or "CC");
            } except Exception {
            }
            credit = creator if creator else "Openverse";
            if license {
                credit = credit + " · " + license;
            }
            out.append(
                DossierImage(
                    url=src, caption=title, credit=credit, source="openverse"
                )
            );
            if len(out) >= limit {
                break;
            }
        }
    } except Exception {
    }
    return out;
}

def _places_photos(query: str, limit: int = 2) -> list[DossierImage] {
    key = os.environ.get("GOOGLE_MAPS_API_KEY", "").strip();
    q = query.strip();
    if not key or not q {
        return [];
    }
    find_url = (
        "https://maps.googleapis.com/maps/api/place/findplacefromtext/json?"
        + urlencode(
            {
                "input": q + " Ann Arbor",
                "inputtype": "textquery",
                "fields": "name,photos,formatted_address",
                "locationbias": "circle:12000@42.2808,-83.7430",
                "key": key
            }
        )
    );
    data = _http_json(find_url);
    out: list[DossierImage] = [];
    try {
        cands: any = data["candidates"];
        if len(cands) == 0 {
            return out;
        }
        place: any = cands[0];
        pname: str = q;
        try {
            pname = str(place["name"] or q);
        } except Exception {
        }
        photos: any = place["photos"];
        i = 0;
        for ph in photos {
            if i >= limit {
                break;
            }
            ref = "";
            try {
                ref = str(ph["photo_reference"] or "");
            } except Exception {
                continue;
            }
            if not ref {
                continue;
            }
            photo_url = (
                "https://maps.googleapis.com/maps/api/place/photo?"
                + urlencode(
                    {"maxwidth": "900", "photo_reference": ref, "key": key}
                )
            );
            out.append(
                DossierImage(
                    url=photo_url,
                    caption=pname,
                    credit="Google Places",
                    source="places"
                )
            );
            i += 1;
        }
    } except Exception {
    }
    return out;
}

impl search_public_images(query: str) -> list[DossierImage] {
    q = query.strip();
    if not q {
        return [];
    }
    hits: list[DossierImage] = [];
    # Prefer CC Openverse (often has venue photos), then Wikipedia, then Places.
    hits = hits + _openverse_images(q, 4);
    if len(hits) < 2 {
        hits = hits + _wiki_images(q, 3);
    }
    if len(hits) < 2 {
        hits = hits + _places_photos(q, 2);
    }
    return _dedupe_images(hits, 4);
}

def _heuristic_image_queries(
    name: str, kind: str, venue: str, organizer: str
) -> list[str] {
    qs: list[str] = [];
    def add(s: str) {
        t = s.strip();
        if not t {
            return;
        }
        low = t.lower();
        for existing in qs {
            if existing.lower() == low {
                return;
            }
        }
        qs.append(t);
    }
    if kind in ["venue", "organizer", "place"] {
        add(name + " Ann Arbor");
        add(name);
    } elif kind == "event" {
        if venue {
            add(venue + " Ann Arbor");
        }
        if organizer {
            add(organizer + " Ann Arbor");
        }
        add(name + " Ann Arbor");
        add(name);
    } else {
        add(name + " Ann Arbor");
        if venue {
            add(venue + " Ann Arbor");
        }
        add(name);
    }
    return qs[:3];
}

def _collect_images_for_queries(queries: list[str]) -> list[DossierImage] {
    hits: list[DossierImage] = [];
    for q in queries {
        hits = hits + search_public_images(q);
        if len(hits) >= 4 {
            break;
        }
    }
    return _dedupe_images(hits, 4);
}

glob _IMG_CACHE: dict[str, list] = {};
glob _IMG_TTL_S: float = 21600.0;

impl dossier_images(node_id: str) -> DossierMedia {
    # The curated set is expensive (LLM + image search) but stable: serve repeats from memory.
    hit = _IMG_CACHE.get(node_id);
    if hit and (time.time() - hit[0]) < _IMG_TTL_S {
        return hit[1];
    }
    media = _dossier_images_uncached(node_id);
    if len(media.images) > 0 {
        _IMG_CACHE[node_id] = [time.time(), media];
    }
    return media;
}

def _dossier_images_uncached(node_id: str) -> DossierMedia {
    _ensure_seed();
    n = _find_key(node_id);
    if n is None {
        return DossierMedia(images=[], queries=[], ai=False);
    }
    ven = _venue_of(n);
    venue_name = ven.name if ven else "";
    orgs = [n ->:OrganizedBy:->][?:Organizer];
    org_name = orgs[0].name if len(orgs) > 0 else "";
    queries = _heuristic_image_queries(n.name, n.kind, venue_name, org_name);
    if _has_llm() {
        try {
            # Agent path: ReAct tool loop picks queries and returns curated set.
            media = llm_curate_images(
                n.name, n.kind, venue_name, org_name, n.desc
            );
            cleaned = _dedupe_images(media.images, 4);
            if len(cleaned) > 0 {
                media.images = cleaned;
                media.ai = True;
                if len(media.queries) == 0 {
                    media.queries = queries;
                }
                return media;
            }
        } except Exception {
        }
        try {
            plan = llm_image_queries(
                n.name, n.kind, venue_name, org_name, n.desc
            );
            if plan.queries and len(plan.queries) > 0 {
                queries = plan.queries[:3];
            }
        } except Exception {
        }
    }
    return DossierMedia(
        images=_collect_images_for_queries(queries),
        queries=queries,
        ai=False
    );
}
