"""Onboarding (/welcome): three quick steps that turn this browser's "You" profile
into a real person node (home, commute route, interests, follows), then open My Monday."""

import from "@jac/runtime" { useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowLeft01Icon, ArrowRight01Icon, Location01Icon, Tick02Icon }
import from .ui.button { Button }
import from .ui.skeleton { Skeleton }
import from .MapChrome { MapAddressSearch }
import from .profile_store { browser_uid, load_profile }
sv import from ..services.pulse { onboarding_options, nearest_place, route_places, save_profile }

glob STEP_COUNT: int = 3;
# One-tap homes / destinations (all are neighborhoods in the graph), for when address search is slow.
glob HOME_PRESETS: list[str] = ["pl-central", "pl-north", "pl-kerry", "pl-main"];
glob DEST_PRESETS: list[str] = ["pl-central", "pl-north", "pl-main", "pl-kerry"];
glob MODES: list[dict] = [
    {"id": "walk", "label": "Walk"},
    {"id": "bike", "label": "Bike"},
    {"id": "car", "label": "Car"},
    {"id": "bus", "label": "Bus"}
];
glob SKIP_KEY: str = "a2pulse.skipOnboarding";

def:pub OptionChip(label: str, active: bool, onToggle: Callable[[], None]) -> JsxElement {
    base = "inline-flex h-9 items-center gap-1.5 rounded-full border pl-3.5 pr-3.5 text-sm font-medium capitalize transition-colors ";
    tone = "border-foreground bg-foreground text-background"
        if active
        else "bg-card text-muted-foreground hover:border-foreground/40 hover:text-foreground";
    return
        <button type="button" aria-pressed={active} onClick={lambda (e: MouseEvent) { onToggle(); }} className={base + tone}>
            {active and <HugeiconsIcon icon={Tick02Icon} strokeWidth={2.5} className="size-3.5" />}
            {label}
        </button>;
}

