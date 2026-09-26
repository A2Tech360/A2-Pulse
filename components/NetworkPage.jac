"""Network tab: the Ann Arbor web as a living graph (EgoSnapshot walker)."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon, Cancel01Icon, ArrowUpRight01Icon, Analytics01Icon }
import from .ui.input { Input }
import from .ui.slider { Slider }
import from .ui.skeleton { Skeleton }
import from .ui.button { Button }
import from .FilterBar { FilterBar }
import from .pulse_theme { kind_color, kind_label }

glob CAMPUS_LAT: float = 42.2780;
glob CAMPUS_LNG: float = -83.7382;
sv import from ..services.pulse { EgoSnapshot, SearchArchive, GetDossier, Snapshot, GNode, GEdge, Dossier }

glob LEGEND: list[str] = ["event", "venue", "organizer", "category", "alert", "civic"];
glob STARTERS: list[dict] = [
    {"key": "cat-music", "name": "music"},
    {"key": "o-jazz", "name": "U-M Jazz Collective"},
    {"key": "a-plymouth", "name": "Plymouth Rd lane closure"},
    {"key": "cat-civic", "name": "civic"},
    {"key": "cat-food", "name": "food"}
];

def:pub NetworkPage(filters: dict, onFilters: Callable[[dict], None]) -> JsxElement {
    has centerKey: str = "cat-music",
        centerName: str = "music",
        hops: int = 2,
        nodes: list[GNode] = [],
        edges: list[GEdge] = [],
        loading: bool = True,
        error: str = "",
        query: str = "",
        results: list[GNode] = [],
        selected: Dossier | None = None,
        selectedId: str = "",
        hoverId: str = "",
        showFilters: bool = False;

    async def load_graph -> None {
        loading = True;
        error = "";
        try {
            res = root spawn EgoSnapshot(
                center_key=centerKey, hops=hops,
                categories=filters["categories"] or [], kinds=filters["kinds"] or [],
                price=filters["price"] or "any", time=filters["time"] or "week",
                distance=filters["distance"] or 0.0, clat=CAMPUS_LAT, clng=CAMPUS_LNG
            );
            if res.reports and len(res.reports) > 0 {
                snap: Snapshot = res.reports[0];
                nodes = snap.nodes;
                edges = snap.edges;
            } else {
                nodes = [];
                edges = [];
            }
        } except Exception {
            error = "The graph walker could not reach the archive.";
        }
        loading = False;
    }

    can with (centerKey, hops, filters) entry {
        load_graph();
    }

    async def run_search(q: str) -> None {
        query = q;
        if not q.strip() {
            results = [];
            return;
        }
        res = root spawn SearchArchive(query=q);
        results = res.reports[0] if res.reports and len(res.reports) > 0 else [];
    }

    async def open_dossier(id: str) -> None {
        selectedId = id;
        res = root spawn GetDossier(node_id=id);
        selected = res.reports[0] if res.reports and len(res.reports) > 0 else None;
    }

    def recenter(key: str, name: str) {
        centerKey = key;
        centerName = name;
        results = [];
        query = "";
    }

    pos: dict[str, GNode] = {};
    for n in nodes {
        pos[n.id] = n;
    }
    focus = hoverId or selectedId;

    return <div className="relative flex flex-1 flex-col lg:flex-row">
        {#* ---------------- graph canvas ---------------- *#}
        <div className="relative min-h-[70svh] flex-1 overflow-hidden paper-grain lg:min-h-[calc(100svh-230px)]">
            {loading and len(nodes) == 0 and <div className="absolute inset-0 flex items-center justify-center">
                <div className="flex flex-col items-center gap-3">
                    <Skeleton className="size-24 rounded-full" />
                    <span className="kicker text-muted-foreground">{"Walking the graph..."}</span>
                </div>
            </div>}
            {error and <div className="absolute inset-0 flex flex-col items-center justify-center gap-3">
                <p className="text-sm text-destructive">{error}</p>
                <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { load_graph(); }}>{"Retry"}</Button>
            </div>}
            {not loading and not error and len(nodes) <= 1 and <div className="absolute inset-0 flex items-center justify-center pl-6 pr-6">
                <div className="max-w-sm border border-foreground bg-card pt-6 pb-6 pl-6 pr-6 text-center shadow-[4px_4px_0_var(--foreground)]">
                    <div className="mx-auto mb-3 flex size-10 items-center justify-center bg-primary/10 text-primary">
                        <HugeiconsIcon icon={Analytics01Icon} strokeWidth={2} className="size-5" />
                    </div>
                    <h3 className="font-display text-xl font-bold">{"Nothing matches this walk"}</h3>
                    <p className="mt-1 text-sm text-muted-foreground">{"Loosen a filter or pick something else to explore."}</p>
                    <Button className="mt-4" size="sm" onClick={lambda (e: MouseEvent) { onFilters({"categories": [], "kinds": [], "price": "any", "time": "week", "distance": 0.0, "reply": "", "query": ""}); }}>{"Clear filters"}</Button>
                </div>
            </div>}
            <svg viewBox="0 0 1200 800" preserveAspectRatio="xMidYMid slice" className={"absolute inset-0 size-full transition-opacity duration-500 " + ("opacity-50" if loading else "opacity-100")}>
                {for e in edges {
                    if e.source in pos and e.target in pos {
                        <line
                            key={e.source + e.target}
                            x1={pos[e.source].x} y1={pos[e.source].y}
                            x2={pos[e.target].x} y2={pos[e.target].y}
                            stroke={("#9b1c2e" if focus and (e.source == focus or e.target == focus) else "#6b5e55")}
                            strokeOpacity={(0.9 if focus and (e.source == focus or e.target == focus) else 0.28)}
                            strokeWidth={(1.6 if focus and (e.source == focus or e.target == focus) else 0.9)}
                        />
                    }
                }}
                {for n in nodes {
                    <g
                        key={n.id}
                        transform={f"translate({n.x},{n.y})"}
                        className="cursor-pointer"
                        onClick={lambda (e: MouseEvent) { open_dossier(n.id); }}
                        onDoubleClick={lambda (e: MouseEvent) { recenter(n.key, n.name); }}
                        onMouseEnter={lambda (e: MouseEvent) { hoverId = n.id; }}
                        onMouseLeave={lambda (e: MouseEvent) { hoverId = ""; }}
                    >
                        {if n.depth == 0 {
                            <circle r={30} fill="none" stroke={kind_color(n.kind)} strokeWidth={1.5} strokeDasharray="3 4" />
                        }}
                        <circle
                            r={(18 if n.depth == 0 else (11 if n.depth == 1 else 7))}
                            fill={kind_color(n.kind)}
                            fillOpacity={(1.0 if n.depth < 2 else 0.78)}
                            stroke={("#1f1a17" if n.id == selectedId else "#faf6ee")}
                            strokeWidth={(3 if n.id == selectedId else 2)}
                        />
                        <text
                            y={(40 if n.depth == 0 else (26 if n.depth == 1 else 20))}
                            textAnchor="middle"
                            fontFamily="Fraunces, Georgia, serif"
                            fontWeight={(800 if n.depth == 0 else (600 if n.depth == 1 else 500))}
                            fontSize={(24 if n.depth == 0 else (15 if n.depth == 1 else 12))}
                            fill={("#1f1a17" if n.depth < 2 else kind_color(n.kind))}
                            stroke="#f7f1e4"
                            strokeWidth={4}
                            paintOrder="stroke"
                        >
                            {(n.name if len(n.name) < 30 else n.name[:28] + "...")}
                        </text>
                    </g>
                }}
            </svg>

            {#* editorial overlay, like a front page headline *#}
            <div className="pointer-events-none relative z-10 flex flex-col gap-4 pt-8 pb-6 pl-5 pr-5 sm:pl-10 lg:max-w-xl">
                <div className="flex items-center gap-3">
                    <span className="h-px w-10 bg-primary" />
                    <span className="kicker text-primary">{"Live · The Network"}</span>
                </div>
                <h2 className="font-display text-4xl font-black leading-[0.95] tracking-tight sm:text-5xl md:text-6xl">
                    {"Everything's connected. "}<span className="text-primary">{"We walk the web."}</span>
                </h2>
                <p className="max-w-md text-base leading-relaxed text-foreground/80">
                    {"Every concert, club, closure and council vote in Ann Arbor, strung together. Pick a thread and watch what's tied to it fan out."}
                </p>
                <div className="pointer-events-auto flex flex-col gap-2">
                    <div className="relative max-w-md">
                        <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                        <Input
                            value={query}
                            onChange={lambda (e: ChangeEvent) { run_search(e.target.value); }}
                            placeholder="Search a club, venue, category or closure"
                            className="h-11 border-foreground bg-card pl-9 shadow-[3px_3px_0_var(--foreground)]"
                        />
                        {len(results) > 0 and <div className="absolute left-0 right-0 top-12 z-30 max-h-72 overflow-y-auto border border-foreground bg-card shadow-[4px_4px_0_var(--foreground)]">
                            {for r in results {
                                <button key={r.id} type="button" onClick={lambda (e: MouseEvent) { recenter(r.key, r.name); }} className="flex w-full items-center gap-3 border-b pt-2 pb-2 pl-3 pr-3 text-left last:border-b-0 hover:bg-muted">
                                    <span className="size-2.5 shrink-0 rounded-full" style={{"backgroundColor": kind_color(r.kind)}} />
                                    <span className="flex-1 truncate text-sm font-medium capitalize">{r.name}</span>
                                    <span className="kicker text-muted-foreground">{kind_label(r.kind)}</span>
                                </button>
                            }}
                        </div>}
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                        {for s in STARTERS {
                            <button key={s["key"]} type="button" onClick={lambda (e: MouseEvent) { recenter(s["key"], s["name"]); }} className={"kicker border pt-1 pb-1 pl-2 pr-2 capitalize transition-colors " + ("border-primary bg-primary text-primary-foreground" if centerKey == s["key"] else "border-border bg-card/80 hover:border-foreground")}>
                                {s["name"]}
                            </button>
                        }}
                    </div>
                </div>
            </div>

            {#* legend + stats, bottom-left *#}
            <div className="absolute bottom-4 left-4 z-10 flex flex-wrap items-center gap-3 border bg-card/90 pt-2 pb-2 pl-3 pr-3 backdrop-blur sm:left-10">
                {for k in LEGEND {
                    <span key={k} className="kicker flex items-center gap-1.5 text-muted-foreground">
                        <span className="size-2.5 rounded-full" style={{"backgroundColor": kind_color(k)}} />
                        {kind_label(k)}
                    </span>
                }}
                <span className="kicker border-l pl-3 tabular-nums text-foreground">{f"{len(nodes)} nodes · {len(edges)} ties"}</span>
            </div>
        </div>

        {#* ---------------- side column: hops, filters, dossier ---------------- *#}
        <aside className="relative z-20 flex w-full flex-col gap-5 border-t bg-card/85 pt-5 pb-6 pl-5 pr-5 backdrop-blur lg:w-[380px] lg:border-l lg:border-t-0">
            <div className="flex flex-col gap-3">
                <div className="flex items-baseline justify-between">
                    <span className="kicker text-muted-foreground">{"Center of the walk"}</span>
                    <span className="kicker text-primary">{kind_label(pos[nodes[0].id].kind) if len(nodes) > 0 else ""}</span>
                </div>
                <h3 className="font-display text-2xl font-bold capitalize leading-tight">{centerName}</h3>
                <div className="flex items-center justify-between text-xs">
                    <span className="kicker text-muted-foreground">{"How far out"}</span>
                    <span className="kicker tabular-nums">{str(hops) + (" hop" if hops == 1 else " hops")}</span>
                </div>
                <Slider min={1} max={3} step={1} value={[hops]} onValueChange={lambda (v: list[float]) { hops = int(v[0]); }} />
                <p className="text-xs text-muted-foreground">{"1 = direct ties. 2 = friends of friends. Double-click any bubble to re-center."}</p>
            </div>

            <div className="border-t pt-4">
                <button type="button" onClick={lambda (e: MouseEvent) { showFilters = not showFilters; }} className="kicker flex w-full items-center justify-between text-foreground">
                    <span>{"Filters & ask"}</span>
                    <span>{"Hide" if showFilters else "Show"}</span>
                </button>
                {showFilters and <div className="mt-3"><FilterBar filters={filters} onChange={onFilters} /></div>}
            </div>

            <div className="border-t pt-4">
                {if selected is None {
                    <div className="flex flex-col gap-1">
                        <span className="kicker text-muted-foreground">{"The dossier"}</span>
                        <p className="text-sm text-muted-foreground">{"Click any bubble to read its file: when, where, who, and where the fact came from."}</p>
                    </div>
                    skip;
                }}
                {selected and <div className="flex flex-col gap-3 animate-in fade-in slide-in-from-bottom-2 duration-300">
                    <div className="flex items-start justify-between gap-3">
                        <div className="flex flex-col gap-1">
                            <span className="kicker" style={{"color": kind_color(selected.kind)}}>{kind_label(selected.kind)}</span>
                            <h3 className="font-display text-xl font-bold leading-tight">{selected.name}</h3>
                        </div>
                        <button type="button" onClick={lambda (e: MouseEvent) { selected = None; selectedId = ""; }} className="text-muted-foreground hover:text-foreground">
                            <HugeiconsIcon icon={Cancel01Icon} strokeWidth={2} className="size-4" />
                        </button>
                    </div>
                    {selected.desc and <p className="text-sm leading-relaxed">{selected.desc}</p>}
                    <dl className="grid grid-cols-[88px_1fr] gap-y-1.5 text-sm">
                        {selected.when and <dt className="kicker pt-0.5 text-muted-foreground">{"When"}</dt>}
                        {selected.when and <dd>{selected.when}</dd>}
                        {(selected.venue or selected.address) and <dt className="kicker pt-0.5 text-muted-foreground">{"Where"}</dt>}
                        {(selected.venue or selected.address) and <dd>{selected.venue + (" · " + selected.address if selected.address else "")}</dd>}
                        {selected.organizer and <dt className="kicker pt-0.5 text-muted-foreground">{"Who"}</dt>}
                        {selected.organizer and <dd>{selected.organizer}</dd>}
                        {selected.kind == "event" and <dt className="kicker pt-0.5 text-muted-foreground">{"Price"}</dt>}
                        {selected.kind == "event" and <dd>{("Free" if selected.price == 0.0 else f"${selected.price:.0f}")}</dd>}
                    </dl>
                    {len(selected.categories) > 0 and <div className="flex flex-wrap gap-1">
                        {for c in (selected.categories if selected else []) {
                            <span key={c} className="kicker border pt-0.5 pb-0.5 pl-1.5 pr-1.5 text-muted-foreground">{c}</span>
                        }}
                    </div>}
                    <div className="flex flex-wrap gap-2">
                        <Button size="sm" variant="outline" onClick={lambda (e: MouseEvent) { recenter(selected.key, selected.name); }}>{"Center here"}</Button>
                        {selected.source_url and <a href={selected.source_url} target="_blank" rel="noreferrer" className="kicker inline-flex items-center gap-1 text-primary hover:underline">
                            {"Source: " + selected.source_name}
                            <HugeiconsIcon icon={ArrowUpRight01Icon} strokeWidth={2} className="size-3.5" />
                        </a>}
                    </div>
                </div>}
            </div>
        </aside>
    </div>;
}
