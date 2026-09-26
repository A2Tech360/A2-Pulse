"""Shared filter defaults, palette and labels used by every A2 Pulse tab."""

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
    "event": "#9b1c2e",
    "venue": "#3f5f8a",
    "organizer": "#b7791f",
    "category": "#1f1a17",
    "alert": "#d9480f",
    "civic": "#2f7d5b",
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
