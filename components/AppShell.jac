"""Masthead + tab nav. Owns the shared filters so Network, Map and Monday stay in sync."""

import from "@jac/runtime" { Routes, Route, Navigate, Link, useLocation }
import from .pulse_theme { default_filters }
import from .NetworkPage { NetworkPage }
import from .MapPage { MapPage }
import from .MondayPage { MondayPage }

glob NAV_ITEMS: list[dict] = [
    {"label": "Network", "to": "/network"},
    {"label": "Map", "to": "/map"},
    {"label": "My Monday", "to": "/monday"}
];

glob DAYS: list[str] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
glob MONTHS: list[str] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

def:pub AppShell() -> JsxElement {
    has filters: dict = default_filters();

    path = useLocation().pathname;
    d: any = new(Date);
    day_name: str = DAYS[d.getDay() as int];
    month_name: str = MONTHS[d.getMonth() as int];
    dateline: str = f"{day_name}, {month_name} {d.getDate()}, {d.getFullYear()}";

    def set_filters(nxt: dict) {
        filters = nxt;
    }

    return <div className="flex min-h-svh flex-col">
        <header className="rule-double bg-background/85 backdrop-blur">
            <div className="mx-auto w-full max-w-7xl pl-4 pr-4 sm:pl-6 sm:pr-6">
                <div className="flex items-center justify-between gap-4 pt-4">
                    <span className="kicker hidden italic text-primary sm:inline">{"Ann Arbor's living local graph"}</span>
                    <span className="kicker italic text-muted-foreground">{dateline}</span>
                </div>
                <Link to="/network" className="block text-center">
                    <h1 className="font-display text-5xl font-black leading-none tracking-tight sm:text-6xl md:text-7xl">
                        {"A2 "}<span className="text-primary">{"Pulse"}</span>
                    </h1>
                </Link>
                <nav className="mt-3 flex flex-wrap items-center justify-center gap-1.5 border-t pt-3 pb-3 sm:gap-3">
                    {for item in NAV_ITEMS {
                        <Link
                            key={item["to"]}
                            to={item["to"]}
                            className={"kicker border pt-1.5 pb-1.5 pl-3 pr-3 transition-colors " + ("border-foreground bg-foreground text-background" if path.startswith(item["to"]) else "border-border text-muted-foreground hover:border-foreground hover:text-foreground")}
                        >
                            {item["label"]}
                        </Link>
                    }}
                </nav>
            </div>
        </header>
        <main className="flex flex-1 flex-col">
            <Routes>
                <Route path="/" element={<Navigate to="/network" replace={True} />} />
                <Route path="/network" element={<NetworkPage filters={filters} onFilters={set_filters} />} />
                <Route path="/map" element={<MapPage filters={filters} onFilters={set_filters} />} />
                <Route path="/monday" element={<MondayPage />} />
                <Route path="*" element={<Navigate to="/network" replace={True} />} />
            </Routes>
        </main>
        <footer className="border-t">
            <div className="mx-auto flex w-full max-w-7xl flex-wrap items-center justify-between gap-2 pt-4 pb-4 pl-4 pr-4 sm:pl-6 sm:pr-6">
                <span className="kicker text-muted-foreground">{"One Jac graph. Three ways to live in your city."}</span>
                <span className="kicker text-muted-foreground">{"A2 Pulse " + str(d.getFullYear())}</span>
            </div>
        </footer>
    </div>;
}
