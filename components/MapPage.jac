"""Map tab: graph truth as an interactive Google Map — Jac shell + overlays."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Location01Icon }
import from .ui.skeleton { Skeleton }
import from .ui.button { Button }
import from .FilterBar { FilterBar }
import from .map_markers { sticker_img_url }
import from .pulse_theme { campus_lat, campus_lng, default_filters }
import from .profile_store { my_persona, load_profile }
import from .net { with_timeout }
import from .MapChrome {
    MapAddressSearch,
    MapKeyMissing,
    MapLoading
}
import from .google_maps {
    load_google_maps,
    create_pulse_map,
    apply_map_theme,
    clear_overlays,
    sync_map_overlays,
    pan_to_item,
    place_search_pin,
    clear_search_pin
}
sv import from ..services.pulse { MapSnapshot, MapItem, maps_config, map_pin_overview, MapOverview }

glob MAP_PIN_CAP: int = 80;
glob MAP_LIST_CAP: int = 120;
# Same live calendars Network pulls — keep map pins in sync even if Network wasn't visited.
glob MAP_FETCH_MS: int = 45000;

def join_filter_list(vals: list[str]) -> str {
    out: str = "";
    for v in vals {
        if out {
            out = out + ",";
        }
        out = out + v;
    }
    return out;
}

def:pub MapPage(
    filters: dict, onFilters: Callable[[dict], None], dark: bool = True, syncVersion: int = 0
) -> JsxElement {
    has items: list[MapItem] = [],
        loading: bool = True,
        error: str = "",
        focusId: str = "",
        apiKey: str = "",
        keyChecked: bool = False,
        mapDown: bool = False,
        mapsReady: bool = False,
        mapEl: Ref[HTMLDivElement] = Ref(),
        mapRef: Ref[any] = Ref(None),
        overlaysRef: Ref[any] = Ref(None),
        infoRef: Ref[any] = Ref(None),
        searchPinRef: Ref[any] = Ref(None),
        pinOverviews: dict = {};

    cats: list[str] = filters["categories"] or [];
    kinds: list[str] = filters["kinds"] or [];
    price: str = filters["price"] or "any";
    time: str = filters["time"] or "week";
    date: str = filters["date"] or "";
    distance: float = filters["distance"] or 0.0;
    include_posted: bool = filters["community"] != False;
    # Primitive sig so category toggles always re-fetch (dict identity can be sticky).
    filter_sig: str = (
        join_filter_list(cats)
        + "|"
        + join_filter_list(kinds)
        + "|"
        + price
        + "|"
        + time
        + "|"
        + date
        + "|"
        + str(distance)
        + "|"
        + ("1" if include_posted else "0")
    );

    async def load_config -> None {
        mapDown = False;
        cfg: any = None;
        try {
            cfg = await with_timeout(maps_config(), None);
        } except Exception {
            cfg = None;
        }
        if cfg is None {
            mapDown = True;
            return;
        }
        key = cfg["key"] or "";
        apiKey = key;
        keyChecked = True;
        if key {
            load_google_maps(key, lambda { mapsReady = True; });
        }
    }

    async can with entry {
        load_config();
    }

    # AppShell syncs calendars when the app opens; reload pins once it brings new data.
    can with [syncVersion] entry {
        if syncVersion > 0 {
            load_pins();
        }
    }

    def map_kinds() -> list[str] {
        # Category chips alone should focus happenings — orgs made the map look unchanged.
        if len(cats) > 0 and len(kinds) == 0 {
            return ["event"];
        }
        return kinds;
    }

    async def fetch_pins(
        want_cats: list[str],
        want_kinds: list[str],
        want_price: str,
        want_time: str,
        want_date: str,
        want_dist: float,
        want_posted: bool
    ) -> any {
        await load_profile();
        res = root spawn MapSnapshot(
            categories=want_cats,
            kinds=want_kinds,
            price=want_price,
            time=want_time,
            date=want_date,
            community=want_posted,
            community_only=False,
            distance=want_dist,
            clat=campus_lat(),
            clng=campus_lng(),
            persona=my_persona()
        );
        return res;
    }

    def parse_pin_report(res: any) -> list[MapItem] {
        if res is None {
            return [];
        }
        reps: any = res.reports;
        if not reps or len(reps) == 0 {
            return [];
        }
        first: any = reps[0];
        if isinstance(first, list) {
            return first;
        }
        return [];
    }

    def rank_pins(raw: list[MapItem]) -> list[MapItem] {
        ranked: list[MapItem] = [];
        for it in raw {
            ranked = ranked + [it];
        }
        ranked.sort(
            key=lambda (it: MapItem) -> float {
                return it.dist if it.dist > 0.0 else 9999.0;
            }
        );
        return ranked;
    }

    async def load_pins -> None {
        want_cats: list[str] = cats;
        want_kinds: list[str] = map_kinds();
        want_price: str = price;
        want_time: str = time;
        want_date: str = date;
        want_dist: float = distance;
        want_posted: bool = include_posted;
        loading = True;
        error = "";
        focusId = "";
        # Drop old pins immediately so category changes are obvious on the map.
        items = [];
        old: list[any] = overlaysRef.current or [];
        clear_overlays(old);
        overlaysRef.current = [];
        w: any = window;
        req: int = (w.__pulsePinsReq or 0) + 1;
        w.__pulsePinsReq = req;
        res: any = None;
        try {
            res = await with_timeout(
                fetch_pins(
                    want_cats,
                    want_kinds,
                    want_price,
                    want_time,
                    want_date,
                    want_dist,
                    want_posted
                ),
                None,
                MAP_FETCH_MS
            );
        } except Exception {
            res = None;
        }
        if w.__pulsePinsReq != req {
            return;
        }
        if res is None {
            error = "Can't reach the A2 Pulse server right now. Check your connection, then retry.";
            items = [];
        } else {
            items = rank_pins(parse_pin_report(res));
        }
        loading = False;
    }

    def clear_filters(e: MouseEvent) {
        onFilters(default_filters());
    }

    async def ensure_overview(id: str) {
        if id in pinOverviews {
            return;
        }
        try {
            ov: MapOverview = await map_pin_overview(id);
            nxt: dict = {**pinOverviews};
            nxt[id] = {"blurb": ov.blurb, "tip": ov.tip, "headline": ov.headline};
            pinOverviews = nxt;
        } except Exception {
            nxt2: dict = {**pinOverviews};
            nxt2[id] = {"blurb": "", "tip": "", "headline": ""};
            pinOverviews = nxt2;
        }
    }

    def select_pin(id: str) {
        focusId = id;
        ensure_overview(id);
    }

    can with [filter_sig] entry {
        load_pins();
    }

    can with [mapsReady] entry {
        if mapsReady and mapEl.current and not mapRef.current {
            bundle = create_pulse_map(mapEl.current, dark);
            mapRef.current = bundle["map"];
            infoRef.current = bundle["info"];
            overlaysRef.current = [];
        }
    }

    can with exit {
        old: list[any] = overlaysRef.current or [];
        clear_overlays(old);
        clear_search_pin(searchPinRef.current);
        mapRef.current = None;
        infoRef.current = None;
        overlaysRef.current = None;
        searchPinRef.current = None;
    }

    can with (dark, mapsReady) entry {
        apply_map_theme(mapRef.current, dark, mapEl.current);
    }

    list_items: list[MapItem] = [];
    li: int = 0;
    for it in items {
        if li < MAP_LIST_CAP {
            list_items = list_items + [it];
        }
        li += 1;
    }

    can with (items, focusId, filter_sig, mapsReady, dark, pinOverviews) entry {
        m: any = mapRef.current;
        if not m or not mapsReady {
            return;
        }
        old: list[any] = overlaysRef.current or [];
        clear_overlays(old);
        dist: float = distance;
        pin_slice: list[MapItem] = [];
        n: int = 0;
        for it in items {
            if n >= MAP_PIN_CAP {
                break;
            }
            pin_slice = pin_slice + [it];
            n += 1;
        }
        overlaysRef.current = sync_map_overlays(
            m,
            infoRef.current,
            pin_slice,
            focusId,
            dist,
            dark,
            lambda (id: str) { select_pin(id); },
            pinOverviews
        );
    }

    def focus_item(it: MapItem) {
        select_pin(it.id);
        clear_search_pin(searchPinRef.current);
        searchPinRef.current = None;
        pan_to_item(mapRef.current, it.lat, it.lng);
    }

    def bind_focus(it: MapItem) -> Callable[[MouseEvent], None] {
        return lambda (e: MouseEvent) { focus_item(it); };
    }

    def go_to_place(lat: float, lng: float, label: str) {
        focusId = "";
        searchPinRef.current = place_search_pin(
            mapRef.current,
            infoRef.current,
            dark,
            lat,
            lng,
            label,
            searchPinRef.current
        );
    }

    def retry_load(e: MouseEvent) {
        load_pins();
    }

    cat_label: str = "all topics";
    if len(cats) == 1 {
        cat_label = cats[0];
    } elif len(cats) > 1 {
        cat_label = str(len(cats)) + " topics";
    }

    return
        <div className="flex flex-1 flex-col bg-background text-foreground lg:flex-row">
            <div
                className="relative min-h-[60svh] flex-1 bg-muted lg:min-h-[calc(100svh-120px)]"
            >
                <div ref={mapEl} className="absolute inset-0"/>
                {keyChecked and not apiKey and <MapKeyMissing/>}
                {mapDown
                    and <div className="absolute inset-0 z-10 flex items-center justify-center pl-6 pr-6" role="alert">
                        <div className="flex max-w-sm flex-col items-center gap-3 rounded-xl border border-border bg-card pt-6 pb-6 pl-6 pr-6 text-center shadow-sm">
                            <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-5 text-muted-foreground" />
                            <p className="text-sm text-foreground">{"The map can't load right now. Check your connection, then retry."}</p>
                            <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { load_config(); load_pins(); }}>{"Retry"}</Button>
                        </div>
                    </div>}
                {((apiKey and not mapsReady) or (not keyChecked and not mapDown)) and <MapLoading/>}
                {mapsReady
                    and <MapAddressSearch dark={dark} onGoTo={go_to_place}/>}
                {loading
                    and mapsReady
                    and <div className="pointer-events-none absolute left-1/2 top-4 z-20 -translate-x-1/2 rounded-full border border-border bg-card/95 px-3 py-1.5 text-xs font-medium text-foreground shadow-sm">
                        {"Updating map…"}
                    </div>}
            </div>
            <aside
                className="flex w-full flex-col gap-6 border-t border-border bg-background pt-6 pb-6 pl-6 pr-6 lg:w-[380px] lg:border-l lg:border-t-0"
            >
                <FilterBar filters={filters} onChange={onFilters} dark={dark}/>
                <div className="flex flex-col gap-2 border-t border-border pt-5">
                    <div className="flex items-baseline justify-between gap-2">
                        <h3 className="text-sm font-semibold text-foreground">
                            {"On the map"}
                        </h3>
                        <span className="text-xs tabular-nums text-muted-foreground">
                            {(
                                "…"
                                    if loading
                                    else f"{len(items)} matches"
                            )}
                        </span>
                    </div>
                    <p className="text-xs text-muted-foreground">
                        {(
                            "Showing "
                            + cat_label
                            + (
                                " events nearest campus."
                                    if len(cats) > 0 and len(kinds) == 0
                                    else ". Route alerts stay on when they touch you."
                            )
                        )}
                    </p>
                    {len(items) > MAP_PIN_CAP
                        and not loading
                        and <p className="text-xs text-muted-foreground">
                            {f"Map pins: nearest {MAP_PIN_CAP} of {len(items)}. Scroll the list for more."}
                        </p>}
                    {error
                        and <div className="flex items-center gap-3">
                            <p className="text-sm text-destructive">{error}</p>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={retry_load}
                            >
                                {"Retry"}
                            </Button>
                        </div>}
                    {if loading and len(items) == 0 {
                        <div className="flex flex-col gap-2">
                            <Skeleton className="h-12 w-full"/>
                            <Skeleton className="h-12 w-full"/>
                            <Skeleton className="h-12 w-full"/>
                        </div>
                        skip;
                    }}
                    {if not loading and len(items) == 0 and not error {
                        <div
                            className="flex flex-col items-center gap-2 rounded-lg border border-dashed border-border pt-8 pb-8 text-center"
                        >
                            <HugeiconsIcon
                                icon={Location01Icon}
                                strokeWidth={2}
                                className="size-5 text-muted-foreground"
                            />
                            <p className="text-sm font-medium text-foreground">
                                {"No places match"}
                            </p>
                            <p className="text-xs text-muted-foreground">
                                {"Try another category, widen distance, or clear filters."}
                            </p>
                            <Button variant="outline" size="sm" className="mt-1" onClick={clear_filters}>
                                {"Clear filters"}
                            </Button>
                        </div>
                        skip;
                    }}
                    <div
                        className="-ml-2 -mr-2 flex max-h-[46svh] flex-col overflow-y-auto"
                    >
                        {for it in list_items {
                            <button
                                key={it.id}
                                type="button"
                                onClick={bind_focus(it)}
                                className={
                                    "flex items-start gap-3 rounded-md pt-2.5 pb-2.5 pl-2 pr-2 text-left text-foreground transition-colors hover:bg-muted "
                                    + ("bg-muted" if it.id == focusId else "")
                                }
                            >
                                <img
                                    src={sticker_img_url(it.kind, dark, it.categories)}
                                    alt=""
                                    className="mt-0.5 h-9 w-9 shrink-0 object-contain"
                                />
                                <span className="flex min-w-0 flex-1 flex-col">
                                    <span className="truncate text-sm font-medium">
                                        {it.name}
                                    </span>
                                    <span className="truncate text-xs text-muted-foreground">
                                        {it.when
                                            + ((" · " + it.venue) if it.venue else "")}
                                    </span>
                                </span>
                                <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                                    {f"{it.dist:.1f} mi"}
                                </span>
                            </button>
                        }}
                    </div>
                </div>
            </aside>
        </div>;
}
