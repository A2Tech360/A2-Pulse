"""Masthead + tab nav. Owns shared filters and app-wide dark/light theme."""

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

glob NAV_ITEMS: list[dict[str, any]] = [
    {"label": "Network", "to": "/network"},
    {"label": "Map", "to": "/map"},
    {"label": "My Monday", "to": "/monday"}
];

glob DAYS: list[str] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
glob MONTHS: list[str] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

def:pub AppShell() -> JsxElement {
    has filters: dict[str, any] = default_filters(),
        dark: bool = read_dark_pref(True);

    path = useLocation().pathname;
    d: any = new(Date);
    day_name: str = DAYS[d.getDay() as int];
    month_name: str = MONTHS[d.getMonth() as int];
    dateline: str = f"{day_name}, {month_name} {d.getDate()}, {d.getFullYear()}";

    async can with entry {
        apply_app_theme(dark);
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
                    <Link to="/network" className="flex items-center gap-2 text-foreground">
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
                    <Route
                        path="*"
                        element={<Navigate to="/network" replace={True} />}
                    />
                </Routes>
            </main>
        </div>;
}
