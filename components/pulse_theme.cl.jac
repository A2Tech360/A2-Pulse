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
    "category": "#78716c",
    "alert": "#f97316",
    "civic": "#10b981",
    "place": "#7c6f64",
    "source": "#7c6f64"
};

glob KIND_LABELS: dict[str, str] = {
    "event": "Event",
    "venue": "Venue",
    "organizer": "Organizer",
    "category": "Category",
    "alert": "Alert",
    "civic": "Civic",
    "place": "Place",
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
        "distance": 0.0,
        "reply": "",
        "query": ""
    };
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
