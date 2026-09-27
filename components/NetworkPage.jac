"""Network tab: accumulating lens browse with force layout."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Search01Icon,
    Cancel01Icon,
    ArrowUpRight01Icon,
    Analytics01Icon,
    ArrowLeft01Icon
}
import from "d3-force" {
    forceSimulation,
    forceLink,
    forceManyBody,
    forceCenter,
    forceCollide
}
import from react { useEffect }
import from .ui.input { Input }
import from .ui.skeleton { Skeleton }
import from .ui.button { Button }
import from .ui.switch { Switch }
import from .ui.select {
    Select,
    SelectTrigger,
    SelectValue,
    SelectContent,
    SelectItem
}
import from .FilterBar { FilterBar }
import from .pulse_theme {
    kind_color,
    kind_label,
    node_fill_color,
    future_date_chips,
    default_filters,
    all_categories
}
import from .net { with_timeout, gather, browse_timeout_ms, photo_timeout_ms }

glob CAMPUS_LAT: float = 42.2780;
glob CAMPUS_LNG: float = -83.7382;
glob PAN_GAIN: float = 0.38;
glob FORCE_LINK_DIST: float = 100.0;
glob FORCE_LINK_STRENGTH: float = 0.28;
glob FORCE_CHARGE: float = -120.0;
glob FORCE_ALPHA: float = 0.35;
glob FORCE_ALPHA_SOFT: float = 0.045;
glob FORCE_DRAG_ALPHA: float = 0.12;
glob FORCE_VELOCITY_DECAY: float = 0.72;
glob FORCE_DRAG_THRESHOLD: float = 5.0;
glob VIEW_W: float = 1200.0;
glob VIEW_H: float = 800.0;
glob ZOOM_MIN: float = 0.45;
glob ZOOM_MAX: float = 3.4;
glob ZOOM_WHEEL_STEP: float = 0.00135;
glob ZOOM_SPREAD_GAIN: float = 0.95;

glob LENS_STARTERS: list[dict] = [
    {"key": "all", "name": "All"},
    {"key": "lens-places", "name": "Places"},
    {"key": "lens-topics", "name": "Topics"},
    {"key": "lens-who", "name": "Hosts"},
    {"key": "lens-city", "name": "City"},
    {"key": "lens-community", "name": "Posted"}
];
glob LENS_ONLY: list[str] = [
    "lens-places",
    "lens-topics",
    "lens-who",
    "lens-city"
];
glob LEGEND: list[str] = [
    "lens",
    "place",
    "venue",
    "category",
    "organizer",
    "event",
    "community",
    "alert",
    "civic"
];

def node_radius(depth: int, kind: str) -> float {
    if kind == "lens" and depth == 0 {
        return 22.0;
    }
    if depth == 0 {
        return 18.0;
    }
    if kind == "lens" or kind == "place" or kind == "category" {
        return 14.0;
    }
    if kind == "venue" or kind == "organizer" {
        return 11.0;
    }
    return 8.0;
}

def is_leaf_kind(kind: str) -> bool {
    return kind in ["event", "alert", "civic"];
}
sv import from ..services.pulse {
    NetworkBrowse,
    SearchArchive,
    GetDossier,
    dossier_images,
    create_community_event,
    Snapshot,
    GNode,
    GEdge,
    Dossier,
    DossierImage,
    DossierMedia
}
sv import from ..services.event_ingest { sync_online_events, SyncReport }

def:pub DossierPanel(
    dossier: Dossier,
    onClose: Callable[[], None],
    onOpenNode: Callable[[str], None],
    onCenter: Callable[[str, str], None]
) -> JsxElement {
    has photos: list[DossierImage] = [],
        photosLoading: bool = True,
        photoReq: Ref[str] = Ref("");

    is_neighbor_post: bool = (
        len(dossier.posted_by) > 0 or dossier.source_name == "Posted"
    );
    where_bits = dossier.venue;
    if dossier.address {
        where_bits = where_bits + (" · " if where_bits else "") + dossier.address;
    }
    # -1 = the source gave no price; say so instead of "Free" or "$-1".
    price_label = (
        "See listing" if dossier.price < 0.0 else ("Free" if dossier.price == 0.0 else f"${dossier.price:.0f}")
    );

    async def load_photos {
        if is_neighbor_post {
            photos = [];
            photosLoading = False;
            return;
        }
        nid = dossier.id;
        photoReq.current = nid;
        w: any = window;
        cache: any = w.__pulsePhotoCache;
        if not cache {
            cache = {};
            w.__pulsePhotoCache = cache;
        }
        if nid in cache {
            photos = cache[nid];
            photosLoading = False;
            return;
        }
        photosLoading = True;
        photos = [];
        try {
            media: DossierMedia = await with_timeout(
                dossier_images(nid),
                DossierMedia(images=[], queries=[], ai=False),
                photo_timeout_ms()
            );
            imgs: list[DossierImage] = media.images if media.images else [];
            cache[nid] = imgs;
            if photoReq.current == nid {
                photos = imgs;
            }
        } except Exception {
            if photoReq.current == nid {
                photos = [];
            }
        }
        if photoReq.current == nid {
            photosLoading = False;
        }
    }

    can with [dossier.id] entry {
        if is_neighbor_post {
            photos = [];
            photosLoading = False;
        } else {
            load_photos();
        }
    }

    def bind_link(nid: str) -> Callable[[MouseEvent], None] {
        captured: str = nid;
        return lambda (e: MouseEvent) { onOpenNode(captured); };
    }

    return
        <div
            className="flex flex-col"
            role="region"
            aria-label="Node dossier"
        >
            <div className="flex items-start justify-between gap-4">
                <span
                    className="font-display text-[11px] font-semibold uppercase italic tracking-[0.14em]"
                    style={{"color": kind_color(dossier.kind)}}
                >
                    {kind_label(dossier.kind)}
                </span>
                <button
                    type="button"
                    onClick={lambda (e: MouseEvent) { onClose(); }}
                    className="kicker inline-flex items-center gap-1.5 text-muted-foreground transition-colors hover:text-foreground"
                >
                    <HugeiconsIcon
                        icon={Cancel01Icon}
                        strokeWidth={2}
                        className="size-3.5"
                    />
                    {"Close"}
                </button>
            </div>
            <h2 className="mt-4 font-display text-2xl font-bold leading-tight tracking-tight text-foreground sm:text-[1.65rem]">
                {dossier.name}
            </h2>
            {not is_neighbor_post
                and photosLoading
                and <div className="mt-4 overflow-hidden rounded-xl border border-border bg-muted/40">
                    <Skeleton className="h-40 w-full rounded-none"/>
                </div>}
            {not is_neighbor_post
                and not photosLoading
                and len(photos) > 0
                and <div className="mt-4 flex flex-col gap-2">
                    <div
                        className={(
                            "grid gap-2 "
                            + (
                                "grid-cols-1"
                                    if len(photos) == 1
                                    else "grid-cols-2"
                            )
                        )}
                    >
                        {for (i, im) in enumerate(photos) {
                            <figure
                                key={im.url + str(i)}
                                className={(
                                    "overflow-hidden rounded-xl border border-border bg-muted/30 "
                                    + (
                                        "col-span-2"
                                            if i == 0 and len(photos) > 1
                                            else ""
                                    )
                                )}
                            >
                                <img
                                    src={im.url}
                                    alt={im.caption if im.caption else dossier.name}
                                    loading="lazy"
                                    referrerPolicy="no-referrer"
                                    className={(
                                        "w-full object-cover "
                                        + (
                                            "max-h-52"
                                                if i == 0
                                                else "aspect-[4/3] max-h-36"
                                        )
                                    )}
                                    onError={lambda (e: any) {
                                        t: any = e.target;
                                        if t and t.style {
                                            t.style.display = "none";
                                        }
                                    }}
                                />
                                {(im.caption or im.credit)
                                    and <figcaption className="border-t border-border pt-1.5 pb-1.5 pl-2.5 pr-2.5 text-[10px] leading-snug text-muted-foreground">
                                        {(
                                            im.caption
                                            + (
                                                " · " + im.credit
                                                    if im.credit
                                                    else ""
                                            )
                                                if im.caption
                                                else im.credit
                                        )}
                                    </figcaption>}
                            </figure>
                        }}
                    </div>
                </div>}
            {dossier.desc
                and <p className="mt-4 text-[15px] leading-relaxed text-foreground/85">
                    {dossier.desc}
                </p>}
            <dl className="mt-6 flex flex-col gap-2.5 border-t border-border pt-5 text-sm">
                {dossier.when
                    and <div className="flex items-baseline gap-4">
                        <dt className="w-20 shrink-0 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                            {"When"}
                        </dt>
                        <dd className="text-foreground">{dossier.when}</dd>
                    </div>}
                {where_bits
                    and <div className="flex items-baseline gap-4">
                        <dt className="w-20 shrink-0 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                            {"Where"}
                        </dt>
                        <dd className="text-foreground">{where_bits}</dd>
                    </div>}
                {dossier.organizer
                    and <div className="flex items-baseline gap-4">
                        <dt className="w-20 shrink-0 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                            {("Posted by" if is_neighbor_post else "Who")}
                        </dt>
                        <dd className="text-foreground">{dossier.organizer}</dd>
                    </div>}
                {not is_neighbor_post
                    and dossier.kind == "event"
                    and <div className="flex items-baseline gap-4">
                        <dt className="w-20 shrink-0 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                            {"Price"}
                        </dt>
                        <dd
                            className="font-medium"
                            style={{"color": kind_color(dossier.kind)}}
                        >
                            {price_label}
                        </dd>
                    </div>}
                {not is_neighbor_post
                    and dossier.source_name
                    and <div className="flex items-baseline gap-4">
                        <dt className="w-20 shrink-0 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                            {"Source"}
                        </dt>
                        <dd className="text-foreground">
                            {dossier.source_url
                                and <a
                                    href={dossier.source_url}
                                    target="_blank"
                                    rel="noreferrer"
                                    className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
                                >
                                    {dossier.source_name}
                                    <HugeiconsIcon
                                        icon={ArrowUpRight01Icon}
                                        strokeWidth={2}
                                        className="size-3.5"
                                    />
                                </a>}
                            {not dossier.source_url and dossier.source_name}
                        </dd>
                    </div>}
            </dl>
            {len(dossier.categories) > 0
                and <div className="mt-5 flex flex-wrap gap-1.5">
                    {for c in dossier.categories {
                        <span
                            key={c}
                            className="rounded-md border border-border pt-0.5 pb-0.5 pl-2 pr-2 text-[11px] text-muted-foreground"
                        >
                            {c}
                        </span>
                    }}
                </div>}
            {not is_neighbor_post
                and len(dossier.links) > 0
                and <div className="mt-6 border-t border-border pt-5">
                    <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                        {"Tied to"}
                    </span>
                    <ul className="mt-3 flex flex-col gap-1.5">
                        {for ln in dossier.links {
                            <li key={ln.id}>
                                <button
                                    type="button"
                                    onClick={bind_link(ln.id)}
                                    className="flex w-full items-center gap-2 rounded-md pt-1.5 pb-1.5 pl-1 pr-1 text-left text-sm hover:bg-muted"
                                >
                                    <span
                                        className="size-2 shrink-0 rounded-full"
                                        style={{
                                            "backgroundColor": kind_color(ln.kind)
                                        }}
                                    />
                                    <span className="flex-1 truncate font-medium">
                                        {ln.name}
                                    </span>
                                    <span className="kicker text-muted-foreground">
                                        {kind_label(ln.kind)}
                                    </span>
                                </button>
                            </li>
                        }}
                    </ul>
                </div>}
            <div className="mt-auto flex flex-wrap gap-2 pt-8">
                <Button
                    size="sm"
                    variant="outline"
                    onClick={lambda (e: MouseEvent) {
                        onCenter(dossier.key, dossier.name);
                    }}
                >
                    {"Center here"}
                </Button>
            </div>
        </div>;
}

def:pub NetworkPage(
    filters: dict,
    onFilters: Callable[[dict], None],
    dark: bool = True,
    syncVersion: int = 0,
    onSynced: Callable[[], None] = lambda {}
) -> JsxElement {
    has focusKey: str = "root",
        focusName: str = "Ann Arbor",
        activeTab: str = "all",
        trail: list[dict] = [{"key": "root", "name": "Ann Arbor"}],
        expandedKeys: list[str] = ["root"],
        nodes: list[GNode] = [],
        edges: list[GEdge] = [],
        loading: bool = True,
        error: str = "",
        query: str = "",
        results: list[GNode] = [],
        searched: str = "",
        selected: Dossier | None = None,
        selectedId: str = "",
        sidebarTab: str = "here",
        hoverId: str = "",
        showFilters: bool = False,
        expandAll: bool = False,
        showPost: bool = False,
        postName: str = "",
        postWhen: str = "",
        postDesc: str = "",
        postBy: str = "",
        postCat: str = "social",
        postDate: str = "",
        postBusy: bool = False,
        postMsg: str = "",
        panX: float = 0.0,
        panY: float = 0.0,
        zoom: float = 1.0,
        dragging: bool = False,
        draggingNode: bool = False,
        layoutTick: int = 0,
        svgRef: Ref[any] = Ref(None),
        canvasRef: Ref[any] = Ref(None),
        dragSession: Ref[any] = Ref(
            {
                "active": False,
                "didPan": False,
                "suppressClick": False,
                "lastX": 0.0,
                "lastY": 0.0
            }
        ),
        nodeDrag: Ref[any] = Ref(
            {
                "active": False,
                "id": "",
                "didDrag": False,
                "startX": 0.0,
                "startY": 0.0
            }
        ),
        panRef: Ref[any] = Ref({"x": 0.0, "y": 0.0}),
        zoomRef: Ref[float] = Ref(1.0),
        lastForceZoom: Ref[float] = Ref(1.0),
        pinchRef: Ref[any] = Ref(
            {
                "active": False,
                "id1": 0,
                "id2": 0,
                "startDist": 0.0,
                "startZoom": 1.0,
                "pts": {}
            }
        ),
        focusKeyRef: Ref[str] = Ref("root"),
        rootSeq: Ref[int] = Ref(0),
        expandSeq: Ref[int] = Ref(0),
        simRef: Ref[any] = Ref(None),
        simById: Ref[any] = Ref({}),
        rafPending: Ref[bool] = Ref(False),
        tickCount: Ref[int] = Ref(0),
        syncing: bool = False,
        syncMsg: str = "",
        didAutoSync: bool = False,
        filtersSeen: Ref[bool] = Ref(False),
        dossierCache: Ref[dict[str, any]] = Ref({}),
        dossierPending: Ref[dict[str, any]] = Ref({}),
        idlePrefetchTimer: Ref[any] = Ref(None),
        idlePrefetchQueue: Ref[list[str]] = Ref([]),
        browseInflight: Ref[int] = Ref(0);

    def key_in_expanded(key: str) -> bool {
        for k in expandedKeys {
            if k == key {
                return True;
            }
        }
        return False;
    }

    def node_dim(n: GNode) -> float {
        # Full for focus + its neighbors; mid for trail; soft for the rest.
        if n.key == focusKey or n.id == selectedId or n.id == hoverId {
            return 1.0;
        }
        fid = "";
        for m in nodes {
            if m.key == focusKey {
                fid = m.id;
            }
        }
        if fid {
            for e in edges {
                if (e.source == fid and e.target == n.id) or (
                    e.target == fid and e.source == n.id
                ) {
                    return 0.92;
                }
            }
        }
        for step in trail {
            if str(step["key"]) == n.key {
                return 0.5;
            }
        }
        return 0.22;
    }

    def edge_dim(src_id: str, tgt_id: str) -> float {
        fid = "";
        for n in nodes {
            if n.key == focusKey {
                fid = n.id;
            }
        }
        if hoverId and (src_id == hoverId or tgt_id == hoverId) {
            return 0.85;
        }
        if selectedId and (src_id == selectedId or tgt_id == selectedId) {
            return 0.85;
        }
        if fid and (src_id == fid or tgt_id == fid) {
            return 0.9;
        }
        return 0.14;
    }

    def clamp_zoom(z: float) -> float {
        if z < ZOOM_MIN {
            return ZOOM_MIN;
        }
        if z > ZOOM_MAX {
            return ZOOM_MAX;
        }
        return z;
    }

    def reset_camera {
        panRef.current = {"x": 0.0, "y": 0.0};
        panX = 0.0;
        panY = 0.0;
        zoomRef.current = 1.0;
        zoom = 1.0;
        lastForceZoom.current = 0.0;
        retune_forces_for_zoom(1.0);
    }

    def is_lens_key(key: str) -> bool {
        for k in LENS_ONLY {
            if k == key {
                return True;
            }
        }
        return False;
    }

    def seed_lens_hubs(hubs: list[GNode]) {
        # Spread the four browse hubs so overview isn't a tight cluster.
        slots: list[list[float]] = [
            [340.0, 250.0],
            [860.0, 250.0],
            [340.0, 560.0],
            [860.0, 560.0]
        ];
        i: int = 0;
        for h in hubs {
            if i >= len(slots) {
                break;
            }
            h.x = slots[i][0];
            h.y = slots[i][1];
            i += 1;
        }
    }

    async def browse_raw(want: str) -> any {
        posted_lane: bool = (
            activeTab == "lens-community" or want == "lens-community"
        );
        res = root spawn NetworkBrowse(
            focus_key=want,
            categories=filters["categories"] or [],
            kinds=filters["kinds"] or [],
            price=filters["price"] or "any",
            time=filters["time"] or "week",
            date=filters["date"] or "",
            community=False,
            community_only=posted_lane,
            distance=filters["distance"] or 0.0,
            clat=CAMPUS_LAT,
            clng=CAMPUS_LNG
        );
        return res;
    }

    # Soft deadline: show Retry instead of hanging forever on a stalled browse.
    async def fetch_browse(want: str) -> Snapshot | None {
        browseInflight.current = int(browseInflight.current) + 1;
        res: any = None;
        out: Snapshot | None = None;
        try {
            res = await with_timeout(browse_raw(want), None, browse_timeout_ms());
            if res is not None and res.reports and len(res.reports) > 0 {
                out = res.reports[0];
            }
        } except Exception {
            out = None;
        }
        n: int = int(browseInflight.current) - 1;
        browseInflight.current = 0 if n < 0 else n;
        return out;
    }

    async def load_overview {
        loading = True;
        error = "";
        activeTab = "all";
        expandAll = False;
        showPost = False;
        focusKeyRef.current = "root";
        rs: int = int(rootSeq.current) + 1;
        rootSeq.current = rs;
        expandSeq.current = int(expandSeq.current) + 1;
        snap = await fetch_browse("root");
        if int(rootSeq.current) != rs {
            return;
        }
        if snap is None {
            error = "Can't reach the A2 Pulse server right now. Check your connection, then retry.";
            nodes = [];
            edges = [];
            loading = False;
            return;
        }
        merged_nodes: list[GNode] = [];
        merged_edges: list[GEdge] = [];
        have: dict[str, bool] = {};
        for n in snap.nodes {
            if n.key == "root" {
                n.x = VIEW_W / 2.0;
                n.y = VIEW_H / 2.0;
            }
            merged_nodes = merged_nodes + [n];
            have[n.id] = True;
            if n.key {
                have[n.key] = True;
            }
        }
        for e in snap.edges {
            merged_edges = merged_edges + [e];
        }
        hubs: list[GNode] = [];
        for n in merged_nodes {
            if is_lens_key(n.key) {
                hubs = hubs + [n];
            }
        }
        seed_lens_hubs(hubs);
        # Paint hubs right away so the canvas isn't stuck empty.
        nodes = merged_nodes;
        edges = merged_edges;
        expandedKeys = ["root"];
        focusKey = "root";
        focusName = "Ann Arbor";
        trail = [{"key": "root", "name": "All"}];
        selected = None;
        selectedId = "";
        sidebarTab = "here";
        loading = False;
        exp: list[str] = ["root"];
        edge_have: dict[str, bool] = {};
        for e in merged_edges {
            edge_have[e.source + ">" + e.target] = True;
        }
        # Start every lens browse at once; await in order so the canvas fills as
        # each returns (wall time ≈ slowest lens, not the sum).
        lens_tasks: list[any] = [];
        for lens_key in LENS_ONLY {
            lens_tasks = lens_tasks + [fetch_browse(lens_key)];
        }
        ti: int = 0;
        for lens_key in LENS_ONLY {
            if int(rootSeq.current) != rs or activeTab != "all" {
                return;
            }
            child: Snapshot | None = None;
            try {
                child = await lens_tasks[ti];
            } except Exception {
                child = None;
            }
            ti += 1;
            if int(rootSeq.current) != rs or activeTab != "all" {
                return;
            }
            if child is None {
                continue;
            }
            exp = exp + [lens_key];
            px: float = VIEW_W / 2.0;
            py: float = VIEW_H / 2.0;
            for h in hubs {
                if h.key == lens_key {
                    px = h.x;
                    py = h.y;
                }
            }
            i: int = 0;
            for g in child.nodes {
                if g.key == lens_key or g.id in have or g.key in have {
                    continue;
                }
                slot: int = i % 10;
                col: int = slot % 5;
                row: int = 0 if slot < 5 else 1;
                ox: float = float(col - 2) * 70.0;
                oy: float = float(row) * 68.0 - 20.0;
                g.x = round(px + ox, 1);
                g.y = round(py + oy, 1);
                merged_nodes = merged_nodes + [g];
                have[g.id] = True;
                if g.key {
                    have[g.key] = True;
                }
                i += 1;
            }
            for e in child.edges {
                ek: str = e.source + ">" + e.target;
                if ek in edge_have {
                    continue;
                }
                edge_have[ek] = True;
                merged_edges = merged_edges + [e];
            }
            # Progressive merge — keep hubs pinned via live positions.
            nodes = merged_nodes;
            edges = merged_edges;
            expandedKeys = exp;
        }
        if int(rootSeq.current) != rs or activeTab != "all" {
            return;
        }
        nodes = merged_nodes;
        edges = merged_edges;
        expandedKeys = exp;
        error = "";
        queue_idle_dossier_prefetch();
    }

    async def load_lens_tab(lens_key: str, lens_name: str) {
        loading = True;
        error = "";
        activeTab = lens_key;
        focusKeyRef.current = lens_key;
        rs: int = int(rootSeq.current) + 1;
        rootSeq.current = rs;
        expandSeq.current = int(expandSeq.current) + 1;
        # Clear prior sim so the isolated branch lays out cleanly.
        simById.current = {};
        snap = await fetch_browse(lens_key);
        if int(rootSeq.current) != rs {
            return;
        }
        if snap is None {
            error = "Can't reach the A2 Pulse server right now. Check your connection, then retry.";
            nodes = [];
            edges = [];
            loading = False;
            return;
        }
        got: Snapshot = snap as Snapshot;
        # Seed the lens hub near center; kids fan around it with room.
        # Posted has no hub — fan every topic node around the viewport center.
        cx: float = VIEW_W / 2.0;
        cy: float = VIEW_H / 2.0;
        if lens_key == "lens-community" {
            ncount: int = max(len(got.nodes), 1);
            i: int = 0;
            for g in got.nodes {
                ang: float = (6.283185307 * float(i)) / float(ncount);
                g.x = round(cx + 240.0 * (Math.cos(ang) as float), 1);
                g.y = round(cy + 180.0 * (Math.sin(ang) as float), 1);
                i += 1;
            }
        } else {
            i: int = 0;
            for g in got.nodes {
                if g.key == lens_key {
                    g.x = cx;
                    g.y = cy;
                } else {
                    ang: float = (6.283185307 * float(i)) / float(
                        max(len(got.nodes) - 1, 1)
                    );
                    g.x = round(cx + 210.0 * (Math.cos(ang) as float), 1);
                    g.y = round(cy + 160.0 * (Math.sin(ang) as float), 1);
                    i += 1;
                }
            }
        }
        nodes = got.nodes;
        edges = got.edges;
        expandedKeys = [lens_key];
        focusKey = lens_key;
        focusName = lens_name;
        trail = [
            {"key": "root", "name": "All"},
            {"key": lens_key, "name": lens_name}
        ];
        selected = None;
        selectedId = "";
        sidebarTab = "here";
        error = "";
        loading = False;
        queue_idle_dossier_prefetch();
    }

    async def switch_tab(tab_key: str, tab_name: str) {
        reset_camera();
        expandAll = False;
        idlePrefetchQueue.current = [];
        if idlePrefetchTimer.current {
            clearTimeout(idlePrefetchTimer.current);
            idlePrefetchTimer.current = None;
        }
        if tab_key != "lens-community" {
            showPost = False;
        }
        if tab_key == "all" {
            await load_overview();
        } else {
            await load_lens_tab(tab_key, tab_name);
        }
    }

    async def load_root {
        await load_overview();
    }

    def parent_xy(key: str, cur: list[GNode]) -> list[float] {
        px: float = VIEW_W / 2.0;
        py: float = VIEW_H / 2.0;
        by_id: any = simById.current;
        for n in cur {
            if n.key != key {
                continue;
            }
            if by_id {
                try {
                    d: any = by_id[n.id];
                    if d and d["x"] is not None {
                        return [float(d["x"]), float(d["y"])];
                    }
                } except Exception {
                    _ = None;
                }
            }
            return [n.x, n.y];
        }
        return [px, py];
    }

    def merge_snap(
        key: str, snap: Snapshot, cur_nodes: list[GNode], cur_edges: list[GEdge]
    ) -> dict[str, any] {
        xy = parent_xy(key, cur_nodes);
        px: float = xy[0];
        py: float = xy[1];
        have: dict[str, bool] = {};
        for n in cur_nodes {
            have[n.id] = True;
            if n.key {
                have[n.key] = True;
            }
        }
        edge_have: dict[str, bool] = {};
        for e in cur_edges {
            edge_have[e.source + "|" + e.target] = True;
            edge_have[e.target + "|" + e.source] = True;
        }
        merged_nodes: list[GNode] = [];
        for n in cur_nodes {
            merged_nodes = merged_nodes + [n];
        }
        merged_edges: list[GEdge] = [];
        for e in cur_edges {
            merged_edges = merged_edges + [e];
        }
        i: int = 0;
        for g in snap.nodes {
            if g.key == key {
                if g.key not in have and g.id not in have {
                    g.x = px;
                    g.y = py;
                    merged_nodes = merged_nodes + [g];
                    have[g.id] = True;
                    have[g.key] = True;
                }
                continue;
            }
            if g.id in have or g.key in have {
                continue;
            }
            slot: int = i % 12;
            col: int = slot % 4;
            row: int = 0;
            if slot >= 8 {
                row = 2;
            } elif slot >= 4 {
                row = 1;
            }
            ox: float = float(col - 1) * 52.0 - 26.0;
            oy: float = float(row - 1) * 48.0;
            g.x = round(px + ox + float(i) * 2.0, 1);
            g.y = round(py + oy - float(i) * 1.5, 1);
            merged_nodes = merged_nodes + [g];
            have[g.id] = True;
            if g.key {
                have[g.key] = True;
            }
            i += 1;
        }
        for e in snap.edges {
            ek = e.source + "|" + e.target;
            if ek in edge_have {
                continue;
            }
            merged_edges = merged_edges + [e];
            edge_have[ek] = True;
            edge_have[e.target + "|" + e.source] = True;
        }
        return {"nodes": merged_nodes, "edges": merged_edges};
    }

    def expand_child_keys(
        hub_key: str,
        cur: list[GNode],
        cur_edges: list[GEdge],
        include_leaves: bool = False
    ) -> list[str] {
        hub_id: str = "";
        for n in cur {
            if n.key == hub_key {
                hub_id = n.id;
            }
        }
        if not hub_id {
            return [];
        }
        out: list[str] = [];
        seen: dict[str, bool] = {};
        for e in cur_edges {
            other: str = "";
            if e.source == hub_id {
                other = e.target;
            } elif e.target == hub_id {
                other = e.source;
            } else {
                continue;
            }
            for n in cur {
                if n.id != other {
                    continue;
                }
                if not n.key or n.key == hub_key {
                    continue;
                }
                if is_leaf_kind(n.kind) {
                    if not include_leaves {
                        continue;
                    }
                } elif not n.expandable {
                    continue;
                }
                if n.key in seen {
                    continue;
                }
                seen[n.key] = True;
                out = out + [n.key];
            }
        }
        return out;
    }

    def canvas_hub_seeds(hub_key: str, cur: list[GNode]) -> list[str] {
        # Posted has no hub edges — open every topic already on the canvas.
        out: list[str] = [];
        seen: dict[str, bool] = {};
        for n in cur {
            if not n.key or n.key == hub_key {
                continue;
            }
            if is_leaf_kind(n.kind) or not n.expandable {
                continue;
            }
            if n.key in seen {
                continue;
            }
            seen[n.key] = True;
            out = out + [n.key];
        }
        return out;
    }

    async def expand_into(key: str) {
        if key == "" or key == "root" {
            return;
        }
        es: int = int(expandSeq.current) + 1;
        expandSeq.current = es;
        rs_at_start: int = int(rootSeq.current);
        loading = True;
        snap = await fetch_browse(key);
        if int(expandSeq.current) != es or int(rootSeq.current) != rs_at_start {
            return;
        }
        if snap is None {
            loading = False;
            return;
        }
        merged = merge_snap(key, snap, nodes, edges);
        nodes = merged["nodes"];
        edges = merged["edges"];
        if not key_in_expanded(key) {
            expandedKeys = expandedKeys + [key];
        }
        loading = False;
        queue_idle_dossier_prefetch();
    }

    async def open_all_connections(hub: str = "") {
        want: str = hub if hub else focusKey;
        if want == "" or want == "root" {
            return;
        }
        es: int = int(expandSeq.current) + 1;
        expandSeq.current = es;
        rs_at_start: int = int(rootSeq.current);
        loading = True;
        cur_nodes: list[GNode] = [];
        for n in nodes {
            cur_nodes = cur_nodes + [n];
        }
        cur_edges: list[GEdge] = [];
        for e in edges {
            cur_edges = cur_edges + [e];
        }
        done: dict[str, bool] = {};
        opened: list[str] = [];
        for k in expandedKeys {
            done[k] = True;
            opened = opened + [k];
        }
        # Two hops from focus. Fetch each depth wave in parallel.
        frontier: list[str] = [want];
        depth_of: dict[str, int] = {};
        depth_of[want] = 0;
        depth: int = 0;
        while len(frontier) > 0 and depth <= 2 {
            if int(expandSeq.current) != es or int(rootSeq.current) != rs_at_start {
                return;
            }
            if len(cur_nodes) >= 90 {
                break;
            }
            to_fetch: list[str] = [];
            for k in frontier {
                if k not in done {
                    to_fetch = to_fetch + [k];
                }
            }
            if len(to_fetch) > 0 {
                tasks: list[any] = [];
                for k in to_fetch {
                    tasks = tasks + [fetch_browse(k)];
                }
                snaps: list[any] = [];
                try {
                    snaps = await gather(tasks);
                } except Exception {
                    snaps = [];
                    for k in to_fetch {
                        snaps = snaps + [None];
                    }
                }
                if int(expandSeq.current) != es or int(rootSeq.current) != rs_at_start {
                    return;
                }
                si: int = 0;
                for k in to_fetch {
                    snap: any = snaps[si] if si < len(snaps) else None;
                    si += 1;
                    if snap is not None {
                        merged = merge_snap(k, snap, cur_nodes, cur_edges);
                        cur_nodes = merged["nodes"];
                        cur_edges = merged["edges"];
                        done[k] = True;
                        opened = opened + [k];
                    }
                }
            }
            if depth >= 2 {
                break;
            }
            next_front: list[str] = [];
            for k in frontier {
                dpth: int = depth_of[k] if k in depth_of else 0;
                cks: list[str] = expand_child_keys(
                    k, cur_nodes, cur_edges, include_leaves=(dpth == 0)
                );
                if len(cks) == 0 and dpth == 0 {
                    cks = canvas_hub_seeds(k, cur_nodes);
                }
                for ck in cks {
                    if ck in depth_of {
                        continue;
                    }
                    depth_of[ck] = dpth + 1;
                    next_front = next_front + [ck];
                }
            }
            frontier = next_front;
            depth += 1;
        }
        if int(expandSeq.current) != es or int(rootSeq.current) != rs_at_start {
            return;
        }
        nodes = cur_nodes;
        edges = cur_edges;
        expandedKeys = opened;
        loading = False;
    }

    async def close_all_connections {
        hub: str = focusKey;
        if hub == "" or hub == "root" {
            return;
        }
        es: int = int(expandSeq.current) + 1;
        expandSeq.current = es;
        rs_at_start: int = int(rootSeq.current);
        loading = True;
        snap = await fetch_browse(hub);
        if int(expandSeq.current) != es or int(rootSeq.current) != rs_at_start {
            return;
        }
        if snap is None {
            loading = False;
            return;
        }
        # Keep trail hubs already on-canvas; rebuild from the focus snapshot.
        keep: list[GNode] = [];
        keep_ids: dict[str, bool] = {};
        for step in trail {
            sk: str = str(step["key"]);
            if sk == hub {
                continue;
            }
            for n in nodes {
                if n.key == sk and n.id not in keep_ids {
                    keep = keep + [n];
                    keep_ids[n.id] = True;
                    if n.key {
                        keep_ids[n.key] = True;
                    }
                }
            }
        }
        for g in snap.nodes {
            if g.id in keep_ids or g.key in keep_ids {
                continue;
            }
            keep = keep + [g];
            keep_ids[g.id] = True;
            if g.key {
                keep_ids[g.key] = True;
            }
        }
        new_edges: list[GEdge] = [];
        edge_have: dict[str, bool] = {};
        for e in snap.edges {
            ek = e.source + "|" + e.target;
            if ek in edge_have {
                continue;
            }
            src_ok = False;
            tgt_ok = False;
            for n in keep {
                if n.id == e.source {
                    src_ok = True;
                }
                if n.id == e.target {
                    tgt_ok = True;
                }
            }
            if src_ok and tgt_ok {
                new_edges = new_edges + [e];
                edge_have[ek] = True;
            }
        }
        nodes = keep;
        edges = new_edges;
        exp: list[str] = [];
        for step in trail {
            sk2: str = str(step["key"]);
            if sk2 and sk2 != "root" {
                exp = exp + [sk2];
            }
        }
        if hub not in exp {
            exp = exp + [hub];
        }
        expandedKeys = exp;
        loading = False;
    }

    async def set_expand_all(on: bool) {
        expandAll = on;
        if on {
            await open_all_connections(focusKey);
        } else {
            await close_all_connections();
        }
    }

    async def reload_active_tab {
        if activeTab == "all" or activeTab == "" {
            await load_overview();
            return;
        }
        tab_name: str = activeTab;
        for s in LENS_STARTERS {
            if str(s["key"]) == activeTab {
                tab_name = str(s["name"]);
            }
        }
        await load_lens_tab(activeTab, tab_name);
    }

    async def run_online_sync(force: bool) {
        if syncing {
            return;
        }
        syncing = True;
        syncMsg = "Pulling public calendars...";
        try {
            rep: SyncReport = await sync_online_events(force);
            syncMsg = rep.message;
            if len(rep.errors) > 0 and rep.created + rep.updated == 0 {
                syncMsg = rep.message + " (" + "; ".join(rep.errors[:2]) + ")";
            }
            if "Skipped" in rep.message and len(nodes) > 0 {
                # Keep the current canvas — don't abort an in-flight overview.
            } else {
                onSynced();
                await reload_active_tab();
            }
        } except Exception {
            syncMsg = "Live sync failed — keeping the seeded archive.";
            if len(nodes) == 0 {
                await reload_active_tab();
            }
        }
        syncing = False;
    }

    async can with entry {
        await load_overview();
    }

    # Redraw after a manual sync bumps AppShell.syncVersion (also refreshes Map).
    can with [syncVersion] entry {
        if syncVersion > 0 and not syncing {
            clear_dossier_cache();
            reload_active_tab();
        }
    }

    can with [focusKey] entry {
        focusKeyRef.current = focusKey;
    }

    # Filters reset the canvas to root (fresh walk); expanding never collapses.
    # Skip the first run — initial load comes from sync / entry.
    can with [filters] entry {
        if not filtersSeen.current {
            filtersSeen.current = True;
            return;
        }
        focusKeyRef.current = "root";
        focusKey = "root";
        focusName = "Ann Arbor";
        activeTab = "all";
        trail = [{"key": "root", "name": "All"}];
        reset_camera();
        load_overview();
    }

    def schedule_layout_tick {
        if rafPending.current {
            return;
        }
        rafPending.current = True;
        requestAnimationFrame(
            lambda {
                rafPending.current = False;
                n: int = int(tickCount.current) + 1;
                tickCount.current = n;
                layoutTick = n;
            }
        );
    }

    def stop_simulation {
        sim: any = simRef.current;
        if sim {
            try {
                sim.stop();
            } except Exception {
            }
        }
        simRef.current = None;
        # Keep simById so the next rebuild can inherit live positions
        # (clearing it here caused hard flinch on every expand).
    }

    def rebuild_simulation {
        prev: any = simById.current;
        had_prev: bool = False;
        try {
            if prev and len(prev.keys()) > 0 {
                had_prev = True;
            }
        } except Exception {
            had_prev = bool(prev);
        }
        stop_simulation();
        if len(nodes) == 0 {
            simById.current = {};
            schedule_layout_tick();
            return;
        }
        by_id: dict[str, any] = {};
        sim_nodes: list[any] = [];
        for n in nodes {
            sx: float = n.x if n.x != 0.0 or n.y != 0.0 else VIEW_W / 2.0;
            sy: float = n.y if n.x != 0.0 or n.y != 0.0 else VIEW_H / 2.0;
            svx: float = 0.0;
            svy: float = 0.0;
            if prev {
                try {
                    pd: any = prev[n.id];
                    if pd and pd["x"] is not None and pd["y"] is not None {
                        sx = float(pd["x"]);
                        sy = float(pd["y"]);
                        if pd["vx"] is not None {
                            svx = float(pd["vx"]) * 0.12;
                        }
                        if pd["vy"] is not None {
                            svy = float(pd["vy"]) * 0.12;
                        }
                    }
                } except Exception {
                }
            }
            d: dict[str, any] = {
                "id": n.id,
                "key": n.key,
                "name": n.name,
                "kind": n.kind,
                "depth": n.depth,
                "expandable": n.expandable,
                "x": sx,
                "y": sy,
                "vx": svx,
                "vy": svy,
                "fx": None,
                "fy": None
            };
            # In All overview, pin the big hubs so branches don't collapse together.
            if activeTab == "all" and (
                n.key == "root" or is_lens_key(n.key)
            ) {
                d["fx"] = sx;
                d["fy"] = sy;
            }
            by_id[n.id] = d;
            sim_nodes.append(d);
        }
        sim_links: list[any] = [];
        for e in edges {
            if e.source in by_id and e.target in by_id {
                sim_links.append(
                    {
                        "source": e.source,
                        "target": e.target,
                        "label": e.label
                    }
                );
            }
        }
        z_any0: any = zoomRef.current;
        z_spread: float = zoom_spread(
            float(z_any0) if z_any0 is not None else 1.0
        );
        link_f: any = (
            forceLink(sim_links)
            .id(lambda (d: any) -> str { return str(d["id"]); })
            .distance(
                FORCE_LINK_DIST
                * (1.45 if activeTab == "all" else 1.0)
                * z_spread
            )
            .strength(FORCE_LINK_STRENGTH)
        );
        charge_f: any = forceManyBody().strength(
            lambda (d: any) -> float {
                kind_v: any = d["kind"];
                depth_v: any = d["depth"];
                kind_s: str = str(kind_v) if kind_v else "";
                depth_i: int = int(depth_v) if depth_v is not None else 2;
                base: float = FORCE_CHARGE * z_spread;
                if activeTab == "all" {
                    base = FORCE_CHARGE * 1.55 * z_spread;
                }
                if kind_s == "lens" or depth_i == 0 {
                    return base * 1.8;
                }
                if kind_s == "place" or kind_s == "category" {
                    return base * 1.25;
                }
                return base;
            }
        );
        # Soft center when expanding — hard center yanks everything on click.
        center_strength: float = 0.008 if had_prev else (
            0.08 if activeTab == "all" else 0.18
        );
        center_f: any = forceCenter(VIEW_W / 2.0, VIEW_H / 2.0).strength(
            center_strength
        );
        collide_f: any = forceCollide().radius(
            lambda (d: any) -> float {
                depth_v: any = d["depth"];
                kind_v: any = d["kind"];
                depth_i: int = int(depth_v) if depth_v is not None else 2;
                kind_s: str = str(kind_v) if kind_v else "";
                return (
                    node_radius(depth_i, kind_s)
                    + (
                        18.0
                            if activeTab == "all"
                                and (kind_s == "lens" or depth_i <= 1)
                            else 8.0
                    )
                ) * z_spread;
            }
        ).strength(0.55 if had_prev else 0.75);
        boot_alpha: float = FORCE_ALPHA_SOFT if had_prev else FORCE_ALPHA;
        sim: any = (
            forceSimulation(sim_nodes)
            .force("link", link_f)
            .force("charge", charge_f)
            .force("center", center_f)
            .force("collide", collide_f)
            .velocityDecay(FORCE_VELOCITY_DECAY)
            .on("tick", lambda { schedule_layout_tick(); })
        );
        sim.alphaTarget(0.0).alpha(boot_alpha).restart();
        simRef.current = sim;
        simById.current = by_id;
        lastForceZoom.current = (
            float(zoomRef.current) if zoomRef.current is not None else 1.0
        );
        schedule_layout_tick();
    }

    # Rebuild force layout whenever the walker snapshot changes.
    useEffect(
        lambda {
            rebuild_simulation();
            return lambda { stop_simulation(); };
        },
        [nodes, edges]
    );

    def view_scale -> float {
        el = svgRef.current;
        if not el {
            return 1.0;
        }
        w = float(el.clientWidth) if el.clientWidth else VIEW_W;
        h = float(el.clientHeight) if el.clientHeight else VIEW_H;
        sx = w / VIEW_W;
        sy = h / VIEW_H;
        # SVG preserveAspectRatio slice ≈ cover = max(sx, sy)
        return sx if sx > sy else sy;
    }

    def client_to_graph(cx: float, cy: float) -> list[float] {
        el = svgRef.current;
        if not el {
            return [0.0, 0.0];
        }
        rect: any = el.getBoundingClientRect();
        s = view_scale();
        if s < 0.0001 {
            s = 1.0;
        }
        z_any: any = zoomRef.current;
        z: float = float(z_any) if z_any is not None else 1.0;
        if z < 0.0001 {
            z = 1.0;
        }
        ox = (float(rect.width) - VIEW_W * s) / 2.0;
        oy = (float(rect.height) - VIEW_H * s) / 2.0;
        svg_x = (cx - float(rect.left) - ox) / s;
        svg_y = (cy - float(rect.top) - oy) / s;
        p = panRef.current;
        px_any: any = p["x"];
        py_any: any = p["y"];
        return [
            (svg_x - float(px_any)) / z,
            (svg_y - float(py_any)) / z
        ];
    }

    def zoom_spread(z: float) -> float {
        # How much extra layout breathing room to give at this zoom.
        return 0.75 + z * ZOOM_SPREAD_GAIN;
    }

    def glyph_scale -> float {
        # Keep bubbles ~constant on screen while positions pull apart.
        z_any: any = zoomRef.current;
        z: float = float(z_any) if z_any is not None else 1.0;
        if z < 0.35 {
            z = 0.35;
        }
        return 1.0 / z;
    }

    def draw_radius(depth: int, kind: str) -> float {
        r = node_radius(depth, kind) * glyph_scale();
        if r < 4.0 {
            return 4.0;
        }
        return r;
    }

    def retune_forces_for_zoom(z: float) {
        sim: any = simRef.current;
        if not sim {
            return;
        }
        prev_z: any = lastForceZoom.current;
        pz: float = float(prev_z) if prev_z is not None else 1.0;
        if abs(z - pz) < 0.04 {
            return;
        }
        lastForceZoom.current = z;
        spread = zoom_spread(z);
        overview_m: float = 1.45 if activeTab == "all" else 1.0;
        try {
            link_f: any = sim.force("link");
            if link_f {
                link_f.distance(FORCE_LINK_DIST * overview_m * spread);
            }
            charge_f: any = sim.force("charge");
            if charge_f {
                charge_f.strength(
                    lambda (d: any) -> float {
                        kind_v: any = d["kind"];
                        depth_v: any = d["depth"];
                        kind_s: str = str(kind_v) if kind_v else "";
                        depth_i: int = (
                            int(depth_v) if depth_v is not None else 2
                        );
                        base: float = FORCE_CHARGE * spread;
                        if activeTab == "all" {
                            base = FORCE_CHARGE * 1.55 * spread;
                        }
                        if kind_s == "lens" or depth_i == 0 {
                            return base * 1.8;
                        }
                        if kind_s == "place" or kind_s == "category" {
                            return base * 1.25;
                        }
                        return base;
                    }
                );
            }
            collide_f: any = sim.force("collide");
            if collide_f {
                collide_f.radius(
                    lambda (d: any) -> float {
                        depth_v: any = d["depth"];
                        kind_v: any = d["kind"];
                        depth_i: int = (
                            int(depth_v) if depth_v is not None else 2
                        );
                        kind_s: str = str(kind_v) if kind_v else "";
                        pad: float = (
                            18.0
                                if activeTab == "all"
                                    and (kind_s == "lens" or depth_i <= 1)
                                else 10.0
                        );
                        return (node_radius(depth_i, kind_s) + pad) * spread;
                    }
                );
            }
            # Soft reopen — nodes drift apart instead of jumping.
            sim.alphaTarget(0.0).alpha(0.14).restart();
        } except Exception {
        }
        schedule_layout_tick();
    }

    def apply_zoom_at(cx: float, cy: float, next_z: float) {
        before = client_to_graph(cx, cy);
        nz = clamp_zoom(next_z);
        zoomRef.current = nz;
        zoom = nz;
        el = svgRef.current;
        if not el {
            retune_forces_for_zoom(nz);
            return;
        }
        rect: any = el.getBoundingClientRect();
        s = view_scale();
        if s < 0.0001 {
            s = 1.0;
        }
        ox = (float(rect.width) - VIEW_W * s) / 2.0;
        oy = (float(rect.height) - VIEW_H * s) / 2.0;
        svg_x = (cx - float(rect.left) - ox) / s;
        svg_y = (cy - float(rect.top) - oy) / s;
        nx = svg_x - before[0] * nz;
        ny = svg_y - before[1] * nz;
        panRef.current = {"x": nx, "y": ny};
        panX = nx;
        panY = ny;
        retune_forces_for_zoom(nz);
    }

    def pinch_distance(pts: any) -> float {
        keys: list[str] = [];
        try {
            keys = list(pts.keys());
        } except Exception {
            return 0.0;
        }
        if len(keys) < 2 {
            return 0.0;
        }
        a: any = pts[keys[0]];
        b: any = pts[keys[1]];
        dx: float = float(a["x"]) - float(b["x"]);
        dy: float = float(a["y"]) - float(b["y"]);
        return (Math.sqrt(dx * dx + dy * dy) as float);
    }

    def wheel_over_scroll_panel(e: any) -> bool {
        try {
            el: any = e.target;
            hops: int = 0;
            while el and hops < 48 {
                if el.getAttribute {
                    mark: any = el.getAttribute("data-scroll-panel");
                    if mark == "1" or mark == "true" {
                        return True;
                    }
                }
                el = el.parentElement;
                hops += 1;
            }
        } except Exception {
        }
        return False;
    }

    def on_wheel_zoom(e: any) {
        # Let dossier / search panels keep trackpad scroll.
        if wheel_over_scroll_panel(e) {
            return;
        }
        try {
            e.preventDefault();
        } except Exception {
        }
        dy: float = float(e.deltaY) if e.deltaY is not None else 0.0;
        factor: float = Math.exp(0.0 - dy * ZOOM_WHEEL_STEP) as float;
        z_now: any = zoomRef.current;
        apply_zoom_at(
            float(e.clientX),
            float(e.clientY),
            (float(z_now) if z_now is not None else 1.0) * factor
        );
    }

    # Non-passive wheel so trackpad zoom can prevent page scroll.
    useEffect(
        lambda {
            el_raw: any = canvasRef.current;
            if not el_raw {
                el_raw = svgRef.current;
            }
            if not el_raw {
                return lambda {};
            }
            handler: any = on_wheel_zoom;
            el_raw.addEventListener("wheel", handler, {"passive": False});
            return lambda {
                try {
                    el_raw.removeEventListener("wheel", handler);
                } except Exception {
                }
            };
        },
        [loading, nodes]
    );

    def zoom_by(factor: float) {
        el = svgRef.current;
        cx: float = 600.0;
        cy: float = 400.0;
        if el {
            try {
                rect: any = el.getBoundingClientRect();
                cx = float(rect.left) + float(rect.width) / 2.0;
                cy = float(rect.top) + float(rect.height) / 2.0;
            } except Exception {
            }
        }
        z_now: any = zoomRef.current;
        cur: float = float(z_now) if z_now is not None else 1.0;
        apply_zoom_at(cx, cy, cur * factor);
    }

    def live_xy(n: GNode) -> list[float] {
        # layoutTick keeps this reading fresh while the sim runs.
        _t: int = layoutTick;
        by_id: any = simById.current;
        if by_id {
            try {
                d: any = by_id[n.id];
                if d and d["x"] is not None and d["y"] is not None {
                    return [float(d["x"]), float(d["y"])];
                }
            } except Exception {
            }
        }
        return [n.x, n.y];
    }

    def end_node_drag {
        nd = nodeDrag.current;
        if not nd["active"] {
            return;
        }
        nid_any: any = nd["id"];
        nid: str = str(nid_any) if nid_any else "";
        by_id: any = simById.current;
        if by_id and nid {
            try {
                d: any = by_id[nid];
                if d {
                    d["fx"] = None;
                    d["fy"] = None;
                }
            } except Exception {
            }
        }
        sim: any = simRef.current;
        if sim {
            try {
                sim.alphaTarget(0.0);
            } except Exception {
            }
        }
        sess = dragSession.current;
        sess["suppressClick"] = bool(nd["didDrag"]);
        nd["active"] = False;
        nd["id"] = "";
        nd["didDrag"] = False;
        draggingNode = False;
        schedule_layout_tick();
    }

    def on_graph_pointer_down(e: MouseEvent) {
        if e.button != 0 {
            return;
        }
        nd = nodeDrag.current;
        if nd["active"] {
            return;
        }
        ev: any = e;
        pid: int = int(ev.pointerId) if ev.pointerId is not None else 0;
        pinch = pinchRef.current;
        pts: any = pinch["pts"];
        try {
            pts[str(pid)] = {"x": float(e.clientX), "y": float(e.clientY)};
            pinch["pts"] = pts;
        } except Exception {
        }
        # Two fingers → pinch zoom (cancel pan).
        try {
            if len(list(pts.keys())) >= 2 {
                pinch["active"] = True;
                pinch["startDist"] = pinch_distance(pts);
                z0: any = zoomRef.current;
                pinch["startZoom"] = float(z0) if z0 is not None else 1.0;
                sess0 = dragSession.current;
                sess0["active"] = False;
                dragging = False;
                return;
            }
        } except Exception {
        }
        # Don't start a pan when the press is on a node — otherwise
        # setPointerCapture steals the click and the dossier never opens.
        t: any = e.target;
        try {
            if t and t.closest {
                hit: any = t.closest("[data-node-id]");
                if hit {
                    return;
                }
            }
        } except Exception {
        }
        sess = dragSession.current;
        sess["active"] = True;
        sess["didPan"] = False;
        sess["lastX"] = float(e.clientX);
        sess["lastY"] = float(e.clientY);
        dragging = True;
        el = svgRef.current;
        if el and el.setPointerCapture and ev.pointerId is not None {
            el.setPointerCapture(ev.pointerId);
        }
    }

    def on_graph_pointer_move(e: MouseEvent) {
        ev: any = e;
        pid: int = int(ev.pointerId) if ev.pointerId is not None else 0;
        pinch = pinchRef.current;
        pts: any = pinch["pts"];
        try {
            if str(pid) in pts {
                pts[str(pid)] = {"x": float(e.clientX), "y": float(e.clientY)};
                pinch["pts"] = pts;
            }
        } except Exception {
        }
        if pinch["active"] {
            dist = pinch_distance(pts);
            sd_any: any = pinch["startDist"];
            start_d: float = float(sd_any) if sd_any is not None else 0.0;
            if start_d > 1.0 and dist > 1.0 {
                mid_x: float = float(e.clientX);
                mid_y: float = float(e.clientY);
                try {
                    keys = list(pts.keys());
                    if len(keys) >= 2 {
                        a: any = pts[keys[0]];
                        b: any = pts[keys[1]];
                        mid_x = (float(a["x"]) + float(b["x"])) / 2.0;
                        mid_y = (float(a["y"]) + float(b["y"])) / 2.0;
                    }
                } except Exception {
                }
                sz_any: any = pinch["startZoom"];
                sz: float = float(sz_any) if sz_any is not None else 1.0;
                apply_zoom_at(mid_x, mid_y, sz * (dist / start_d));
            }
            return;
        }
        if nodeDrag.current["active"] {
            return;
        }
        sess = dragSession.current;
        if not sess["active"] {
            return;
        }
        last_x: any = sess["lastX"];
        last_y: any = sess["lastY"];
        dx = float(e.clientX) - float(last_x);
        dy = float(e.clientY) - float(last_y);
        if abs(dx) > 4.0 or abs(dy) > 4.0 {
            sess["didPan"] = True;
        }
        s = view_scale();
        if s < 0.0001 {
            s = 1.0;
        }
        z_any: any = zoomRef.current;
        z: float = float(z_any) if z_any is not None else 1.0;
        if z < 0.0001 {
            z = 1.0;
        }
        p = panRef.current;
        px_any: any = p["x"];
        py_any: any = p["y"];
        nx = float(px_any) + ((dx / (s * z)) * PAN_GAIN);
        ny = float(py_any) + ((dy / (s * z)) * PAN_GAIN);
        p["x"] = nx;
        p["y"] = ny;
        panX = nx;
        panY = ny;
        sess["lastX"] = float(e.clientX);
        sess["lastY"] = float(e.clientY);
    }

    def on_graph_pointer_up(e: MouseEvent) {
        ev2: any = e;
        pid: int = int(ev2.pointerId) if ev2.pointerId is not None else 0;
        pinch = pinchRef.current;
        pts: any = pinch["pts"];
        try {
            if str(pid) in pts {
                nxt: dict[str, any] = {};
                for k in list(pts.keys()) {
                    if k != str(pid) {
                        nxt[k] = pts[k];
                    }
                }
                pinch["pts"] = nxt;
                pts = nxt;
            }
            if len(list(pts.keys())) < 2 {
                pinch["active"] = False;
                pinch["startDist"] = 0.0;
            }
        } except Exception {
        }
        if nodeDrag.current["active"] {
            end_node_drag();
            return;
        }
        if pinch["active"] {
            return;
        }
        sess = dragSession.current;
        # Swallow only the click that ends a pan; clear so later clicks work.
        sess["suppressClick"] = bool(sess["didPan"]);
        sess["active"] = False;
        sess["didPan"] = False;
        dragging = False;
        el = svgRef.current;
        if el and el.releasePointerCapture and ev2.pointerId is not None {
            try {
                el.releasePointerCapture(ev2.pointerId);
            } except Exception {
            }
        }
    }

    async def fetch_search(q: str) -> any {
        res = root spawn SearchArchive(query=q);
        return res;
    }

    async def fetch_dossier(id: str) -> any {
        res = root spawn GetDossier(node_id=id);
        return res;
    }

    def clear_dossier_cache {
        dossierCache.current = {};
        dossierPending.current = {};
        idlePrefetchQueue.current = [];
        if idlePrefetchTimer.current {
            clearTimeout(idlePrefetchTimer.current);
            idlePrefetchTimer.current = None;
        }
    }

    async def fetch_and_cache_dossier(id: str) -> any {
        cache: dict[str, any] = dossierCache.current as dict[str, any];
        if id in cache {
            return cache[id];
        }
        pend: dict[str, any] = dossierPending.current as dict[str, any];
        pending: any = pend[id] if id in pend else None;
        if not pending {
            pending = with_timeout(fetch_dossier(id), None);
            pend[id] = pending;
        }
        res: any = None;
        try {
            res = await pending;
        } except Exception {
            res = None;
        }
        pend[id] = None;
        d: any = None;
        if res is not None and res.reports and len(res.reports) > 0 {
            d = res.reports[0];
        }
        if d {
            cache[id] = d;
        }
        return d;
    }

    def queue_idle_dossier_prefetch {
        # Opportunistic only: visible leaf nodes, one at a time, never while loading.
        cache: dict[str, any] = dossierCache.current as dict[str, any];
        seen: dict[str, bool] = {};
        q: list[str] = [];
        for n in nodes {
            if not is_leaf_kind(n.kind) {
                continue;
            }
            if n.id in cache or n.id in seen {
                continue;
            }
            seen[n.id] = True;
            q = q + [n.id];
            if len(q) >= 6 {
                break;
            }
        }
        idlePrefetchQueue.current = q;
        if idlePrefetchTimer.current {
            return;
        }
        idlePrefetchTimer.current = setTimeout(
            lambda {
                run_idle_dossier_prefetch();
            },
            1200
        );
    }

    async def run_idle_dossier_prefetch {
        idlePrefetchTimer.current = None;
        if loading or int(browseInflight.current) > 0 {
            idlePrefetchTimer.current = setTimeout(
                lambda {
                    run_idle_dossier_prefetch();
                },
                1500
            );
            return;
        }
        w: any = window;
        if w.document and w.document.hidden {
            return;
        }
        q: list[str] = idlePrefetchQueue.current as list[str];
        if len(q) == 0 {
            return;
        }
        nid: str = q[0];
        idlePrefetchQueue.current = q[1:];
        try {
            await fetch_and_cache_dossier(nid);
        } except Exception {
            _ = None;
        }
        if len(idlePrefetchQueue.current as list[str]) > 0 and not loading {
            idlePrefetchTimer.current = setTimeout(
                lambda {
                    run_idle_dossier_prefetch();
                },
                900
            );
        }
    }

    async def run_search(q: str) {
        query = q;
        if not q.strip() {
            results = [];
            searched = "";
            return;
        }
        w: any = window;
        req: int = (w.__pulseSearchReq or 0) + 1;
        w.__pulseSearchReq = req;
        res: any = None;
        try {
            res = await with_timeout(fetch_search(q), None);
        } except Exception {
            res = None;
        }
        if w.__pulseSearchReq != req or res is None {
            return;    # superseded by newer typing, or the server is slow
        }
        results = res.reports[0] if res.reports and len(res.reports) > 0 else [];
        searched = q;
    }

    async def open_dossier(id: str) {
        selectedId = id;
        sidebarTab = "detail";
        cache: dict[str, any] = dossierCache.current as dict[str, any];
        if id in cache {
            selected = cache[id];
            return;
        }
        selected = None;
        d: any = await fetch_and_cache_dossier(id);
        if selectedId != id {
            return;
        }
        selected = d;
        if selected is None {
            selectedId = "";
            sidebarTab = "here";
        }
    }

    def select_node(id: str) {
        sess = dragSession.current;
        if sess["suppressClick"] {
            sess["suppressClick"] = False;
            return;
        }
        found_key: str = "";
        found_name: str = "";
        found_id: str = "";
        found_kind: str = "";
        found_sub: str = "";
        found_exp: bool = False;
        matched: bool = False;
        for n in nodes {
            if n.id == id or n.key == id {
                found_key = n.key;
                found_name = n.name;
                found_id = n.id;
                found_kind = n.kind;
                found_sub = n.sub;
                found_exp = n.expandable;
                matched = True;
            }
        }
        if not matched {
            open_dossier(id);
            return;
        }
        # Leaves open the dossier; expandable nodes accumulate into the graph.
        if (not found_exp) or is_leaf_kind(found_kind) {
            if found_kind == "lens" and found_sub == "root" {
                set_focus("root", "Ann Arbor");
                return;
            }
            open_dossier(found_id);
            return;
        }
        if key_in_expanded(found_key) {
            set_focus(found_key, found_name);
            if expandAll {
                open_all_connections(found_key);
            }
            return;
        }
        drill_to(found_key, found_name);
    }

    def close_dossier {
        selected = None;
        selectedId = "";
        sidebarTab = "here";
    }

    def set_focus(key: str, name: str) {
        focusKeyRef.current = key;
        cut: int = -1;
        i: int = 0;
        for step in trail {
            if str(step["key"]) == key {
                cut = i;
            }
            i += 1;
        }
        if cut >= 0 {
            trail = trail[: cut + 1];
        } elif key != "root" {
            trail = trail + [{"key": key, "name": name}];
        } else {
            trail = [{"key": "root", "name": "Ann Arbor"}];
        }
        focusKey = key;
        focusName = name;
        selected = None;
        selectedId = "";
        sidebarTab = "here";
        results = [];
        query = "";
    }

    async def drill_to(key: str, name: str) {
        set_focus(key, name);
        if expandAll {
            await open_all_connections(key);
        } elif key != "root" and not key_in_expanded(key) {
            await expand_into(key);
        }
    }

    def go_trail(index: int) {
        if index < 0 or index >= len(trail) {
            return;
        }
        step = trail[index];
        sk: str = str(step["key"]);
        sn: str = str(step["name"]);
        if sk == "root" or sk == "all" {
            if activeTab != "all" {
                switch_tab("all", "All");
            } else {
                set_focus("root", "Ann Arbor");
                trail = [{"key": "root", "name": "All"}];
            }
            return;
        }
        if is_lens_key(sk) and activeTab != sk {
            switch_tab(sk, sn);
            return;
        }
        # Keep the graph; only move the highlight.
        focusKeyRef.current = sk;
        focusKey = sk;
        focusName = sn;
        selected = None;
        selectedId = "";
        sidebarTab = "here";
    }

    def go_root {
        focusKeyRef.current = "root";
        trail = [{"key": "root", "name": "All"}];
        focusKey = "root";
        focusName = "Ann Arbor";
        activeTab = "all";
        selected = None;
        selectedId = "";
        sidebarTab = "here";
        results = [];
        query = "";
        reset_camera();
        load_overview();
    }

    # Capture id outside the SVG loop so Jac/JS doesn't share one closure.
    def bind_node_click(nid: str) -> Callable[[MouseEvent], None] {
        captured: str = nid;
        return lambda (e: MouseEvent) {
            e.stopPropagation();
            select_node(captured);
        };
    }

    def bind_node_pointer_down(nid: str) -> Callable[[MouseEvent], None] {
        captured: str = nid;
        return lambda (e: MouseEvent) {
            e.stopPropagation();
            if e.button != 0 {
                return;
            }
            nd = nodeDrag.current;
            nd["active"] = True;
            nd["id"] = captured;
            nd["didDrag"] = False;
            nd["startX"] = float(e.clientX);
            nd["startY"] = float(e.clientY);
            # Don't pin / restart force until the pointer actually moves —
            # otherwise a normal click yanks the whole graph.

            def on_win_move(ev: any) {
                cur = nodeDrag.current;
                if not cur["active"] {
                    return;
                }
                move_id: str = str(cur["id"]) if cur["id"] else "";
                sx_any: any = cur["startX"];
                sy_any: any = cur["startY"];
                dx: float = float(ev.clientX) - float(sx_any if sx_any is not None else 0.0);
                dy: float = float(ev.clientY) - float(sy_any if sy_any is not None else 0.0);
                if not cur["didDrag"] {
                    if abs(dx) < FORCE_DRAG_THRESHOLD and abs(dy) < FORCE_DRAG_THRESHOLD {
                        return;
                    }
                    cur["didDrag"] = True;
                    draggingNode = True;
                    move_pt0 = client_to_graph(float(ev.clientX), float(ev.clientY));
                    live0: any = simById.current;
                    if live0 and move_id {
                        try {
                            node0: any = live0[move_id];
                            if node0 {
                                node0["fx"] = move_pt0[0];
                                node0["fy"] = move_pt0[1];
                            }
                        } except Exception {
                        }
                    }
                    sim0: any = simRef.current;
                    if sim0 {
                        try {
                            sim0.alphaTarget(FORCE_DRAG_ALPHA).restart();
                        } except Exception {
                        }
                    }
                }
                move_pt = client_to_graph(float(ev.clientX), float(ev.clientY));
                live: any = simById.current;
                if live and move_id {
                    try {
                        node_d: any = live[move_id];
                        if node_d {
                            node_d["fx"] = move_pt[0];
                            node_d["fy"] = move_pt[1];
                        }
                    } except Exception {
                    }
                }
                schedule_layout_tick();
            }

            def on_win_up(ev: any) {
                window.removeEventListener("pointermove", on_win_move);
                window.removeEventListener("pointerup", on_win_up);
                window.removeEventListener("pointercancel", on_win_up);
                end_node_drag();
            }

            window.addEventListener("pointermove", on_win_move);
            window.addEventListener("pointerup", on_win_up);
            window.addEventListener("pointercancel", on_win_up);
        };
    }

    def bind_node_dblclick(nkey: str, nname: str) -> Callable[[MouseEvent], None] {
        ck: str = nkey;
        cn: str = nname;
        return lambda (e: MouseEvent) {
            e.stopPropagation();
            sess = dragSession.current;
            if not sess["didPan"] {
                drill_to(ck, cn);
            }
        };
    }

    async def warm_photos(nid: str, pc: any) {
        try {
            m: DossierMedia = await dossier_images(nid);
            if m and m.images and len(m.images) > 0 {
                pc[nid] = m.images;
            }
        } except Exception {
            _ = None;
        }
    }

    def warm_node(nid: str) {
        # Hover intent: start the dossier + photo fetch before the click lands.
        fetch_and_cache_dossier(nid);
        w: any = window;
        pc: any = w.__pulsePhotoCache;
        if not pc {
            pc = {};
            w.__pulsePhotoCache = pc;
        }
        warm: any = w.__pulsePhotoWarm;
        if not warm {
            warm = {};
            w.__pulsePhotoWarm = warm;
        }
        if nid in pc or nid in warm {
            return;
        }
        warm[nid] = True;
        warm_photos(nid, pc);
    }

    def bind_node_enter(nid: str) -> Callable[[MouseEvent], None] {
        captured: str = nid;
        return lambda (e: MouseEvent) {
            hoverId = captured;
            warm_node(captured);
        };
    }

    def bind_node_leave -> Callable[[MouseEvent], None] {
        return lambda (e: MouseEvent) { hoverId = ""; };
    }

    def bind_trail_click(idx: int) -> Callable[[MouseEvent], None] {
        captured: int = idx;
        return lambda (e: MouseEvent) { go_trail(captured); };
    }

    def recenter(key: str, name: str) {
        drill_to(key, name);
    }

    def bind_lens_starter(key: str, name: str) -> Callable[[MouseEvent], None] {
        ck: str = key;
        cn: str = name;
        return lambda (e: MouseEvent) {
            switch_tab(ck, cn);
        };
    }

    def bind_search_pick(g: GNode) -> Callable[[MouseEvent], None] {
        captured: GNode = g;
        return lambda (e: MouseEvent) { pick_search(captured); };
    }

    def pick_search(r: GNode) {
        results = [];
        query = "";
        if r.expandable and not is_leaf_kind(r.kind) {
            if key_in_expanded(r.key) {
                set_focus(r.key, r.name);
            } else {
                drill_to(r.key, r.name);
            }
        } else {
            open_dossier(r.id);
        }
    }

    def open_from_dossier(id: str) {
        # Prefer drilling when the linked node is on-screen and expandable.
        for n in nodes {
            if n.id == id or n.key == id {
                select_node(n.id);
                return;
            }
        }
        open_dossier(id);
    }

    def set_day_filter(iso: str) {
        nxt = {** filters};
        nxt["date"] = iso;
        onFilters(nxt);
    }

    def on_day_select(v: str) {
        if not v or v == "any" {
            set_day_filter("");
        } else {
            set_day_filter(v);
        }
    }

    async def submit_community_event {
        if postBusy {
            return;
        }
        postBusy = True;
        postMsg = "";
        try {
            res: dict = await create_community_event(
                postName,
                postWhen,
                postDesc,
                postCat,
                postBy if postBy else "Neighbor",
                postDate,
                0.0
            );
            if res.get("ok") {
                postMsg = "Posted — open your topic under Posted.";
                postName = "";
                postWhen = "";
                postDesc = "";
                showPost = False;
                await switch_tab("lens-community", "Posted");
            } else {
                postMsg = str(res.get("error") or "Could not post that event.");
            }
        } except Exception {
            postMsg = "Could not post that event.";
        }
        postBusy = False;
    }

    dateChips: list[dict] = future_date_chips(14);
    selectedDate: str = filters["date"] or "";
    dayValue: str = selectedDate if selectedDate else "any";

    pos: dict[str, GNode] = {};
    for n in nodes {
        pos[n.id] = n;
    }
    focus = hoverId or selectedId;

    return
        <div className="relative flex flex-1 flex-col lg:h-[calc(100svh-57px)] lg:flex-row lg:overflow-hidden">
            {#* ---------------- graph canvas ---------------- *#}
            <div
                ref={canvasRef}
                className="relative min-h-[70svh] flex-1 overflow-hidden paper-grain lg:h-auto lg:min-h-0 lg:self-stretch"
            >
                {loading
                    and len(nodes) == 0
                    and <div
                        className="absolute inset-0 flex items-center justify-center"
                    >
                        <div className="flex flex-col items-center gap-3">
                            <Skeleton className="size-24 rounded-full"/>
                            <span className="kicker text-muted-foreground">
                                {"Walking the graph..."}
                            </span>
                        </div>
                    </div>}
                {error
                    and <div
                        className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3"
                        role="alert"
                    >
                        <p className="text-sm text-destructive">{error}</p>
                        <Button
                            variant="outline"
                            size="sm"
                            onClick={lambda (e: MouseEvent) { load_root(); }}
                        >
                            {"Retry"}
                        </Button>
                    </div>}
                {not loading
                    and not error
                    and activeTab != "lens-community"
                    and len(nodes) <= 1
                    and <div
                        className="absolute inset-0 z-10 flex items-center justify-center pl-6 pr-6"
                    >
                        <div
                            className="max-w-sm rounded-xl border bg-card pt-6 pb-6 pl-6 pr-6 text-center shadow-sm"
                        >
                            <div
                                className="mx-auto mb-3 flex size-10 items-center justify-center bg-primary/10 text-primary"
                            >
                                <HugeiconsIcon
                                    icon={Analytics01Icon}
                                    strokeWidth={2}
                                    className="size-5"
                                />
                            </div>
                            <h3 className="font-display text-xl font-bold">
                                {"Nothing matches this walk"}
                            </h3>
                            <p className="mt-1 text-sm text-muted-foreground">
                                {"Loosen a filter or pick something else to explore."}
                            </p>
                            <Button
                                className="mt-4"
                                size="sm"
                                onClick={lambda (e: MouseEvent) { onFilters(
                                    default_filters()
                                ); }}
                            >
                                {"Clear filters"}
                            </Button>
                        </div>
                    </div>}
                <svg
                    ref={svgRef}
                    viewBox="0 0 1200 800"
                    preserveAspectRatio="xMidYMid slice"
                    className={"absolute inset-0 size-full touch-none select-none transition-opacity duration-500 "
                        + ("opacity-50" if loading else "opacity-100 ")
                        + (
                            "cursor-grabbing"
                                if dragging or draggingNode
                                else "cursor-grab"
                        )}
                    onPointerDown={on_graph_pointer_down}
                    onPointerMove={on_graph_pointer_move}
                    onPointerUp={on_graph_pointer_up}
                    onPointerLeave={on_graph_pointer_up}
                    onPointerCancel={on_graph_pointer_up}
                >
                    <g
                        transform={f"translate({panX},{panY}) scale({zoom})"}
                        data-tick={str(layoutTick)}
                    >
                        {for e in edges {
                            if e.source in pos and e.target in pos {
                                a = live_xy(pos[e.source]);
                                b = live_xy(pos[e.target]);
                                eop = edge_dim(e.source, e.target);
                                <line
                                    key={e.source + e.target}
                                    x1={a[0]}
                                    y1={a[1]}
                                    x2={b[0]}
                                    y2={b[1]}
                                    stroke={(
                                        ("#fafaf9" if dark else "#1c1917")
                                            if eop > 0.5
                                            else ("#78716c" if dark else "#a8a29e")
                                    )}
                                    strokeOpacity={eop}
                                    strokeWidth={(
                                        (1.6 if eop > 0.5 else 0.85)
                                        * glyph_scale()
                                    )}
                                />
                            }
                        }}
                        {for n in nodes {
                            xy = live_xy(n);
                            nop = node_dim(n);
                            is_focus = n.key == focusKey or n.id == selectedId;
                            gs = glyph_scale();
                            <g
                                key={n.id}
                                data-node-id={n.id}
                                transform={f"translate({xy[0]},{xy[1]})"}
                                className="cursor-pointer"
                                opacity={nop}
                                onPointerDown={bind_node_pointer_down(n.id)}
                                onClick={bind_node_click(n.id)}
                                onDoubleClick={bind_node_dblclick(n.key, n.name)}
                                onMouseEnter={bind_node_enter(n.id)}
                                onMouseLeave={bind_node_leave()}
                            >
                                {if is_focus {
                                    <circle
                                        r={draw_radius(n.depth, n.kind) + 10.0 * gs}
                                        fill="none"
                                        stroke={(
                                            "#a8a29e"
                                                if n.kind == "lens"
                                                else node_fill_color(n.kind, n.sub)
                                        )}
                                        strokeWidth={1.5 * gs}
                                        strokeDasharray="3 4"
                                    />
                                }}
                                <circle
                                    r={draw_radius(n.depth, n.kind)}
                                    fill={node_fill_color(n.kind, n.sub)}
                                    fillOpacity={1.0}
                                    stroke={(
                                        "#292524"
                                            if n.kind == "lens"
                                            else (
                                                ("#fafaf9" if dark else "#1c1917")
                                                if is_focus
                                                else ("#1c1917" if dark else "#ffffff")
                                            )
                                    )}
                                    strokeWidth={(
                                        (3.0 if is_focus else 2.0) * gs
                                    )}
                                />
                                <text
                                    y={(
                                        (
                                            40.0
                                                if is_focus
                                                else (
                                                    26.0 if n.depth <= 1 else 20.0
                                                )
                                        )
                                        * gs
                                    )}
                                    textAnchor="middle"
                                    fontFamily="Geist Variable, system-ui, sans-serif"
                                    fontWeight={(600 if is_focus else 500)}
                                    fontSize={(
                                        (
                                            16.0
                                                if is_focus
                                                else (
                                                    13.0 if n.depth <= 1 else 11.0
                                                )
                                        )
                                        * gs
                                    )}
                                    fill={(
                                        ("#fafaf9" if dark else "#1c1917")
                                        if nop > 0.4
                                        else ("#a8a29e" if dark else "#78716c")
                                    )}
                                    stroke={("#1c1917" if dark else "#ffffff")}
                                    strokeWidth={4.0 * gs}
                                    paintOrder="stroke"
                                >
                                    {(
                                        n.name
                                        if len(n.name) < 28
                                        else n.name[:26] + "..."
                                    )}
                                </text>
                            </g>
                        }}
                    </g>
                </svg>
                {#* editorial overlay, like a front page headline *#}
                <div
                    className="pointer-events-none relative z-10 flex flex-col gap-3 pt-6 pb-6 pl-5 pr-5 sm:pl-8 lg:max-w-md"
                >
                    <h2 className="text-2xl font-semibold tracking-tight">
                        {"Explore Ann Arbor"}
                    </h2>
                    <p className="text-sm text-muted-foreground">
                        {"All shows every branch. Places, Topics, Hosts, and City isolate one. Pinch in to spread nodes apart · drag to pan."}
                    </p>
                    <div className="pointer-events-auto flex flex-col gap-2">
                        <div className="relative max-w-md">
                            <HugeiconsIcon
                                icon={Search01Icon}
                                strokeWidth={2}
                                className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                            />
                            <Input
                                value={query}
                                onChange={lambda (e: ChangeEvent) { run_search(
                                    e.target.value
                                ); }}
                                placeholder="Search a club, venue, category or closure"
                                className="h-10 bg-card pl-9 shadow-sm"
                            />
                            {len(results) == 0
                                and query.strip()
                                and searched == query
                                and <div
                                    className="absolute left-0 right-0 top-11 z-30 flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-3 pr-3 shadow-lg"
                                    role="status"
                                >
                                    <p className="text-sm">
                                        {"No matches for “" + query.strip() + "”. Browse by place, topic, host or city instead:"}
                                    </p>
                                    <div className="flex flex-wrap gap-1.5">
                                        {for s in LENS_STARTERS[1:] {
                                            <button
                                                key={"none-" + s["key"]}
                                                type="button"
                                                onClick={bind_lens_starter(str(s["key"]), str(s["name"]))}
                                                className="rounded-full border bg-background pt-1 pb-1 pl-3 pr-3 text-xs font-medium text-muted-foreground hover:text-foreground"
                                            >
                                                {s["name"]}
                                            </button>
                                        }}
                                    </div>
                                </div>}
                            {len(results) > 0
                                and <div
                                    data-scroll-panel="1"
                                    className="absolute left-0 right-0 top-11 z-30 max-h-72 overflow-y-auto overscroll-contain rounded-lg border bg-card shadow-lg"
                                >
                                    {for r in results {
                                        <button
                                            key={r.id}
                                            type="button"
                                            onClick={bind_search_pick(r)}
                                            className="flex w-full items-center gap-3 border-b pt-2 pb-2 pl-3 pr-3 text-left last:border-b-0 hover:bg-muted"
                                        >
                                            <span
                                                className="size-2.5 shrink-0 rounded-full"
                                                style={{
                                                    "backgroundColor": kind_color(
                                                        r.kind
                                                    )
                                                }}
                                            />
                                            <span
                                                className="flex-1 truncate text-sm font-medium capitalize"
                                            >
                                                {r.name}
                                            </span>
                                            <span
                                                className="kicker text-muted-foreground"
                                            >
                                                {kind_label(r.kind)}
                                            </span>
                                        </button>
                                    }}
                                </div>}
                        </div>
                        <div className="flex flex-wrap gap-1.5">
                            {for s in LENS_STARTERS {
                                <button
                                    key={s["key"]}
                                    type="button"
                                    onClick={bind_lens_starter(str(s["key"]), str(s["name"]))}
                                    className={"rounded-full border pt-1 pb-1 pl-3 pr-3 text-xs font-medium transition-colors "
                                        + (
                                            "border-foreground bg-foreground text-background"
                                                if activeTab == s["key"]
                                                else "bg-card text-muted-foreground hover:text-foreground"
                                        )}
                                >
                                    {s["name"]}
                                </button>
                            }}
                        </div>
                        <div className="mt-2 flex flex-wrap items-center gap-3">
                            <div className="flex items-center gap-2">
                                <span className="kicker shrink-0 text-muted-foreground">
                                    {"Day"}
                                </span>
                                <Select
                                    value={dayValue}
                                    onValueChange={lambda (v: str) { on_day_select(v); }}
                                >
                                    <SelectTrigger
                                        className="h-8 w-[9.5rem] bg-card text-xs"
                                        aria-label="Filter by day"
                                        size="sm"
                                    >
                                        <SelectValue placeholder="Any day"/>
                                    </SelectTrigger>
                                    <SelectContent position="popper" align="start">
                                        <SelectItem value="any">{"Any day"}</SelectItem>
                                        {for chip in dateChips {
                                            <SelectItem
                                                key={chip["iso"]}
                                                value={str(chip["iso"])}
                                            >
                                                {str(chip["label"])}
                                            </SelectItem>
                                        }}
                                    </SelectContent>
                                </Select>
                            </div>
                            <label
                                className="flex items-center gap-2 text-xs text-muted-foreground"
                            >
                                <Switch
                                    checked={expandAll}
                                    disabled={loading or focusKey == "root"}
                                    onCheckedChange={lambda (on: bool) {
                                        set_expand_all(on);
                                    }}
                                    aria-label="Open all connections"
                                    size="sm"
                                />
                                <span>
                                    {(
                                        "All connections"
                                            if expandAll
                                            else "Open all"
                                    )}
                                </span>
                            </label>
                            {activeTab == "lens-community"
                                and <Button
                                    type="button"
                                    size="sm"
                                    variant="outline"
                                    className="h-8 text-xs"
                                    onClick={lambda (e: MouseEvent) {
                                        showPost = not showPost;
                                    }}
                                >
                                    {"Post an event"}
                                </Button>}
                        </div>
                        {activeTab == "lens-community"
                            and showPost
                            and <div
                                className="mt-2 flex max-w-md flex-col gap-2 rounded-lg border bg-card/95 pt-3 pb-3 pl-3 pr-3 shadow-sm"
                            >
                                <span className="kicker text-muted-foreground">
                                    {"Share something for everyone"}
                                </span>
                                <Input
                                    value={postName}
                                    onChange={lambda (e: ChangeEvent) {
                                        postName = e.target.value;
                                    }}
                                    placeholder="Event name"
                                    className="h-8 text-sm"
                                />
                                <Input
                                    value={postWhen}
                                    onChange={lambda (e: ChangeEvent) {
                                        postWhen = e.target.value;
                                    }}
                                    placeholder="When (e.g. Sat 7pm · Kerrytown)"
                                    className="h-8 text-sm"
                                />
                                <Input
                                    value={postDesc}
                                    onChange={lambda (e: ChangeEvent) {
                                        postDesc = e.target.value;
                                    }}
                                    placeholder="Short description"
                                    className="h-8 text-sm"
                                />
                                <div className="flex flex-wrap gap-2">
                                    <Input
                                        value={postBy}
                                        onChange={lambda (e: ChangeEvent) {
                                            postBy = e.target.value;
                                        }}
                                        placeholder="Your name"
                                        className="h-8 min-w-[8rem] flex-1 text-sm"
                                    />
                                    <Select
                                        value={postCat}
                                        onValueChange={lambda (v: str) {
                                            if v {
                                                postCat = v;
                                            }
                                        }}
                                    >
                                        <SelectTrigger className="h-8 w-[8.5rem] text-xs" size="sm">
                                            <SelectValue placeholder="Topic"/>
                                        </SelectTrigger>
                                        <SelectContent>
                                            {for c in all_categories() {
                                                <SelectItem key={c} value={c}>
                                                    {c}
                                                </SelectItem>
                                            }}
                                        </SelectContent>
                                    </Select>
                                </div>
                                <div className="flex items-center gap-2">
                                    <Button
                                        type="button"
                                        size="sm"
                                        disabled={postBusy or not postName.strip()}
                                        onClick={lambda (e: MouseEvent) {
                                            submit_community_event();
                                        }}
                                    >
                                        {"Posting…" if postBusy else "Publish"}
                                    </Button>
                                    <Button
                                        type="button"
                                        size="sm"
                                        variant="ghost"
                                        onClick={lambda (e: MouseEvent) {
                                            showPost = False;
                                        }}
                                    >
                                        {"Cancel"}
                                    </Button>
                                </div>
                                {postMsg
                                    and <p className="text-[11px] text-muted-foreground">
                                        {postMsg}
                                    </p>}
                            </div>}
                    </div>
                </div>
                {#* zoom controls *#}
                <div
                    className="absolute bottom-4 right-4 z-10 flex flex-col overflow-hidden rounded-lg border bg-card/95 shadow-sm backdrop-blur"
                >
                    <button
                        type="button"
                        aria-label="Zoom in"
                        onClick={lambda (e: MouseEvent) { zoom_by(1.2); }}
                        className="px-3 py-2 text-sm font-semibold text-foreground hover:bg-muted"
                    >
                        {"+"}
                    </button>
                    <button
                        type="button"
                        aria-label="Reset zoom"
                        onClick={lambda (e: MouseEvent) { reset_camera(); }}
                        className="border-t border-b px-3 py-1.5 text-[10px] font-medium tabular-nums text-muted-foreground hover:bg-muted"
                    >
                        {f"{zoom * 100.0:.0f}%"}
                    </button>
                    <button
                        type="button"
                        aria-label="Zoom out"
                        onClick={lambda (e: MouseEvent) { zoom_by(0.83); }}
                        className="px-3 py-2 text-sm font-semibold text-foreground hover:bg-muted"
                    >
                        {"−"}
                    </button>
                </div>
                {#* legend + stats, bottom-left *#}
                <div
                    className="absolute bottom-4 left-4 z-10 flex flex-wrap items-center gap-3 rounded-lg border bg-card/90 pt-2 pb-2 pl-3 pr-3 backdrop-blur sm:left-8"
                >
                    {for k in LEGEND {
                        <span
                            key={k}
                            className="kicker flex items-center gap-1.5 text-muted-foreground"
                        >
                            <span
                                className="size-2.5 rounded-full"
                                style={{"backgroundColor": kind_color(k)}}
                            />
                            {kind_label(k)}
                        </span>
                    }}
                    <span className="kicker border-l pl-3 tabular-nums text-foreground">
                        {f"{len(nodes)} nodes · {len(edges)} ties"}
                    </span>
                </div>
            </div>
            {#* ---------------- side column: here + detail tabs ---------------- *#}
            <aside
                data-scroll-panel="1"
                className="relative z-20 flex w-full flex-col gap-5 overflow-y-auto overscroll-contain border-t bg-background pt-6 pb-6 pl-6 pr-6 lg:h-[calc(100svh-57px)] lg:w-[360px] lg:shrink-0 lg:self-stretch lg:border-l lg:border-t-0"
            >
                {selectedId != ""
                    and <div
                        className="flex items-center gap-1 border-b border-border pb-3"
                        role="tablist"
                        aria-label="Sidebar panels"
                    >
                        <button
                            type="button"
                            role="tab"
                            aria-selected={sidebarTab == "here"}
                            onClick={lambda (e: MouseEvent) { sidebarTab = "here"; }}
                            className={(
                                "rounded-md pt-1.5 pb-1.5 pl-3 pr-3 text-xs font-medium transition-colors "
                                + (
                                    "bg-foreground text-background"
                                        if sidebarTab == "here"
                                        else "text-muted-foreground hover:bg-muted hover:text-foreground"
                                )
                            )}
                        >
                            {"Here"}
                        </button>
                        <button
                            type="button"
                            role="tab"
                            aria-selected={sidebarTab == "detail"}
                            onClick={lambda (e: MouseEvent) { sidebarTab = "detail"; }}
                            className={(
                                "min-w-0 flex-1 truncate rounded-md pt-1.5 pb-1.5 pl-3 pr-3 text-left text-xs font-medium transition-colors "
                                + (
                                    "bg-foreground text-background"
                                        if sidebarTab == "detail"
                                        else "text-muted-foreground hover:bg-muted hover:text-foreground"
                                )
                            )}
                        >
                            {(
                                selected.name
                                    if selected is not None
                                    else "Detail"
                            )}
                        </button>
                    </div>}
                {sidebarTab == "detail"
                    and selectedId != ""
                    and <div className="flex flex-col gap-4">
                        {selected is not None
                            and <DossierPanel
                                dossier={selected}
                                onClose={close_dossier}
                                onOpenNode={open_from_dossier}
                                onCenter={recenter}
                            />}
                        {selected is None
                            and <div className="flex flex-col gap-3">
                                <Skeleton className="h-4 w-20"/>
                                <Skeleton className="h-8 w-48"/>
                                <Skeleton className="h-40 w-full rounded-xl"/>
                                <Skeleton className="h-16 w-full"/>
                            </div>}
                    </div>}
                {(sidebarTab != "detail" or selectedId == "")
                    and <div className="flex flex-col gap-5">
                        <div className="flex flex-col gap-3">
                            <div className="flex items-baseline justify-between">
                                <span className="kicker text-muted-foreground">
                                    {"You are here"}
                                </span>
                                {focusKey != "root"
                                    and <button
                                        type="button"
                                        onClick={lambda (e: MouseEvent) { go_root(); }}
                                        className="kicker inline-flex items-center gap-1 text-primary hover:underline"
                                    >
                                        <HugeiconsIcon
                                            icon={ArrowLeft01Icon}
                                            strokeWidth={2}
                                            className="size-3.5"
                                        />
                                        {"Root"}
                                    </button>}
                            </div>
                            <h3 className="font-display text-2xl font-bold leading-tight">
                                {focusName}
                            </h3>
                            <nav
                                className="flex flex-wrap items-center gap-1 text-xs"
                                aria-label="Browse path"
                            >
                                {for (i, step) in enumerate(trail) {
                                    <span key={str(step["key"]) + str(i)} className="flex items-center gap-1">
                                        {i > 0 and <span className="text-muted-foreground">{"/"}</span>}
                                        <button
                                            type="button"
                                            onClick={bind_trail_click(i)}
                                            className={(
                                                "rounded px-1 py-0.5 font-medium transition-colors "
                                                + (
                                                    "text-foreground"
                                                        if i == len(trail) - 1
                                                        else "text-muted-foreground hover:text-foreground hover:bg-muted"
                                                )
                                            )}
                                        >
                                            {str(step["name"])}
                                        </button>
                                    </span>
                                }}
                            </nav>
                            <p className="text-xs text-muted-foreground">
                                {"Click a hub to dig in. Events open a detail tab here. Pinch/scroll to spread clusters · drag empty space to pan · yank a node to bounce."}
                            </p>
                            <Button
                                type="button"
                                size="sm"
                                variant="outline"
                                disabled={syncing}
                                onClick={lambda (e: MouseEvent) { run_online_sync(True); }}
                                className="mt-1 w-full"
                            >
                                {(
                                    "Syncing calendars…"
                                    if syncing
                                    else "Sync live events"
                                )}
                            </Button>
                            {syncMsg
                                and <p className="text-[11px] leading-snug text-muted-foreground">
                                    {syncMsg}
                                </p>}
                        </div>
                        <div className="border-t pt-4">
                            <button
                                type="button"
                                onClick={lambda (e: MouseEvent) { showFilters = not showFilters; }}
                                className="kicker flex w-full items-center justify-between text-foreground"
                            >
                                <span>{"Filters & ask"}</span>
                                <span>{"Hide" if showFilters else "Show"}</span>
                            </button>
                            {showFilters
                                and <div className="mt-3">
                                    <FilterBar filters={filters} onChange={onFilters} dark={dark}/>
                                </div>}
                        </div>
                    </div>}
            </aside>
        </div>;
}
