"""Shared filter defaults, palette, labels and app theme helpers."""

glob ALL_CATEGORIES: list[str] = [
    "music", "food", "sports", "academic", "social", "arts", "community",
    "outdoor", "civic", "networking"
];

glob KIND_OPTIONS: list[dict] = [
    {"value": "event", "label": "Events"},
    {"value": "organizer", "label": "Clubs"},
    {"value": "alert", "label": "Closures"},
    {"value": "civic", "label": "Civic"}
];

glob KIND_COLORS: dict[str, str] = {
    "event": "#e11d48",
    "venue": "#6366f1",
    "organizer": "#f59e0b",
    "category": "#38bdf8",
    "alert": "#f97316",
    "civic": "#10b981",
    "place": "#0d9488",
    "lens": "#fafaf9",
    "source": "#7c6f64"
};

glob KIND_LABELS: dict[str, str] = {
    "event": "Event",
    "venue": "Venue",
    "organizer": "Organizer",
    "category": "Topic",
    "alert": "Alert",
    "civic": "Civic",
    "place": "Place",
    "lens": "Browse",
    "source": "Source"
};

glob CAMPUS_LAT: float = 42.2780;
glob CAMPUS_LNG: float = -83.7382;
glob THEME_KEY: str = "a2pulse.dark";

def:pub all_categories() -> list[str] {
    return ALL_CATEGORIES;
}

def:pub kind_options() -> list[dict] {
    return KIND_OPTIONS;
}

def:pub campus_lat() -> float {
    return CAMPUS_LAT;
}

def:pub campus_lng() -> float {
    return CAMPUS_LNG;
}

def:pub default_filters() -> dict {
    return {
        "categories": [],
        "kinds": [],
        "price": "any",
        "time": "week",
        "date": "",
        "distance": 0.0,
        "reply": "",
        "query": ""
    };
}

glob SHORT_DAYS: list[str] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
glob SHORT_MONTHS: list[str] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
];

def _pad2(n: int) -> str {
    return f"0{n}" if n < 10 else str(n);
}

"""Upcoming calendar chips for the Network day bar (today + next N days)."""
def:pub future_date_chips(days: int = 14) -> list[dict] {
    out: list[dict] = [];
    now: any = new(Date);
    i: int = 0;
    while i < days {
        d: any = new(Date, now.getFullYear(), now.getMonth(), now.getDate() + i);
        y: int = d.getFullYear() as int;
        m: int = (d.getMonth() as int) + 1;
        day_n: int = d.getDate() as int;
        iso: str = f"{y}-{_pad2(m)}-{_pad2(day_n)}";
        label: str = "Today";
        if i == 1 {
            label = "Tomorrow";
        } elif i > 1 {
            label = f"{SHORT_DAYS[d.getDay() as int]} {SHORT_MONTHS[d.getMonth() as int]} {day_n}";
        }
        out.append({"iso": iso, "label": label});
        i += 1;
    }
    return out;
}

def:pub kind_color(kind: str) -> str {
    return KIND_COLORS[kind] if kind in KIND_COLORS else "#7c6f64";
}

def:pub kind_label(kind: str) -> str {
    return KIND_LABELS[kind] if kind in KIND_LABELS else kind;
}

def:pub read_dark_pref(fallback: bool = True) -> bool {
    try {
        raw: any = localStorage.getItem(THEME_KEY);
        if raw == "0" {
            return False;
        }
        if raw == "1" {
            return True;
        }
    } except Exception {
        return fallback;
    }
    return fallback;
}

def:pub write_dark_pref(dark: bool) {
    try {
        localStorage.setItem(THEME_KEY, "1" if dark else "0");
    } except Exception {
        return;
    }
}

def:pub apply_app_theme(dark: bool) {
    html_el: any = document.documentElement;
    if dark {
        html_el.classList.add("dark");
        html_el.style.colorScheme = "dark";
    } else {
        html_el.classList.remove("dark");
        html_el.style.colorScheme = "light";
    }
}
