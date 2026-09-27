"""Citizen-style map markers: high-contrast circular emoji tokens.

Solid disc + thick rim + emoji. Gold rim = active/alert. Campus = blue puck.
Disc/rim adapt slightly so tokens read on both dark and light basemaps.
"""

glob KIND_EMOJI: dict[str, str] = {
    "event": "🎵",
    "venue": "🎭",
    "organizer": "👥",
    "alert": "🚧",
    "civic": "🏛️",
    "category": "📌",
    "place": "📍",
    "source": "📡",
    "campus": "📍"
};

glob RIM_ACTIVE: str = "#f5b942";
glob RIM_NORMAL: str = "#ffffff";
glob DISC_ON_DARK: str = "#222220";
glob DISC_ON_LIGHT: str = "#1c1917";

glob DARK_MAP_STYLE: list[dict] = [
    {"elementType": "geometry", "stylers": [{"color": "#232322"}]},
    {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#9a9a96"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#232322"}]},
    {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#323230"}]},
    {"featureType": "poi", "stylers": [{"visibility": "off"}]},
    {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#243024"}, {"visibility": "on"}]},
    {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6f886f"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#323230"}]},
    {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#a8a8a4"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#40403e"}]},
    {"featureType": "transit", "stylers": [{"visibility": "off"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#1a1f28"}]}
];

glob LIGHT_MAP_STYLE: list[dict] = [
    {"elementType": "geometry", "stylers": [{"color": "#f5f5f4"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#78716c"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#ffffff"}]},
    {"featureType": "poi", "stylers": [{"visibility": "off"}]},
    {"featureType": "transit", "stylers": [{"visibility": "simplified"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#e7e5e4"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#dbe4ea"}]}
];

def emoji_for(kind: str) -> str {
    # Dict lookup, not `match`: Jac 0.34 compiles client-side match to an empty function.
    return KIND_EMOJI[kind] if kind in KIND_EMOJI else "📍";
}

def:pub map_style_for(dark: bool) -> list[dict] {
    return DARK_MAP_STYLE if dark else LIGHT_MAP_STYLE;
}

def:pub map_bg_color(dark: bool) -> str {
    return "#232322" if dark else "#f5f5f4";
}

def:pub pin_sticker_svg(
    kind: str, focused: bool = False, dark: bool = True
) -> str {
    # Campus = blue location puck with theme-aware halo.
    if kind == "campus" {
        halo = "#93c5fd" if dark else "#3b82f6";
        return (
            "<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32' viewBox='0 0 32 32'>"
            + "<circle cx='16' cy='16' r='15' fill='"
            + halo
            + "' opacity='0.35'/>"
            + "<circle cx='16' cy='16' r='9' fill='#2563eb' stroke='#ffffff' stroke-width='3.5'/>"
            + "</svg>"
        );
    }

    emoji = emoji_for(kind);
    active = focused or kind == "alert";
    size: int = 56 if active else 48;
    disc = DISC_ON_DARK if dark else DISC_ON_LIGHT;
    rim = RIM_ACTIVE if active else RIM_NORMAL;
    # Halo ring: bright on dark maps, soft dark outline on light maps.
    outer = "#ffffff" if dark else "#1c1917";
    outer_op = "0.7" if dark else "0.18";
    rim_w = "3.5" if active else "3";
    font = "26" if active else "22";
    size_s = str(size);
    shadow = (
        "<feDropShadow dx='0' dy='2' stdDeviation='2.8' flood-color='#000000' flood-opacity='0.85'/>"
        if dark
        else "<feDropShadow dx='0' dy='2' stdDeviation='2.2' flood-color='#000000' flood-opacity='0.42'/>"
    );
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' width='"
        + size_s
        + "' height='"
        + size_s
        + "' viewBox='0 0 52 52'>"
        + "<defs>"
        + "<filter id='s' x='-50%' y='-50%' width='200%' height='200%'>"
        + shadow
        + "</filter>"
        + "</defs>"
        + "<circle cx='26' cy='26' r='24.5' fill='"
        + outer
        + "' opacity='"
        + outer_op
        + "'/>"
        + "<circle cx='26' cy='26' r='21' fill='"
        + disc
        + "' stroke='"
        + rim
        + "' stroke-width='"
        + rim_w
        + "' filter='url(#s)'/>"
        + "<text x='26' y='26' text-anchor='middle' dominant-baseline='central' font-size='"
        + font
        + "'>"
        + emoji
        + "</text></svg>"
    );
}

def:pub pin_data_url(
    kind: str, focused: bool = False, dark: bool = True
) -> str {
    w: any = window;
    return "data:image/svg+xml;charset=UTF-8," + w.encodeURIComponent(
        pin_sticker_svg(kind, focused, dark)
    );
}

def:pub maps_marker_icon(
    gm: any, kind: str, focused: bool = False, dark: bool = True
) -> dict {
    if kind == "campus" {
        return {
            "url": pin_data_url(kind, False, dark),
            "scaledSize": new(gm.Size, 32, 32),
            "anchor": new(gm.Point, 16, 16)
        };
    }
    active = focused or kind == "alert";
    size = 56 if active else 48;
    return {
        "url": pin_data_url(kind, focused, dark),
        "scaledSize": new(gm.Size, size, size),
        "anchor": new(gm.Point, size / 2, size / 2)
    };
}

def:pub sticker_img_url(kind: str, dark: bool = True) -> str {
    return pin_data_url(kind, False, dark);
}

def:pub kind_emoji(kind: str) -> str {
    return emoji_for(kind);
}
