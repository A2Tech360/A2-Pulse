"""Bodies for pulse.jac: seeding, filters, traversal and ranking."""

import from services.event_dates { event_matches_date, parse_iso_date }

glob KIND_TOGGLES: list[str] = ["event", "organizer", "alert", "civic"];
glob MAX_NODES: int = 90;
glob MAX_BROWSE_CHILDREN: int = 24;
glob BROWSE_LENSES: list[dict[str, any]] = [
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

impl _has_llm -> bool {
    for k in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"] {
        v = os.environ.get(k, "");
        if v and len(v.strip()) > 8 {
            return True;
        }
    }
    return False;
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
}

impl _ensure_seed -> Hub {
    hubs = [root -->][?:Hub];
    if len(hubs) > 0 {
        hub = hubs[0];
        _migrate_seed_extras(hub);
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

impl _passes(n: PulseNode, spec: FilterSpec, clat: float, clng: float) -> bool {
    if n.kind == "source" or n.kind == "place" {
        return False;
    }
    if len(spec.kinds) > 0 and n.kind in KIND_TOGGLES and n.kind not in spec.kinds {
        return False;
    }
    if n.kind == "category" {
        return len(spec.categories) == 0 or n.name in spec.categories;
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
        if spec.price == "free" and n.price > 0.0 { return False; }
        if spec.price == "under10" and n.price >= 10.0 { return False; }
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
            ven = _venue_of(e);
            if ven is not None {
                k = ven.key if ven.key else jid(ven);
                if k not in seen {
                    seen.append(k);
                    out.append(ven);
                }
            }
        }
        if len(out) == 0 {
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
            if nb.kind == "source" {
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
    if n.kind == "alert" {
        if n.sub == "detour" {
            return "Check TheRide trip planner and give yourself 10 extra minutes.";
        }
        if commute == "car" {
            return "Shift deliveries and parking outside " + n.when + ".";
        }
        if commute == "bike" {
            return "Leave 10 minutes early or take the Fuller Rd path instead.";
        }
        return "Plan around it: " + n.when + ".";
    }
    if n.kind == "civic" {
        return "Sign up for public comment or email Council: " + n.when + ".";
    }
    if n.price == 0.0 {
        return "Free. Save it to your calendar for " + n.when + ".";
    }
    return "RSVP and grab a ticket ($" + str(int(n.price)) + ") for " + n.when + ".";
}

impl _heuristic_filters(text: str, prior: FilterSpec) -> FilterSpec {
    t = text.lower();
    spec = FilterSpec(query=text, categories=list(prior.categories), kinds=list(prior.kinds), price=prior.price, time=prior.time, date=prior.date, distance=prior.distance);
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
    spec = FilterSpec(categories=self.categories, kinds=self.kinds, price=self.price, time=self.time, date=self.date, distance=self.distance);
    nbrs = [here -->][?:PulseNode] + [here <--][?:PulseNode];
    fresh: list[PulseNode] = [];
    for nb in nbrs {
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
        distance=self.distance
    );
    fk = self.focus_key if self.focus_key else "root";
    nodes: list[GNode] = [];
    edges: list[GEdge] = [];

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
    visit [here -->][?:PulseNode];
}

impl MapSnapshot.pin {
    if here.kind not in KIND_TOGGLES {
        return;
    }
    on_route = here.key in self.route_keys;
    spec = FilterSpec(categories=self.categories, kinds=self.kinds, price=self.price, time=self.time, date=self.date, distance=self.distance);
    if on_route {
        # Always surface commute / home route impacts; still respect kind toggles.
        if len(self.kinds) > 0 and here.kind not in self.kinds {
            return;
        }
    } elif not _passes(here, spec, self.clat, self.clng) {
        return;
    }
    # Online or ungeocoded items have no real location; don't pin them at 0,0.
    if here.lat == 0.0 and here.lng == 0.0 {
        return;
    }
    ven = _venue_of(here);
    self.items.append(MapItem(
        id=jid(here), key=here.key, name=here.name, kind=here.kind, desc=here.desc,
        when=here.when, price=here.price, lat=here.lat, lng=here.lng,
        venue=(ven.name if ven else here.address), categories=_cats_of(here),
        source_name=here.source_name, source_url=here.source_url, path=here.path,
        dist=round(_miles(self.clat, self.clng, here.lat, here.lng), 2)
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
        if x.kind != "source" { links.append(_gnode(x, 1)); }
    }
    report Dossier(
        id=jid(here), key=here.key, name=here.name, kind=here.kind, desc=here.desc,
        when=here.when, venue=(ven.name if ven else ""), address=here.address,
        organizer=(orgs[0].name if len(orgs) > 0 else ""), price=here.price,
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
    today = datetime.now().weekday();
    homes = [here ->:LivesAt:->][?:Place];
    route = [here ->:CommutesVia:->][?:Place];
    interests = [here ->:InterestedIn:->][?:Category];
    follows = [here ->:Follows:->][?:Organizer];
    w = here.weights;
    scores: dict[str, float] = {};
    reasons: dict[str, list[str]] = {};
    nodes: dict[str, PulseNode] = {};

    def bump(n: PulseNode, pts: float, why: str) -> None {
        k = n.key;
        if k not in scores {
            scores[k] = 0.0;
            reasons[k] = [];
            nodes[k] = n;
        }
        scores[k] = scores[k] + pts;
        if why not in reasons[k] { reasons[k].append(why); }
    }

    for p in homes + route {
        is_home = p in homes;
        for x in [p <-:AffectsRoute:<-][?:PulseNode] {
            if x.kind == "alert" {
                bump(x, 3.0 if is_home else 2.6, ("Near your home in " if is_home else "On your " + here.commute + " route via ") + p.name);
            } else {
                bump(x, 2.2, "Affects " + p.name + ", where you live or travel");
            }
        }
        for v in [p <-:Near:<-][?:Venue] {
            for e in [v <-:HostedAt:<-][?:Event] {
                bump(e, 1.0, "Close by at " + v.name);
            }
        }
    }
    for c in interests {
        for x in [c <-:TaggedAs:<-][?:PulseNode] {
            bump(x, 1.5 * w.get(c.name, 1.0), "Matches your interest in " + c.name);
        }
    }
    for o in follows {
        for x in [o <-:OrganizedBy:<-][?:PulseNode] {
            bump(x, 2.0, "From " + o.name + ", which you follow");
        }
    }
    for (k, n) in nodes.items() {
        for c in _cats_of(n) {
            scores[k] = scores[k] * w.get(c, 1.0);
        }
        delta = n.day - today;
        if delta >= 0 and delta <= 2 and n.kind in ["civic", "alert"] {
            scores[k] = scores[k] + 0.6;
            reasons[k].append("Coming up in the next " + str(delta + 1) + " days");
        }
    }
    ranked = sorted(list(scores.keys()), key=lambda (k: str) -> float { return scores[k]; }, reverse=True);
    items: list[BriefItem] = [];
    for k in ranked[:5] {
        n = nodes[k];
        cats = _cats_of(n);
        items.append(BriefItem(
            id=jid(n), key=n.key, name=n.name, kind=n.kind, when=n.when,
            why=". ".join(reasons[k][:2]) + ".",
            action=_action_for(n, reasons[k], here.commute),
            category=(cats[0] if len(cats) > 0 else n.kind),
            source_name=n.source_name, source_url=n.source_url,
            score=round(scores[k], 2)
        ));
    }
    home_name = homes[0].name if len(homes) > 0 else "Ann Arbor";
    interest_names = [c.name for c in interests];
    lines: list[str] = [];
    i = 1;
    for it in items {
        lines.append(str(i) + ". " + it.name + " (" + it.when + "): " + it.why + " " + it.action);
        i += 1;
    }
    summary = "";
    used_ai = False;
    if self.use_ai and _has_llm() {
        try {
            profile = here.name + ", lives in " + home_name + ", commutes by " + here.commute + ", into " + ", ".join(interest_names);
            summary = llm_write_brief(profile, "\n".join(lines));
            used_ai = True;
        } except Exception {
            summary = "";
        }
    }
    if summary == "" {
        first = here.name.split(",")[0];
        parts: list[str] = ["Good morning " + first + ". Here is what touches your week in Ann Arbor."];
        j = 1;
        for it in items {
            parts.append("Number " + str(j) + ": " + it.name + ", " + it.when + ". " + it.action);
            j += 1;
        }
        parts.append("That is your Monday. Have a good week.");
        summary = " ".join(parts);
    }
    report Brief(
        persona=here.persona, profile_name=here.name, home=home_name, commute=here.commute,
        interests=interest_names, summary=summary, ai=used_ai, items=items
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
impl update_custom_profile(home_key: str, commute: str, interests: list[str]) -> dict[str, any] {
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
        try {
            spec = llm_parse_filters(text, prior, CATEGORIES);
            spec.categories = [c for c in spec.categories if c in CATEGORIES];
            spec.kinds = [k for k in spec.kinds if k in KIND_TOGGLES];
            if spec.price not in ["any", "free", "under10"] { spec.price = "any"; }
            if spec.time not in ["today", "weekend", "week"] { spec.time = "week"; }
            dval: any = spec.date;
            if not isinstance(dval, str) {
                spec.date = prior.date;
            }
            spec.query = text;
            if not spec.reply { spec.reply = "Updated your view."; }
            return spec;
        } except Exception {
            return _heuristic_filters(text, prior);
        }
    }
    return _heuristic_filters(text, prior);
}

impl list_personas() -> list[dict[str, any]] {
    _ensure_seed();
    out: list[dict[str, any]] = [];
    for p in [root -->][?:UserProfile] {
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

def _nominatim_search(query: str, limit: int) -> list[dict[str, any]] {
    q = query.strip();
    if len(q) < 2 {
        return [];
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
            "User-Agent": "A2Pulse/1.0 (Jac demo; local map search)",
            "Accept": "application/json"
        }
    );
    try {
        resp = urlopen(req, timeout=8);
        raw = resp.read().decode("utf-8");
        resp.close();
        data = json.loads(raw);
        if isinstance(data, list) {
            return data;
        }
    } except Exception {
        return [];
    }
    return [];
}

def _split_place_label(display: str) -> dict[str, any] {
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
glob _voices_cache: list[dict[str, any]] = [];

# Premade ElevenLabs voices, used when the key cannot list voices (no voices_read).
glob PREMADE_VOICES: list[dict[str, any]] = [
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

impl speak_brief(text: str, voice_id: str = "") -> dict[str, any] {
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip();
    if not key {
        return {"audio": "", "error": "ELEVENLABS_API_KEY is not set"};
    }
    text = text.strip()[:TTS_MAX_CHARS];
    if not text {
        return {"audio": "", "error": "Nothing to read"};
    }
    voice = voice_id.strip() or os.environ.get("ELEVENLABS_VOICE_ID", "").strip() or TTS_DEFAULT_VOICE;
    if not voice.isalnum() or len(voice) > 64 {
        return {"audio": "", "error": "Invalid voice id"};
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
        return {"audio": "", "error": f"ElevenLabs {e.code}: {detail}"};
    } except Exception as e {
        return {"audio": "", "error": f"ElevenLabs request failed: {e}"};
    }
    url = "data:audio/mpeg;base64," + base64.b64encode(mp3).decode("ascii");
    _tts_cache[cache_key] = url;
    return {"audio": url, "error": ""};
}

impl list_voices -> dict[str, any] {
    if _voices_cache {
        return {"voices": _voices_cache, "source": "account"};
    }
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip();
    if key {
        req = Request(
            "https://api.elevenlabs.io/v2/voices?page_size=100",
            headers={"xi-api-key": key, "Accept": "application/json"}
        );
        try {
            resp: any = urlopen(req, timeout=20);
            data: any = json.loads(resp.read().decode("utf-8"));
            resp.close();
            out: list[dict[str, any]] = [];
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
    tip = n.when if n.when else "";
    if n.kind == "alert" and not tip {
        tip = "Check before you leave.";
    } elif n.kind == "event" and n.price == 0.0 {
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

def _http_json(url: str, timeout: float = 8.0) -> dict[str, any] {
    req = Request(url, headers={"User-Agent": _IMG_UA, "Accept": "application/json"});
    try {
        resp: any = urlopen(req, timeout=timeout);
        raw: bytes = resp.read();
        resp.close();
        parsed: any = json.loads(raw.decode("utf-8", "replace"));
        if isinstance(parsed, dict) {
            return parsed as dict[str, any];
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

impl dossier_images(node_id: str) -> DossierMedia {
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
