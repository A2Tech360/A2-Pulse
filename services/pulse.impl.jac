"""Bodies for pulse.jac: seeding, filters, traversal and ranking."""

glob KIND_TOGGLES: list[str] = ["event", "organizer", "alert", "civic"];
glob MAX_NODES: int = 90;

impl _has_llm -> bool {
    return pulse_llm.llm_enabled();
}

impl _hub -> Hub {
    return _ensure_seed();
}

impl _ensure_seed -> Hub {
    hubs = [root -->][?:Hub];
    if len(hubs) > 0 {
        return hubs[0];
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
        today = datetime.now().weekday();
        if spec.time == "today" and n.day != today { return False; }
        if spec.time == "weekend" and n.day < 4 { return False; }
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
    return GNode(id=jid(n), key=n.key, name=n.name, kind=n.kind, sub=n.sub, depth=depth);
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
    spec = FilterSpec(query=text, categories=list(prior.categories), kinds=list(prior.kinds), price=prior.price, time=prior.time, distance=prior.distance);
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
    elif "tonight" in t or "today" in t { spec.time = "today"; }
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
    spec = FilterSpec(categories=self.categories, kinds=self.kinds, price=self.price, time=self.time, distance=self.distance);
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
    spec = FilterSpec(categories=self.categories, kinds=self.kinds, price=self.price, time=self.time, distance=self.distance);
    if on_route {
        # Always surface commute / home route impacts; still respect kind toggles.
        if len(self.kinds) > 0 and here.kind not in self.kinds {
            return;
        }
    } elif not _passes(here, spec, self.clat, self.clng) {
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
        if n.kind in ["source", "place"] { continue; }
        hay = (n.name + " " + n.kind + " " + n.sub + " " + n.desc).lower();
        if q == "" or q in hay {
            self.found.append(_gnode(n, 0));
        }
    }
    order: dict[str, int] = {"category": 0, "organizer": 1, "event": 2, "alert": 3, "civic": 4, "venue": 5};
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
    t_start = time.perf_counter();
    trace = new_trace(here.persona);
    today = datetime.now().weekday();
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

    def bump(n: PulseNode, pts: float, why: str, rule: str) -> None {
        k = n.key;
        if k not in scores {
            scores[k] = 0.0;
            reasons[k] = [];
            nodes[k] = n;
            rules[k] = [];
        }
        scores[k] = scores[k] + pts;
        rules[k].append({"rule": rule, "points": round(pts, 3), "detail": why});
        if why not in reasons[k] { reasons[k].append(why); }
    }

    for p in homes + route {
        is_home = p in homes;
        for x in [p <-:AffectsRoute:<-][?:PulseNode] {
            if x.kind == "alert" {
                bump(x, 3.0 if is_home else 2.6, ("Near your home in " if is_home else "On your " + here.commute + " route via ") + p.name, "home_alert" if is_home else "route_alert");
            } else {
                bump(x, 2.2, "Affects " + p.name + ", where you live or travel", "affects_place");
            }
        }
        for v in [p <-:Near:<-][?:Venue] {
            for e in [v <-:HostedAt:<-][?:Event] {
                bump(e, 1.0, "Close by at " + v.name, "near_venue");
            }
        }
    }
    for c in interests {
        for x in [c <-:TaggedAs:<-][?:PulseNode] {
            bump(x, 1.5 * w.get(c.name, 1.0), "Matches your interest in " + c.name, "interest");
        }
    }
    for o in follows {
        for x in [o <-:OrganizedBy:<-][?:PulseNode] {
            bump(x, 2.0, "From " + o.name + ", which you follow", "follows");
        }
    }
    for (k, n) in nodes.items() {
        for c in _cats_of(n) {
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
    ranked = sorted(list(scores.keys()), key=lambda (k: str) -> float { return scores[k]; }, reverse=True);
    t_score = time.perf_counter();

    # Action agent: a to-do for each of the top five.
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
        {"name": it.name, "kind": it.kind, "when": it.when, "reasons": strongest_first(reasons[it.key], rules[it.key]), "action": it.action}
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
            spec.query = text;
            if not spec.reply { spec.reply = "Updated your view."; }
            return spec;
        }
    }
    return _heuristic_filters(text, prior);
}

impl list_personas() -> list[dict] {
    _ensure_seed();
    out: list[dict] = [];
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

def _nominatim_search(query: str, limit: int) -> list[dict] {
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
    if key {
        req = Request(
            "https://api.elevenlabs.io/v2/voices?page_size=100",
            headers={"xi-api-key": key, "Accept": "application/json"}
        );
        try {
            resp: any = urlopen(req, timeout=20);
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
        }
    }
    return {"voices": PREMADE_VOICES, "source": "premade"};
}
