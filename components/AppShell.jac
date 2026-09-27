"""Masthead + tab nav. Owns shared filters, app-wide dark/light theme and the
live calendar sync that runs once when the app opens."""

import from "@jac/runtime" { Routes, Route, Navigate, Link, useLocation }
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
import from ..services.pulse { sync_online_events, SyncReport }

glob NAV_ITEMS: list[dict[str, any]] = [
    {"label": "My Monday", "to": "/monday"},
    {"label": "Map", "to": "/map"},
    {"label": "Network", "to": "/network"}
];

# Guards the open-time sync against remounts (and React's dev double-invoke).
glob APP_SYNC_STARTED: bool = False;

glob DAYS: list[str] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
glob MONTHS: list[str] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

def:pub AppShell() -> JsxElement {
    has filters: dict[str, any] = default_filters(),
        dark: bool = read_dark_pref(True),
        syncing: bool = False,
        syncNote: str = "",
        # Bumped when a sync adds or changes events, so pages reload their data.
        syncVersion: int = 0;

    path = useLocation().pathname;
    d: any = new(Date);
    day_name: str = DAYS[d.getDay() as int];
    month_name: str = MONTHS[d.getMonth() as int];
    dateline: str = f"{day_name}, {month_name} {d.getDate()}, {d.getFullYear()}";

    async can with entry {
        apply_app_theme(dark);
        sync_on_open();
    }

    async def sync_on_open {
        # Non-forced: the server skips it if calendars synced in the last few minutes.
        if APP_SYNC_STARTED {
            return;
        }
        APP_SYNC_STARTED = True;
        syncing = True;
        try {
            rep: SyncReport = await sync_online_events(False);
            if rep.created + rep.updated > 0 {
                syncVersion = syncVersion + 1;
                syncNote = (
                    f"{rep.created} new events" if rep.created > 0 else "Calendars up to date"
                );
            } elif not rep.ok {
                syncNote = "Calendar sync failed";
            }
        } except Exception {
            syncNote = "Calendar sync failed";
        }
        syncing = False;
    }

    can with [dark] entry {
        apply_app_theme(dark);
        write_dark_pref(dark);
    }

    def set_filters(nxt: dict[str, any]) {
        filters = nxt;
    }

    def toggle_theme {
        dark = not dark;
    }

    return
        <div className="flex min-h-svh flex-col overflow-x-hidden bg-background text-foreground">
            <header className="sticky top-0 z-30 border-b border-border bg-background/80 backdrop-blur">
                <div className="mx-auto flex h-14 w-full max-w-7xl items-center justify-between gap-4 pl-4 pr-4 sm:pl-6 sm:pr-6">
                    <Link to="/monday" className="flex items-center gap-2 text-foreground">
                        <span className="size-2.5 rounded-full bg-foreground" />
                        <span className="text-base font-semibold tracking-tight">
                            {"A2 Pulse"}
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
                        {(syncing or syncNote) and <span
                            className="hidden text-xs text-muted-foreground sm:inline"
                            aria-live="polite"
                        >
                            {("Syncing calendars…" if syncing else syncNote)}
                        </span>}
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
                        element={<Navigate to="/monday" replace={True} />}
                    />
                    <Route
                        path="/network"
                        element={
                            <NetworkPage
                                filters={filters}
                                onFilters={set_filters}
                                dark={dark}
                                syncVersion={syncVersion}
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
                                syncVersion={syncVersion}
                            />
                        }
                    />
                    <Route path="/monday" element={<MondayPage />} />
                    <Route
                        path="*"
                        element={<Navigate to="/monday" replace={True} />}
                    />
                </Routes>
            </main>
        </div>;
}
