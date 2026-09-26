"""Map tab: the same graph truth as an interactive Google Map (MapSnapshot walker)."""

import from react { useEffect }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Location01Icon, Settings01Icon }
import from .ui.skeleton { Skeleton }
import from .ui.button { Button }
import from .FilterBar { FilterBar }
import from .pulse_theme { kind_color, kind_label }
sv import from ..services.pulse { MapSnapshot, MapItem, maps_config }

glob CAMPUS_LAT: float = 42.2780;
glob CAMPUS_LNG: float = -83.7382;

# Quiet, minimal basemap: muted land, no POI clutter.
glob MAP_STYLE: list[dict] = [
    {"elementType": "geometry", "stylers": [{"color": "#f5f5f4"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#78716c"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#ffffff"}]},
    {"featureType": "poi", "stylers": [{"visibility": "off"}]},
    {"featureType": "transit", "stylers": [{"visibility": "simplified"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#e7e5e4"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#dbe4ea"}]}
];

def load_google_maps(key: str, on_ready: Callable[[], None]) {
    w: any = window;
    if w.google and w.google.maps {
        on_ready();
        return;
    }
    existing: any = document.getElementById("gmaps-js");
    if existing {
        existing.addEventListener("load", lambda { on_ready(); });
        return;
    }
    s: any = document.createElement("script");
    s.id = "gmaps-js";
    s.src = "https://maps.googleapis.com/maps/api/js?key=" + key + "&v=weekly";
    s.async = True;
    s.onload = lambda { on_ready(); };
    doc: any = document;
    doc.head.appendChild(s);
}

def popup_html(it: MapItem) -> str {
    price = "";
    if it.kind == "event" {
        price = " · Free" if it.price == 0.0 else f" · ${it.price:.0f}";
    }
    dir_url = f"https://www.google.com/maps/dir/?api=1&destination={it.lat},{it.lng}";
    src = "";
    if it.source_url {
        src = f"<a href='{it.source_url}' target='_blank' rel='noreferrer' style='color:#57534e'>{it.source_name}</a> &middot; ";
    }
    return (
        f"<div style='max-width:240px;font-family:Geist Variable,system-ui,sans-serif'>"
        + f"<div style='font-size:11px;color:{kind_color(it.kind)};font-weight:600'>{kind_label(it.kind)}{price}</div>"
        + f"<div style='font-size:15px;font-weight:600;margin:2px 0 4px;color:#1c1917'>{it.name}</div>"
        + f"<div style='font-size:12px;color:#57534e'>{it.when}{(' · ' + it.venue) if it.venue else ''}</div>"
        + f"<div style='font-size:12px;color:#78716c;margin:6px 0'>{it.desc}</div>"
        + f"<div style='font-size:12px'>{src}<a href='{dir_url}' target='_blank' rel='noreferrer' style='color:#1c1917;font-weight:600'>Directions</a></div></div>"
    );
}

def:pub MapPage(filters: dict, onFilters: Callable[[dict], None]) -> JsxElement {
    has items: list[MapItem] = [],
        loading: bool = True,
        error: str = "",
        focusId: str = "",
        apiKey: str = "",
        keyChecked: bool = False,
        mapsReady: bool = False,
        mapEl: Ref[HTMLDivElement] = Ref(),
        mapRef: Ref[any] = Ref(None),
        overlaysRef: Ref[any] = Ref(None),
        infoRef: Ref[any] = Ref(None);

    async can with entry {
        cfg = await maps_config();
        apiKey = cfg["key"] or "";
        keyChecked = True;
        if apiKey {
            load_google_maps(apiKey, lambda { mapsReady = True; });
        }
    }

    async def load_pins -> None {
        loading = True;
        error = "";
        try {
            res = root spawn MapSnapshot(
                categories=filters["categories"] or [], kinds=filters["kinds"] or [],
                price=filters["price"] or "any", time=filters["time"] or "week",
                distance=filters["distance"] or 0.0, clat=CAMPUS_LAT, clng=CAMPUS_LNG
            );
            items = res.reports[0] if res.reports and len(res.reports) > 0 else [];
        } except Exception {
            error = "Could not load the map layer.";
        }
        loading = False;
    }

    can with [filters] entry {
        load_pins();
    }

    # create the Google map once the script is ready
    useEffect(lambda {
        w: any = window;
        if mapsReady and mapEl.current and not mapRef.current {
            gm: any = w.google.maps;
            mapRef.current = new(gm.Map, mapEl.current, {
                "center": {"lat": CAMPUS_LAT, "lng": CAMPUS_LNG},
                "zoom": 14,
                "styles": MAP_STYLE,
                "disableDefaultUI": True,
                "zoomControl": True,
                "fullscreenControl": True,
                "gestureHandling": "greedy"
            });
            infoRef.current = new(gm.InfoWindow);
            overlaysRef.current = [];
        }
        return lambda {
            if overlaysRef.current {
                for o in overlaysRef.current { o.setMap(None); }
            }
            mapRef.current = None;
        };
    }, [mapsReady]);

    # redraw markers, closure lines and radius circle on data change
    useEffect(lambda {
        w: any = window;
        m: any = mapRef.current;
        if not m or not mapsReady {
            return;
        }
        gm: any = w.google.maps;
        old: list[any] = overlaysRef.current or [];
        for o in old { o.setMap(None); }
        fresh: list[any] = [];
        info: any = infoRef.current;
        dist: float = filters["distance"] or 0.0;
        fresh.append(new(gm.Marker, {
            "position": {"lat": CAMPUS_LAT, "lng": CAMPUS_LNG}, "map": m, "title": "Central Campus",
            "icon": {"path": gm.SymbolPath.CIRCLE, "scale": 6, "fillColor": "#1c1917", "fillOpacity": 1, "strokeColor": "#ffffff", "strokeWeight": 3}
        }));
        if dist > 0.0 {
            fresh.append(new(gm.Circle, {
                "map": m, "center": {"lat": CAMPUS_LAT, "lng": CAMPUS_LNG}, "radius": dist * 1609.34,
                "strokeColor": "#1c1917", "strokeOpacity": 0.35, "strokeWeight": 1, "fillColor": "#1c1917", "fillOpacity": 0.04
            }));
        }
        for it in items {
            col = kind_color(it.kind);
            html = popup_html(it);
            if len(it.path) > 1 {
                line: any = new(gm.Polyline, {
                    "map": m, "path": [{"lat": p[0], "lng": p[1]} for p in it.path],
                    "strokeColor": col, "strokeOpacity": 0.8, "strokeWeight": 5
                });
                line.addListener("click", lambda (ev: any) { info.setContent(html); info.setPosition(ev.latLng); info.open(m); });
                fresh.append(line);
            }
            mk: any = new(gm.Marker, {
                "position": {"lat": it.lat, "lng": it.lng}, "map": m, "title": it.name,
                "icon": {"path": gm.SymbolPath.CIRCLE, "scale": (10 if it.id == focusId else 7), "fillColor": col, "fillOpacity": 1, "strokeColor": "#ffffff", "strokeWeight": 2}
            });
            mk.addListener("click", lambda { focusId = it.id; info.setContent(html); info.open(m, mk); });
            if it.id == focusId {
                info.setContent(html);
                info.open(m, mk);
            }
            fresh.append(mk);
        }
        overlaysRef.current = fresh;
    }, [items, focusId, filters, mapsReady]);

    def focus_item(it: MapItem) {
        focusId = it.id;
        if mapRef.current {
            mapRef.current.panTo({"lat": it.lat, "lng": it.lng});
            mapRef.current.setZoom(16);
        }
    }

    return <div className="flex flex-1 flex-col lg:flex-row">
        <div className="relative min-h-[60svh] flex-1 bg-muted lg:min-h-[calc(100svh-120px)]">
            <div ref={mapEl} className="absolute inset-0" />
            {keyChecked and not apiKey and <div className="absolute inset-0 flex items-center justify-center pt-6 pb-6 pl-6 pr-6">
                <div className="flex max-w-md flex-col gap-3 rounded-xl border bg-card pt-6 pb-6 pl-6 pr-6 shadow-sm">
                    <div className="flex size-9 items-center justify-center rounded-lg bg-muted">
                        <HugeiconsIcon icon={Settings01Icon} strokeWidth={2} className="size-4" />
                    </div>
                    <h3 className="text-lg font-semibold tracking-tight">{"Connect Google Maps"}</h3>
                    <ol className="flex list-decimal flex-col gap-1.5 pl-4 text-sm text-muted-foreground">
                        <li>{"In Google Cloud Console, enable the Maps JavaScript API and create an API key."}</li>
                        <li>{"Open Settings (gear icon) > Environment and add GOOGLE_MAPS_API_KEY."}</li>
                        <li>{"Restart the preview. The map loads here."}</li>
                    </ol>
                    <p className="text-xs text-muted-foreground">{"The list on the right works without a key."}</p>
                </div>
            </div>}
            {apiKey and not mapsReady and <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-sm text-muted-foreground">{"Loading Google Maps..."}</span>
            </div>}
        </div>

        <aside className="flex w-full flex-col gap-6 border-t bg-background pt-6 pb-6 pl-6 pr-6 lg:w-[380px] lg:border-l lg:border-t-0">
            <FilterBar filters={filters} onChange={onFilters} />
            <div className="flex flex-col gap-2 border-t pt-5">
                <div className="flex items-baseline justify-between">
                    <h3 className="text-sm font-semibold">{"On the map"}</h3>
                    <span className="text-xs tabular-nums text-muted-foreground">{f"{len(items)} items"}</span>
                </div>
                {error and <div className="flex items-center gap-3">
                    <p className="text-sm text-destructive">{error}</p>
                    <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { load_pins(); }}>{"Retry"}</Button>
                </div>}
                {if loading and len(items) == 0 {
                    <div className="flex flex-col gap-2">
                        <Skeleton className="h-12 w-full" />
                        <Skeleton className="h-12 w-full" />
                        <Skeleton className="h-12 w-full" />
                    </div>
                    skip;
                }}
                {if not loading and len(items) == 0 and not error {
                    <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed pt-8 pb-8 text-center">
                        <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-5 text-muted-foreground" />
                        <p className="text-sm font-medium">{"No places match"}</p>
                        <p className="text-xs text-muted-foreground">{"Widen the distance or clear a filter."}</p>
                    </div>
                    skip;
                }}
                <div className="-ml-2 -mr-2 flex max-h-[46svh] flex-col overflow-y-auto">
                    {for it in items {
                        <button key={it.id} type="button" onClick={lambda (e: MouseEvent) { focus_item(it); }} className={"flex items-start gap-3 rounded-md pt-2.5 pb-2.5 pl-2 pr-2 text-left transition-colors hover:bg-muted " + ("bg-muted" if it.id == focusId else "")}>
                            <span className="mt-1.5 size-2 shrink-0 rounded-full" style={{"backgroundColor": kind_color(it.kind)}} />
                            <span className="flex min-w-0 flex-1 flex-col">
                                <span className="truncate text-sm font-medium">{it.name}</span>
                                <span className="truncate text-xs text-muted-foreground">{it.when + ((" · " + it.venue) if it.venue else "")}</span>
                            </span>
                            <span className="shrink-0 text-xs tabular-nums text-muted-foreground">{f"{it.dist:.1f} mi"}</span>
                        </button>
                    }}
                </div>
            </div>
        </aside>
    </div>;
}
