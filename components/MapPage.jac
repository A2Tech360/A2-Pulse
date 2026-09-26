"""Map tab: the same graph truth as pins and closure lines (MapSnapshot walker)."""

import "leaflet/dist/leaflet.css";
import from "leaflet" { default as L }
import from react { useEffect }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowUpRight01Icon, Location01Icon }
import from .ui.skeleton { Skeleton }
import from .ui.button { Button }
import from .FilterBar { FilterBar }
import from .pulse_theme { kind_color, kind_label }
sv import from ..services.pulse { MapSnapshot, MapItem }

glob CAMPUS_LAT: float = 42.2780;
glob CAMPUS_LNG: float = -83.7382;

def popup_html(it: MapItem) -> str {
    price = "";
    if it.kind == "event" {
        price = " · Free" if it.price == 0.0 else f" · ${it.price:.0f}";
    }
    dir_url = f"https://www.google.com/maps/dir/?api=1&destination={it.lat},{it.lng}";
    src = "";
    if it.source_url {
        src = f"<a href='{it.source_url}' target='_blank' rel='noreferrer' style='color:#9b1c2e'>Source: {it.source_name}</a> &middot; ";
    }
    return (
        f"<div style='min-width:210px'><div style='font:500 10px IBM Plex Mono,monospace;letter-spacing:.16em;text-transform:uppercase;color:{kind_color(it.kind)}'>{kind_label(it.kind)}{price}</div>"
        + f"<div style='font:700 17px Fraunces,Georgia,serif;margin:3px 0 4px'>{it.name}</div>"
        + f"<div style='font-size:12.5px;line-height:1.45'>{it.when}{(' · ' + it.venue) if it.venue else ''}</div>"
        + f"<div style='font-size:12px;color:#6b5e55;margin:6px 0'>{it.desc}</div>"
        + f"<div style='font:500 10.5px IBM Plex Mono,monospace;letter-spacing:.08em;text-transform:uppercase'>{src}<a href='{dir_url}' target='_blank' rel='noreferrer' style='color:#1f1a17'>Get directions</a></div></div>"
    );
}

