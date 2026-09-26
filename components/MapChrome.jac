"""Map chrome: legend, address search, setup / loading overlays."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Settings01Icon,
    Search01Icon,
    Cancel01Icon,
    Location01Icon
}
import from .map_markers { sticker_img_url }
import from .pulse_theme { kind_label }
sv import from ..services.pulse { suggest_places, geocode_address, PlaceSuggestion }

glob LEGEND_KINDS: list[str] = ["event", "venue", "organizer", "alert", "civic"];

def:pub MapAddressSearch(
    dark: bool,
    onGoTo: Callable[[float, float, str], None]
) -> JsxElement {
    has query: str = "",
        open: bool = False,
        busy: bool = False,
        err: str = "",
        places: list[PlaceSuggestion] = [],
        suggestSeq: int = 0,
        timerRef: Ref[any] = Ref(None);

    shell = "border-border bg-card/95 text-foreground shadow-lg backdrop-blur";
    muted = "text-muted-foreground";
    row_hover = "hover:bg-muted";

    def apply_suggestions(seq: int, rows: list[PlaceSuggestion]) {
        if seq != suggestSeq {
            return;
        }
        places = rows;
        open = len(rows) > 0;
    }

    async def fetch_suggestions(q: str) {
        ql = q.strip();
        if len(ql) < 2 {
            places = [];
            open = False;
            return;
        }
        suggestSeq = suggestSeq + 1;
        seq = suggestSeq;
        try {
            rows = await suggest_places(ql);
            apply_suggestions(seq, rows);
        } except Exception {
            if seq == suggestSeq {
                places = [];
                open = False;
            }
        }
    }

    def schedule_suggest(q: str) {
        if timerRef.current {
            clearTimeout(timerRef.current);
        }
        timerRef.current = setTimeout(
            lambda {
                fetch_suggestions(q);
            },
            280
        );
    }

    def on_change(e: ChangeEvent) {
        q = e.target.value;
        query = q;
        err = "";
        if len(q.strip()) < 2 {
            places = [];
            open = False;
            if timerRef.current {
                clearTimeout(timerRef.current);
                timerRef.current = None;
            }
            return;
        }
        open = len(places) > 0;
        schedule_suggest(q);
    }

    def pick_place(place: PlaceSuggestion) {
        query = place.label;
        open = False;
        err = "";
        places = [];
        onGoTo(place.lat, place.lng, place.label);
    }

    async def run_geocode {
        q = query.strip();
        if not q or busy {
            return;
        }
        busy = True;
        err = "";
        open = False;
        try {
            place = await geocode_address(q);
            busy = False;
            if not place.label {
                err = "No places match that search.";
                return;
            }
            query = place.label;
            onGoTo(place.lat, place.lng, place.label);
        } except Exception {
            busy = False;
            err = "Could not look up that address.";
        }
    }

    def run_search {
        q = query.strip();
        if not q or busy {
            return;
        }
        if len(places) > 0 {
            pick_place(places[0]);
            return;
        }
        run_geocode();
    }

    def on_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            e.preventDefault();
            run_search();
        } elif e.key == "Escape" {
            open = False;
        }
    }

    def clear_query(e: MouseEvent) {
        query = "";
        places = [];
        open = False;
        err = "";
        if timerRef.current {
            clearTimeout(timerRef.current);
            timerRef.current = None;
        }
    }

    def submit_click(e: MouseEvent) {
        run_search();
    }

    return
        <div className="pointer-events-auto absolute top-4 left-4 right-4 z-10 sm:right-auto sm:w-[min(100%,360px)]">
            <div
                className={
                    "flex items-center gap-2 rounded-full border pl-3 pr-1.5 py-1.5 "
                    + shell
                }
            >
                <HugeiconsIcon
                    icon={Search01Icon}
                    strokeWidth={2}
                    className={"size-4 shrink-0 " + muted}
                />
                <input
                    type="search"
                    value={query}
                    onChange={on_change}
                    onKeyDown={on_key}
                    onFocus={lambda (e: FocusEvent) {
                        if len(places) > 0 {
                            open = True;
                        }
                    }}
                    placeholder="Search address or place…"
                    className="min-w-0 flex-1 bg-transparent text-sm text-foreground outline-none placeholder:text-muted-foreground"
                    aria-label="Search map addresses"
                    aria-autocomplete="list"
                    autoComplete="off"
                />
                {query
                    and <button
                        type="button"
                        onClick={clear_query}
                        className={"rounded-full p-1.5 " + muted + " " + row_hover}
                        aria-label="Clear search"
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            strokeWidth={2}
                            className="size-3.5"
                        />
                    </button>}
                <button
                    type="button"
                    onClick={submit_click}
                    disabled={busy or not query.strip()}
                    className="rounded-full bg-foreground px-3 py-1.5 text-xs font-semibold text-background transition-colors hover:opacity-90 disabled:opacity-40"
                >
                    {( "…" if busy else "Go")}
                </button>
            </div>
            {err
                and <p className="mt-2 pl-3 text-xs font-medium text-destructive">{err}</p>}
            {open
                and len(places) > 0
                and <div
                    role="listbox"
                    className={"mt-2 overflow-hidden rounded-2xl border " + shell}
                >
                    {for place in places {
                        <button
                            key={place.id}
                            type="button"
                            role="option"
                            onClick={lambda (e: MouseEvent) { pick_place(place); }}
                            className={
                                "flex w-full items-start gap-2.5 px-3 py-2.5 text-left transition-colors "
                                + row_hover
                            }
                        >
                            <span className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-muted">
                                <HugeiconsIcon
                                    icon={Location01Icon}
                                    strokeWidth={2}
                                    className={"size-3.5 " + muted}
                                />
                            </span>
                            <span className="min-w-0 flex-1">
                                <span className="block truncate text-sm font-medium text-foreground">
                                    {place.title}
                                </span>
                                {place.sub
                                    and <span
                                        className={"block truncate text-xs " + muted}
                                    >
                                        {place.sub}
                                    </span>}
                            </span>
                        </button>
                    }}
                </div>}
        </div>;
}

def:pub MapLegend(dark: bool) -> JsxElement {
    return
        <div
            className="pointer-events-none absolute bottom-4 left-4 right-4 flex flex-wrap gap-2 sm:right-auto"
        >
            {for kind in LEGEND_KINDS {
                <div
                    key={kind}
                    className="flex items-center gap-1.5 rounded-full border border-border bg-card/95 pt-1 pb-1 pl-1.5 pr-2.5 text-xs font-medium text-foreground shadow-sm backdrop-blur"
                >
                    <img
                        src={sticker_img_url(kind, dark)}
                        alt=""
                        className="h-7 w-7 object-contain"
                    />
                    <span>{kind_label(kind)}</span>
                </div>
            }}
        </div>;
}

def:pub MapKeyMissing() -> JsxElement {
    return
        <div
            className="absolute inset-0 flex items-center justify-center pt-6 pb-6 pl-6 pr-6"
        >
            <div
                className="flex max-w-md flex-col gap-3 rounded-xl border border-border bg-card pt-6 pb-6 pl-6 pr-6 text-card-foreground shadow-sm"
            >
                <div
                    className="flex size-9 items-center justify-center rounded-lg bg-muted"
                >
                    <HugeiconsIcon
                        icon={Settings01Icon}
                        strokeWidth={2}
                        className="size-4 text-foreground"
                    />
                </div>
                <h3 className="text-lg font-semibold tracking-tight text-foreground">
                    {"Connect Google Maps"}
                </h3>
                <ol
                    className="flex list-decimal flex-col gap-1.5 pl-4 text-sm text-muted-foreground"
                >
                    <li>
                        {"In Google Cloud Console, enable the Maps JavaScript API, then create an API key."}
                    </li>
                    <li>
                        {"Open Settings (gear icon) > Environment and add GOOGLE_MAPS_API_KEY."}
                    </li>
                    <li>{"Restart the preview. The map loads here."}</li>
                </ol>
                <p className="text-xs text-muted-foreground">
                    {"Address search works without Maps. The list on the right works without a key."}
                </p>
            </div>
        </div>;
}

def:pub MapLoading() -> JsxElement {
    return
        <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-sm text-muted-foreground">
                {"Loading Google Maps..."}
            </span>
        </div>;
}
