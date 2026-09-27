"""Masthead + tab nav. Owns shared filters and app-wide dark/light theme."""

import from "@jac/runtime" { Routes, Route, Navigate, Link, useLocation, useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Sun01Icon, Moon02Icon }
import from .pulse_theme {
    default_filters,
    read_dark_pref,
    write_dark_pref,
    apply_app_theme
}
import from .NetworkPage { NetworkPage }
import from .MapPage { MapPage }
import from .MondayPage { MondayPage }
import from .WelcomePage { WelcomePage }
import from .profile_store { load_profile }

glob NAV_ITEMS: list[dict] = [
    {"label": "Network", "to": "/network"},
    {"label": "Map", "to": "/map"},
    {"label": "My Monday", "to": "/monday"}
];

glob SKIP_KEY: str = "a2pulse.skipOnboarding";
glob TAGLINE: str = "Ann Arbor's living local graph";
glob FAVICON_URL: str = "/assets/favicon.svg";
glob PAGE_TITLES: dict[str, str] = {
    "/network": "Network",
    "/map": "Map",
    "/monday": "My Monday",
    "/welcome": "Welcome"
};

# Tab title per screen, e.g. "My Monday · A2 Pulse" (the dev server ignores jac.toml's title).
def set_page_title(path: str) {
    w: any = window;
    label: str = "";
    for (prefix, name) in PAGE_TITLES.items() {
        if path.startswith(prefix) {
            label = name;
        }
    }
    w.document.title = (label + " · A2 Pulse") if label else ("A2 Pulse · " + TAGLINE);
}

def ensure_favicon() {
    w: any = window;
    doc: any = w.document;
    if doc.querySelector("link[rel='icon']") {
        return;
    }
    link: any = doc.createElement("link");
    link.rel = "icon";
    link.type = "image/svg+xml";
    link.href = FAVICON_URL;
    doc.head.appendChild(link);
}

# "Just show me the demo" was chosen in this tab (sessionStorage, or in-memory fallback).
def skipped_onboarding() -> bool {
    w: any = window;
    if w.__pulseSkipOnboarding {
        return True;
    }
    try {
        return sessionStorage.getItem(SKIP_KEY) == "1";
    } except Exception {
        return False;
    }
}

glob DAYS: list[str] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
glob MONTHS: list[str] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

def:pub AppShell() -> JsxElement {
    has filters: dict = default_filters(),
        dark: bool = read_dark_pref(True);

    path = useLocation().pathname;
    nav = useNavigate();
    d: any = new(Date);
    day_name: str = DAYS[d.getDay() as int];
    month_name: str = MONTHS[d.getMonth() as int];
    dateline: str = f"{day_name}, {month_name} {d.getDate()}, {d.getFullYear()}";

    can with [path] entry {
        set_page_title(path);
    }

    async can with entry {
        apply_app_theme(dark);
        ensure_favicon();
        # New visitors start with onboarding (once per page load).
        start_path: str = path;
        prof: dict = await load_profile();
        if prof["ok"] and not prof["onboarded"] and not skipped_onboarding() and not start_path.startswith("/welcome") {
            nav("/welcome", {"replace": True});
        }
    }

    can with [dark] entry {
        apply_app_theme(dark);
        write_dark_pref(dark);
    }

    def set_filters(nxt: dict) {
        filters = nxt;
    }

    def toggle_theme {
        dark = not dark;
    }

    return
        <div className="flex min-h-svh flex-col overflow-x-hidden bg-background text-foreground">
            <header className="sticky top-0 z-30 border-b border-border bg-background/80 backdrop-blur">
                <div className="mx-auto flex h-14 w-full max-w-7xl items-center justify-between gap-4 pl-4 pr-4 sm:pl-6 sm:pr-6">
                    <Link to="/network" className="flex min-w-0 items-center gap-2 text-foreground" aria-label={"A2 Pulse, " + TAGLINE}>
                        <span className="size-2.5 shrink-0 rounded-full bg-foreground" />
                        <span className="flex min-w-0 flex-col leading-tight">
                            <span className="text-base font-semibold tracking-tight">
                                {"A2 Pulse"}
                            </span>
                            <span className="hidden truncate text-[11px] text-muted-foreground sm:block">
                                {TAGLINE}
                            </span>
                        </span>
                    </Link>
                    <nav className="flex items-center gap-1 rounded-lg bg-muted pt-1 pb-1 pl-1 pr-1">
                        {for item in NAV_ITEMS {
                            <Link
                                key={item["to"]}
                                to={item["to"]}
                                className={
                                    "rounded-md pt-1 pb-1 pl-3 pr-3 text-sm font-medium transition-colors "
                                    + (
                                        "bg-background text-foreground shadow-sm"
                                        if path.startswith(item["to"])
                                        else "text-muted-foreground hover:text-foreground"
                                    )
                                }
                            >
                                {item["label"]}
                            </Link>
                        }}
                    </nav>
                    <div className="flex items-center gap-3">
                        <span className="hidden text-xs text-muted-foreground md:inline">
                            {dateline}
                        </span>
                        <button
                            type="button"
                            onClick={lambda (e: MouseEvent) { toggle_theme(); }}
                            className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-2.5 py-1.5 text-xs font-medium text-foreground shadow-sm transition-colors hover:bg-muted"
                            aria-label="Toggle color theme"
                        >
                            <HugeiconsIcon
                                icon={Moon02Icon if dark else Sun01Icon}
                                strokeWidth={2}
                                className="size-3.5"
                            />
                            <span>{("Dark" if dark else "Light")}</span>
                        </button>
                    </div>
                </div>
            </header>
            <main className="flex flex-1 flex-col bg-background text-foreground">
                <Routes>
                    <Route
                        path="/"
                        element={<Navigate to="/network" replace={True} />}
                    />
                    <Route
                        path="/network"
                        element={
                            <NetworkPage
                                filters={filters}
                                onFilters={set_filters}
                                dark={dark}
                            />
                        }
                    />
                    <Route
                        path="/map"
                        element={
                            <MapPage
                                filters={filters}
                                onFilters={set_filters}
                                dark={dark}
                            />
                        }
                    />
                    <Route path="/monday" element={<MondayPage />} />
                    <Route path="/welcome" element={<WelcomePage dark={dark} />} />
                    <Route
                        path="*"
                        element={<Navigate to="/network" replace={True} />}
                    />
                </Routes>
            </main>
        </div>;
}