def:pub MapPage(filters: dict, onFilters: Callable[[dict], None]) -> JsxElement {
    has items: list[MapItem] = [],
        loading: bool = True,
        error: str = "",
        focusId: str = "",
        mapEl: Ref[HTMLDivElement] = Ref(),
        mapRef: Ref[any] = Ref(None),
        layerRef: Ref[any] = Ref(None);

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

    # create the Leaflet map once; tear it down on unmount
    useEffect(lambda {
        if mapEl.current and not mapRef.current {
            m = L.map(mapEl.current, {"zoomControl": True, "scrollWheelZoom": True}).setView([CAMPUS_LAT, CAMPUS_LNG], 14);
            L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {"maxZoom": 19, "attribution": "&copy; OpenStreetMap contributors"}).addTo(m);
            mapRef.current = m;
            layerRef.current = L.layerGroup().addTo(m);
        }
        return lambda {
            if mapRef.current {
                mapRef.current.remove();
                mapRef.current = None;
                layerRef.current = None;
            }
        };
    }, []);

    # redraw pins, closure lines and the radius circle whenever data changes
    useEffect(lambda {
        layer: any = layerRef.current;
        if not layer {
            return;
        }
        layer.clearLayers();
        dist: float = filters["distance"] or 0.0;
        L.circleMarker([CAMPUS_LAT, CAMPUS_LNG], {"radius": 7, "color": "#faf6ee", "weight": 3, "fillColor": "#1f1a17", "fillOpacity": 1}).bindTooltip("You are here (Central Campus)").addTo(layer);
        if dist > 0.0 {
            L.circle([CAMPUS_LAT, CAMPUS_LNG], {"radius": dist * 1609.34, "color": "#9b1c2e", "weight": 1.5, "dashArray": "5 6", "fillColor": "#9b1c2e", "fillOpacity": 0.05}).addTo(layer);
        }
        for it in items {
            col = kind_color(it.kind);
            if len(it.path) > 1 {
                L.polyline(it.path, {"color": col, "weight": 6, "opacity": 0.75, "dashArray": "10 8"}).bindPopup(popup_html(it)).addTo(layer);
            }
            mk = L.circleMarker([it.lat, it.lng], {
                "radius": (11 if it.id == focusId else 8),
                "color": ("#1f1a17" if it.id == focusId else "#faf6ee"),
                "weight": 2.5,
                "fillColor": col,
                "fillOpacity": 0.95
            }).bindPopup(popup_html(it)).addTo(layer);
            if it.id == focusId {
                mk.openPopup();
            }
        }
    }, [items, focusId, filters]);

    def focus_item(it: MapItem) {
        focusId = it.id;
        if mapRef.current {
            mapRef.current.flyTo([it.lat, it.lng], 16, {"duration": 0.6});
        }
    }

    counts: dict[str, int] = {"event": 0, "organizer": 0, "alert": 0, "civic": 0};
    for it in items {
        counts[it.kind] = counts[it.kind] + 1;
    }

    return <div className="flex flex-1 flex-col lg:flex-row">
        <div className="relative min-h-[60svh] flex-1 lg:min-h-[calc(100svh-230px)]">
            <div ref={mapEl} className="absolute inset-0 z-0" />
            <div className="pointer-events-none absolute left-4 top-4 z-[500] flex max-w-sm flex-col gap-2 border border-foreground bg-card/95 pt-3 pb-3 pl-4 pr-4 shadow-[4px_4px_0_var(--foreground)] sm:left-6">
                <div className="flex items-center gap-2">
                    <span className="h-px w-8 bg-primary" />
                    <span className="kicker text-primary">{"Live · The Map"}</span>
                </div>
                <h2 className="font-display text-2xl font-black leading-tight sm:text-3xl">{"Same city. "}<span className="text-primary">{"Now with streets."}</span></h2>
                <div className="flex flex-wrap gap-3">
                    <span className="kicker flex items-center gap-1.5"><span className="size-2.5 rounded-full" style={{"backgroundColor": kind_color("event")}} />{f"{counts['event']} events"}</span>
                    <span className="kicker flex items-center gap-1.5"><span className="size-2.5 rounded-full" style={{"backgroundColor": kind_color("organizer")}} />{f"{counts['organizer']} clubs"}</span>
                    <span className="kicker flex items-center gap-1.5"><span className="size-2.5 rounded-full" style={{"backgroundColor": kind_color("alert")}} />{f"{counts['alert']} closures"}</span>
                    <span className="kicker flex items-center gap-1.5"><span className="size-2.5 rounded-full" style={{"backgroundColor": kind_color("civic")}} />{f"{counts['civic']} civic"}</span>
                </div>
            </div>
            {loading and <div className="absolute bottom-4 left-4 z-[500] kicker border bg-card pt-1.5 pb-1.5 pl-3 pr-3 sm:left-6">{"Refreshing pins..."}</div>}
        </div>

        <aside className="flex w-full flex-col gap-5 border-t bg-card/85 pt-5 pb-6 pl-5 pr-5 backdrop-blur lg:w-[400px] lg:border-l lg:border-t-0">
            <div className="flex flex-col gap-1">
                <span className="kicker text-muted-foreground">{"Filters stay in sync with the Network"}</span>
            </div>
            <FilterBar filters={filters} onChange={onFilters} />
            <div className="flex flex-col gap-2 border-t pt-4">
                <div className="flex items-baseline justify-between">
                    <h3 className="font-display text-xl font-bold">{"On the map"}</h3>
                    <span className="kicker tabular-nums text-muted-foreground">{f"{len(items)} items"}</span>
                </div>
                {error and <div className="flex items-center gap-3">
                    <p className="text-sm text-destructive">{error}</p>
                    <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { load_pins(); }}>{"Retry"}</Button>
                </div>}
                {if loading and len(items) == 0 {
                    <div className="flex flex-col gap-2">
                        <Skeleton className="h-14 w-full" />
                        <Skeleton className="h-14 w-full" />
                        <Skeleton className="h-14 w-full" />
                    </div>
                    skip;
                }}
                {if not loading and len(items) == 0 and not error {
                    <div className="flex flex-col items-center gap-2 border border-dashed pt-8 pb-8 text-center">
                        <div className="flex size-10 items-center justify-center bg-primary/10 text-primary">
                            <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-5" />
                        </div>
                        <p className="font-display text-lg font-bold">{"No pins match"}</p>
                        <p className="text-sm text-muted-foreground">{"Widen the distance or clear a filter."}</p>
                    </div>
                    skip;
                }}
                <div className="flex max-h-[46svh] flex-col overflow-y-auto">
                    {for it in items {
                        <button key={it.id} type="button" onClick={lambda (e: MouseEvent) { focus_item(it); }} className={"flex items-start gap-3 border-b pt-3 pb-3 text-left transition-colors hover:bg-muted/60 " + ("bg-muted" if it.id == focusId else "")}>
                            <span className="mt-1.5 size-2.5 shrink-0 rounded-full" style={{"backgroundColor": kind_color(it.kind)}} />
                            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                                <span className="truncate font-display text-base font-semibold leading-tight">{it.name}</span>
                                <span className="truncate text-xs text-muted-foreground">{it.when + ((" · " + it.venue) if it.venue else "")}</span>
                            </span>
                            <span className="kicker shrink-0 tabular-nums text-muted-foreground">{f"{it.dist:.1f} mi"}</span>
                        </button>
                    }}
                </div>
            </div>
        </aside>
    </div>;
}