def:pub WelcomePage(dark: bool = True) -> JsxElement {
    has step: int = 1,
        opts: dict = {"places": [], "categories": [], "organizers": []},
        ready: bool = False,
        editing: bool = False,
        home_key: str = "",
        home_label: str = "",
        home_lat: float = 0.0,
        home_lng: float = 0.0,
        home_dist: float = -1.0,
        commute: str = "",
        dest_key: str = "pl-central",
        dest_label: str = "",
        route: list[dict] = [],
        interests: list[str] = [],
        follows: list[str] = [],
        saving: bool = False,
        err: str = "";

    nav = useNavigate();

    async can with entry {
        o: dict = {"places": [], "categories": [], "organizers": []};
        try {
            o = await onboarding_options();
        } except Exception {
            err = "Could not load the neighborhoods. Check that the server is running.";
        }
        opts = o;
        prof: dict = await load_profile();
        if prof["ok"] and prof["onboarded"] {
            editing = True;
            home_key = prof["home_key"];
            home_label = prof["home_label"];
            home_lat = prof["home_lat"];
            home_lng = prof["home_lng"];
            commute = prof["commute"];
            dest_key = prof["dest_key"] or "pl-central";
            dest_label = prof["dest_label"];
            interests = prof["interests"];
            follows = prof["follows"];
        }
        ready = True;
    }

    can with (home_key, dest_key) entry {
        refresh_route();
    }

    async def refresh_route -> None {
        hk: str = home_key;
        dk: str = dest_key;
        if not hk {
            route = [];
            return;
        }
        w: any = window;
        seq: int = (w.__pulseRouteSeq or 0) + 1;
        w.__pulseRouteSeq = seq;
        rows: list[dict] = [];
        try {
            rows = await route_places(hk, dk);
        } except Exception {
            rows = [{"key": hk, "name": place_name(hk)}];
        }
        if w.__pulseRouteSeq == seq {
            route = rows;
        }
    }

    def place_name(key: str) -> str {
        places: list[dict] = opts["places"] or [];
        for pl in places {
            if pl["key"] == key {
                name: str = pl["name"];
                return name;
            }
        }
        return "";
    }

    # "1100, Beal Avenue, Ann Arbor, ..." -> "1100 Beal Avenue" (OSM splits house numbers off).
    def short_label(label: str) -> str {
        parts: list[str] = [x.strip() for x in label.split(",")];
        if len(parts) > 1 and len(parts[0]) <= 6 {
            return parts[0] + " " + parts[1];
        }
        return parts[0] if len(parts) > 0 else label;
    }

    def choose_home_preset(key: str) {
        home_key = key;
        home_label = "";
        home_lat = 0.0;
        home_lng = 0.0;
        home_dist = -1.0;
        err = "";
    }

    async def choose_home_address(lat: float, lng: float, label: str) -> None {
        err = "";
        home_label = label;
        home_lat = lat;
        home_lng = lng;
        try {
            hit: dict = await nearest_place(lat, lng);
            home_key = hit["key"];
            home_dist = hit["dist"];
        } except Exception {
            err = "Could not place that address. Pick a neighborhood below instead.";
        }
    }

    def choose_dest_preset(key: str) {
        dest_key = key;
        dest_label = "";
    }

    async def choose_dest_address(lat: float, lng: float, label: str) -> None {
        dest_label = label;
        try {
            hit: dict = await nearest_place(lat, lng);
            dest_key = hit["key"];
        } except Exception {
            err = "Could not place that address. Pick a spot below instead.";
        }
    }

    def toggle_interest(c: str) {
        if c in interests {
            interests = [x for x in interests if x != c];
        } else {
            interests = interests + [c];
        }
    }

    def toggle_follow(k: str) {
        if k in follows {
            follows = [x for x in follows if x != k];
        } else {
            follows = follows + [k];
        }
    }

    # Up to 5 organizers whose events share the most categories with the picked interests.
    def suggested_orgs() -> list[dict] {
        all_orgs: list[dict] = opts["organizers"] or [];
        out: list[dict] = [];
        best: int = 10;
        while best >= 0 and len(out) < 5 {
            for o in all_orgs {
                cats: list[str] = o["categories"];
                overlap: int = len([c for c in cats if c in interests]);
                wanted: bool = overlap > 0 or o["key"] in follows;
                if wanted and overlap == best and len(out) < 5 {
                    out.append(o);
                }
            }
            best = best - 1;
        }
        return out;
    }

    def org_sub(o: dict) -> str {
        kind: str = o["type"];
        cats: list[str] = o["categories"];
        return kind + " · " + ", ".join(cats[:3]);
    }

    def can_continue() -> bool {
        if step == 1 {
            return home_key != "";
        }
        if step == 2 {
            return commute != "";
        }
        return len(interests) >= 2;
    }

    def go_back(e: MouseEvent) {
        err = "";
        if step > 1 {
            step = step - 1;
        } else {
            nav("/monday");
        }
    }

    def go_next(e: MouseEvent) {
        if not can_continue() {
            return;
        }
        err = "";
        if step < STEP_COUNT {
            step = step + 1;
        } else {
            finish();
        }
    }

    async def finish -> None {
        if saving {
            return;
        }
        saving = True;
        err = "";
        via_keys: list[str] = [r["key"] for r in route];
        res: dict = {"ok": False, "error": ""};
        try {
            res = await save_profile(
                browser_uid(), home_key, home_lat, home_lng, home_label, commute,
                via_keys, dest_key, dest_label, interests, follows
            );
        } except Exception {
            res = {"ok": False, "error": ""};
        }
        if not res["ok"] {
            saving = False;
            err = res["error"] or "Could not save your profile. Try again.";
            return;
        }
        await load_profile(True);
        saving = False;
        nav("/monday?who=you");
    }

    def show_demo(e: MouseEvent) {
        w: any = window;
        w.__pulseSkipOnboarding = True;
        try {
            sessionStorage.setItem(SKIP_KEY, "1");
        } except Exception {
            print("A2 Pulse: session storage unavailable");
        }
        nav("/monday?who=student");
    }

    titles: list[str] = ["Where do you live?", "How do you get around?", "What are you into?"];
    subtitles: list[str] = [
        "Your neighborhood decides which closures and council items reach your brief.",
        "We watch your usual route for closures and detours.",
        "Pick at least two. Follow a few groups if you like."
    ];
    route_names: list[str] = [r["name"] for r in route];
    orgs: list[dict] = suggested_orgs();

    return
        <div className="mx-auto flex w-full max-w-xl flex-col gap-6 pt-8 pb-16 pl-4 pr-4 sm:pt-12 animate-in fade-in slide-in-from-bottom-2 duration-500">
            {#* progress + back *#}
            <div className="flex flex-col gap-3">
                <div className="flex items-center justify-between gap-3">
                    <button type="button" onClick={go_back} className="inline-flex items-center gap-1 text-sm text-muted-foreground transition-colors hover:text-foreground">
                        <HugeiconsIcon icon={ArrowLeft01Icon} strokeWidth={2} className="size-4" />
                        {"Back" if step > 1 else ("Cancel" if editing else "Back")}
                    </button>
                    <span className="text-xs font-medium tabular-nums text-muted-foreground">{f"Step {step} of {STEP_COUNT}"}</span>
                </div>
                <div className="grid grid-cols-3 gap-1.5" aria-hidden="true">
                    {for i in [1, 2, 3] {
                        <span key={i} className={"h-1 rounded-full transition-colors " + ("bg-foreground" if i <= step else "bg-muted")} />
                    }}
                </div>
            </div>

            <div className="flex flex-col gap-1.5">
                <h1 className="text-2xl font-semibold tracking-tight">{titles[step - 1]}</h1>
                <p className="text-sm text-muted-foreground">{subtitles[step - 1]}</p>
            </div>

            {if not ready {
                <div className="flex flex-col gap-3">
                    <Skeleton className="h-10 w-full" />
                    <Skeleton className="h-9 w-3/4" />
                </div>
                skip;
            }}

            {#* step 1: home *#}
            {ready and step == 1 and <div className="flex flex-col gap-4">
                <MapAddressSearch dark={dark} inline={True} placeholder="Your street address" onGoTo={lambda (lat: float, lng: float, label: str) { choose_home_address(lat, lng, label); }} />
                <div className="flex flex-col gap-2">
                    <span className="text-xs font-medium text-muted-foreground">{"Or tap your neighborhood"}</span>
                    <div className="flex flex-wrap gap-2">
                        {for k in HOME_PRESETS {
                            <OptionChip key={k} label={place_name(k)} active={home_key == k and not home_label} onToggle={lambda { choose_home_preset(k); }} />
                        }}
                    </div>
                </div>
                {home_key and <div className="flex items-start gap-3 rounded-lg border bg-card pt-3 pb-3 pl-3.5 pr-3.5">
                    <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="mt-0.5 size-4 shrink-0 text-primary" />
                    <p className="text-sm">
                        {"We'll treat you as "}
                        <span className="font-semibold">{place_name(home_key)}</span>
                        {"."}
                        {home_label and <span className="block truncate text-xs text-muted-foreground">
                            {short_label(home_label) + ((" · " + str(home_dist) + " mi from its center") if home_dist >= 0.0 else "")}
                        </span>}
                    </p>
                </div>}
            </div>}

            {#* step 2: commute *#}
            {ready and step == 2 and <div className="flex flex-col gap-5">
                <div className="grid grid-cols-4 gap-2">
                    {for m in MODES {
                        <button key={m["id"]} type="button" aria-pressed={commute == m["id"]} onClick={lambda (e: MouseEvent) { commute = m["id"]; }} className={"flex h-12 items-center justify-center rounded-lg border text-sm font-medium transition-colors " + ("border-foreground bg-foreground text-background" if commute == m["id"] else "bg-card text-muted-foreground hover:text-foreground")}>
                            {m["label"]}
                        </button>
                    }}
                </div>
                <div className="flex flex-col gap-2">
                    <span className="text-sm font-medium">{"Where do you go most days?"}<span className="ml-1.5 text-xs font-normal text-muted-foreground">{"Optional"}</span></span>
                    <div className="flex flex-wrap gap-2">
                        {for k in DEST_PRESETS {
                            <OptionChip key={k} label={place_name(k)} active={dest_key == k and not dest_label} onToggle={lambda { choose_dest_preset(k); }} />
                        }}
                    </div>
                    <MapAddressSearch dark={dark} inline={True} placeholder="Or search a workplace or class building" onGoTo={lambda (lat: float, lng: float, label: str) { choose_dest_address(lat, lng, label); }} />
                </div>
                {len(route_names) > 0 and <div className="flex flex-col gap-1 rounded-lg border bg-card pt-3 pb-3 pl-3.5 pr-3.5">
                    <span className="text-xs font-medium text-muted-foreground">{"We'll watch this route"}</span>
                    <p className="text-sm font-medium">{" → ".join(route_names)}</p>
                </div>}
            </div>}

            {#* step 3: interests + follows *#}
            {ready and step == 3 and <div className="flex flex-col gap-5">
                <div className="flex flex-wrap gap-2">
                    {for c in (opts["categories"] or []) {
                        <OptionChip key={c} label={c} active={c in interests} onToggle={lambda { toggle_interest(c); }} />
                    }}
                </div>
                <span className="text-xs text-muted-foreground">{f"{len(interests)} picked" + ("" if len(interests) >= 2 else ", pick at least 2")}</span>
                {len(orgs) > 0 and <div className="flex flex-col gap-2 border-t pt-4">
                    <span className="text-sm font-medium">{"Groups you might follow"}<span className="ml-1.5 text-xs font-normal text-muted-foreground">{"Optional"}</span></span>
                    <div className="flex flex-col gap-1.5">
                        {for o in orgs {
                            <button key={o["key"]} type="button" aria-pressed={o["key"] in follows} onClick={lambda (e: MouseEvent) { toggle_follow(o["key"]); }} className={"flex items-center justify-between gap-3 rounded-lg border pt-2.5 pb-2.5 pl-3.5 pr-3 text-left transition-colors " + ("border-foreground bg-muted" if o["key"] in follows else "bg-card hover:bg-muted")}>
                                <span className="flex min-w-0 flex-col">
                                    <span className="truncate text-sm font-medium">{o["name"]}</span>
                                    <span className="truncate text-xs capitalize text-muted-foreground">{org_sub(o)}</span>
                                </span>
                                <span className={"shrink-0 rounded-full pt-1 pb-1 pl-2.5 pr-2.5 text-xs font-medium " + ("bg-foreground text-background" if o["key"] in follows else "border text-muted-foreground")}>
                                    {"Following" if o["key"] in follows else "Follow"}
                                </span>
                            </button>
                        }}
                    </div>
                </div>}
            </div>}

            {err and <p className="text-sm text-destructive">{err}</p>}

            <div className="flex flex-col-reverse items-stretch gap-3 border-t pt-5 sm:flex-row sm:items-center sm:justify-between">
                {(not editing) and <button type="button" onClick={show_demo} className="text-sm text-muted-foreground underline-offset-4 hover:text-foreground hover:underline">
                    {"Just show me the demo"}
                </button>}
                {editing and <span />}
                <Button size="lg" onClick={go_next} disabled={not ready or not can_continue() or saving}>
                    {("Saving..." if saving else ("Save changes" if editing else "Build my Monday")) if step == STEP_COUNT else "Continue"}
                    <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} />
                </Button>
            </div>
        </div>;
}
