"""Google Maps loader + overlay helpers — all Jac, thin browser interop."""

import from .map_markers {
    maps_marker_icon,
    map_style_for,
    kind_emoji,
    map_bg_color,
    primary_category
}
import from .pulse_theme { kind_color, kind_label, campus_lat, campus_lng }
sv import from ..services.pulse { MapItem }

def:pub load_google_maps(key: str, on_ready: Callable[[], None]) {
    w: any = window;
    if w.google and w.google.maps {
        on_ready();
        return;
    }
    existing: any = document.getElementById("gmaps-js");
    if existing {
        existing.addEventListener("load", lambda { on_ready(); });
        return;
    }
    s: any = document.createElement("script");
    s.id = "gmaps-js";
    s.src = "https://maps.googleapis.com/maps/api/js?key=" + key + "&v=weekly";
    s.async = True;
    s.onload = lambda { on_ready(); };
    doc: any = document;
    doc.head.appendChild(s);
}

def:pub map_popup_html(
    it: MapItem, dark: bool = True, overview: str = "", tip: str = ""
) -> str {
    price = "";
    if it.kind == "event" and it.price >= 0.0 {    # -1 = price unknown: show nothing
        price = " · Free" if it.price == 0.0 else " · $" + str(int(it.price));
    }
    dir_url = (
        "https://www.google.com/maps/dir/?api=1&destination="
        + str(it.lat)
        + ","
        + str(it.lng)
    );
    when_bits = it.when if it.when else "";
    if it.venue {
        when_bits = when_bits + (" · " if when_bits else "") + it.venue;
    }
    body_text = overview if overview else it.desc;
    tip_text = tip;
    emoji = kind_emoji(it.kind, it.categories);
    topic = primary_category(it.categories);
    # Match app theme: dark → gray bubble + light type; light → light bubble + dark type.
    bg = "#232322" if dark else "#fafaf9";
    fg = "#f5f5f4" if dark else "#0c0a09";
    muted = "#a8a29e" if dark else "#57534e";
    body = "#d6d3d1" if dark else "#292524";
    link = "#f5b942" if dark else "#b45309";
    shadow = (
        "0 10px 28px rgba(0,0,0,0.45)"
        if dark
        else "0 10px 28px rgba(0,0,0,0.28)"
    );
    return (
        "<div style='max-width:280px;font-family:Geist Variable,system-ui,sans-serif;"
        + "background:"
        + bg
        + ";color:"
        + fg
        + ";border-radius:16px;padding:12px 14px 14px;"
        + "box-shadow:"
        + shadow
        + ";border:none'>"
        + "<div style='display:flex;align-items:center;gap:8px;margin-bottom:6px;padding-right:18px'>"
        + "<span style='font-size:18px;line-height:1'>"
        + emoji
        + "</span>"
        + "<span style='font-size:11px;color:"
        + muted
        + ";font-weight:600;letter-spacing:0.02em'>"
        + kind_label(it.kind)
        + (
            (" · " + topic)
                if topic and it.kind == "event"
                else ""
        )
        + price
        + "</span></div>"
        + "<div style='font-size:15px;font-weight:650;line-height:1.25;color:"
        + fg
        + "'>"
        + it.name
        + "</div>"
        + (
            "<div style='font-size:12px;color:"
            + muted
            + ";margin-top:4px'>"
            + when_bits
            + "</div>"
            if when_bits
            else ""
        )
        + (
            "<div style='font-size:12px;color:"
            + body
            + ";margin-top:8px;line-height:1.45'>"
            + body_text
            + "</div>"
            if body_text
            else ""
        )
        + (
            "<div style='font-size:11px;color:"
            + muted
            + ";margin-top:8px;font-weight:600'>"
            + tip_text
            + "</div>"
            if tip_text
            else ""
        )
        + "<div style='margin-top:10px'>"
        + "<a href='"
        + dir_url
        + "' target='_blank' rel='noreferrer' style='color:"
        + link
        + ";font-size:12px;"
        + "font-weight:600;text-decoration:none'>Directions</a></div></div>"
    );
}

def bind_marker_click(
    mk: any,
    info: any,
    map_obj: any,
    html: str,
    item_id: str,
    on_focus: Callable[[str], None]
) {
    # Separate fn so Jac doesn't hoist loop vars into one shared closure.
    captured_html = html;
    captured_id = item_id;
    captured_mk = mk;
    mk.addListener(
        "click",
        lambda {
            on_focus(captured_id);
            info.setContent(captured_html);
            info.open(map_obj, captured_mk);
        }
    );
}

def bind_line_click(line: any, info: any, map_obj: any, html: str) {
    captured_html = html;
    line.addListener(
        "click",
        lambda (ev: any) {
            info.setContent(captured_html);
            info.setPosition(ev.latLng);
            info.open(map_obj);
        }
    );
}

def:pub create_pulse_map(el: any, dark: bool) -> dict {
    w: any = window;
    gm: any = w.google.maps;
    map_obj: any = new(
        gm.Map,
        el,
        {
            "center": {"lat": campus_lat(), "lng": campus_lng()},
            "zoom": 14,
            "styles": map_style_for(dark),
            "disableDefaultUI": True,
            "zoomControl": True,
            "fullscreenControl": True,
            "gestureHandling": "greedy",
            "backgroundColor": map_bg_color(dark)
        }
    );
    info: any = new(gm.InfoWindow, {"maxWidth": 280, "pixelOffset": new(gm.Size, 0, -8)});
    set_map_theme_class(el, dark);
    return {"map": map_obj, "info": info, "gm": gm};
}

def set_map_theme_class(el: any, dark: bool) {
    if not el {
        return;
    }
    host: any = el.parentElement if el.parentElement else el;
    host.classList.remove("pulse-map-dark");
    host.classList.remove("pulse-map-light");
    host.classList.add("pulse-map-dark" if dark else "pulse-map-light");
}

def:pub apply_map_theme(map_obj: any, dark: bool, map_el: any = None) {
    if not map_obj {
        return;
    }
    map_obj.setOptions(
        {
            "styles": map_style_for(dark),
            "backgroundColor": map_bg_color(dark)
        }
    );
    if map_el {
        set_map_theme_class(map_el, dark);
    }
}

def:pub clear_overlays(overlays: list[any]) {
    for o in overlays {
        o.setMap(None);
    }
}

def:pub sync_map_overlays(
    map_obj: any,
    info: any,
    items: list[MapItem],
    focus_id: str,
    distance_mi: float,
    dark: bool,
    on_focus: Callable[[str], None],
    overviews: dict = {}
) -> list[any] {
    if not map_obj {
        return [];
    }
    w: any = window;
    gm: any = w.google.maps;
    fresh: list[any] = [];
    fresh.append(
        new(
            gm.Marker,
            {
                "position": {"lat": campus_lat(), "lng": campus_lng()},
                "map": map_obj,
                "title": "Central Campus",
                "zIndex": 1,
                "icon": maps_marker_icon(gm, "campus", False, dark)
            }
        )
    );
    if distance_mi > 0.0 {
        ring_col = "#f5f5f4" if dark else "#1c1917";
        fresh.append(
            new(
                gm.Circle,
                {
                    "map": map_obj,
                    "center": {"lat": campus_lat(), "lng": campus_lng()},
                    "radius": distance_mi * 1609.34,
                    "strokeColor": ring_col,
                    "strokeOpacity": 0.35,
                    "strokeWeight": 1,
                    "fillColor": ring_col,
                    "fillOpacity": 0.04
                }
            )
        );
    }
    for it in items {
        col = "#f5b942" if it.kind == "alert" else kind_color(it.kind);
        ov_blurb = "";
        ov_tip = "";
        if it.id in overviews {
            raw: any = overviews[it.id];
            try {
                b = raw["blurb"];
                if b {
                    ov_blurb = str(b);
                }
                t = raw["tip"];
                if t {
                    ov_tip = str(t);
                }
            } except Exception {
                if raw {
                    ov_blurb = str(raw);
                }
            }
        }
        html = map_popup_html(it, dark, ov_blurb, ov_tip);
        if len(it.path) > 1 {
            line: any = new(
                gm.Polyline,
                {
                    "map": map_obj,
                    "path": [{"lat": p[0], "lng": p[1]} for p in it.path],
                    "strokeColor": col,
                    "strokeOpacity": 0.8,
                    "strokeWeight": 5
                }
            );
            bind_line_click(line, info, map_obj, html);
            fresh.append(line);
        }
        mk: any = new(
            gm.Marker,
            {
                "position": {"lat": it.lat, "lng": it.lng},
                "map": map_obj,
                "title": it.name,
                "zIndex": (20 if it.id == focus_id else 10),
                "icon": maps_marker_icon(
                    gm, it.kind, it.id == focus_id, dark, it.categories
                )
            }
        );
        bind_marker_click(mk, info, map_obj, html, it.id, on_focus);
        if it.id == focus_id {
            info.setContent(html);
            info.open(map_obj, mk);
        }
        fresh.append(mk);
    }
    return fresh;
}

def:pub pan_to_item(map_obj: any, lat: float, lng: float) {
    if not map_obj {
        return;
    }
    map_obj.panTo({"lat": lat, "lng": lng});
    map_obj.setZoom(16);
}

def nominatim_geocode(
    query: str,
    on_ok: Callable[[dict], None],
    on_err: Callable[[str], None]
) {
    w: any = window;
    q = query.strip();
    low = q.lower();
    if "ann arbor" not in low and "michigan" not in low and ", mi" not in low {
        q = q + ", Ann Arbor, MI, USA";
    }
    url = (
        "https://nominatim.openstreetmap.org/search?format=json&limit=1&q="
        + w.encodeURIComponent(q)
    );
    ok_cb = on_ok;
    err_cb = on_err;
    fetch(
        url,
        {
            "headers": {
                "Accept": "application/json"
            }
        }
    ).then(
        lambda (resp: any) {
            if not resp.ok {
                err_cb("Could not look up that address.");
                return None;
            }
            return resp.json();
        }
    ).then(
        lambda (data: any) {
            if not data {
                return;
            }
            if len(data) > 0 {
                row: any = data[0];
                ok_cb(
                    {
                        "lat": float(row["lat"]),
                        "lng": float(row["lon"]),
                        "label": row["display_name"]
                    }
                );
            } else {
                err_cb("No places match that search.");
            }
        }
    ).catch(
        lambda (e: any) {
            err_cb("Could not look up that address.");
        }
    );
}

def split_place_label(display: str) -> dict {
    parts = display.split(",");
    if len(parts) == 0 {
        return {"title": display, "sub": ""};
    }
    title = parts[0].strip();
    rest: list[str] = [];
    i = 1;
    while i < len(parts) and len(rest) < 3 {
        bit = parts[i].strip();
        if bit {
            rest.append(bit);
        }
        i += 1;
    }
    return {"title": title, "sub": ", ".join(rest)};
}

def:pub suggest_places(
    query: str,
    on_ok: Callable[[list[dict]], None]
) {
    w: any = window;
    q = query.strip();
    ok_cb = on_ok;
    if len(q) < 2 {
        ok_cb([]);
        return;
    }
    low = q.lower();
    bias = q;
    if "ann arbor" not in low and "michigan" not in low and ", mi" not in low {
        bias = q + ", Ann Arbor, MI";
    }
    # viewbox roughly covers Ann Arbor metro (left, top, right, bottom).
    url = (
        "https://nominatim.openstreetmap.org/search?format=json&addressdetails=0"
        + "&limit=3&countrycodes=us"
        + "&viewbox=-83.90,42.36,-83.62,42.20&bounded=0&q="
        + w.encodeURIComponent(bias)
    );
    fetch(
        url,
        {
            "headers": {
                "Accept": "application/json"
            }
        }
    ).then(
        lambda (resp: any) {
            if not resp.ok {
                return [];
            }
            return resp.json();
        }
    ).then(
        lambda (data: any) {
            out: list[dict] = [];
            if not data {
                ok_cb(out);
                return;
            }
            for row in data {
                if len(out) >= 3 {
                    break;
                }
                display = str(row["display_name"]);
                bits = split_place_label(display);
                out.append(
                    {
                        "id": str(row["place_id"]),
                        "title": bits["title"],
                        "sub": bits["sub"],
                        "label": display,
                        "lat": float(row["lat"]),
                        "lng": float(row["lon"])
                    }
                );
            }
            ok_cb(out);
        }
    ).catch(
        lambda (e: any) {
            ok_cb([]);
        }
    );
}

def:pub geocode_query(
    query: str,
    on_ok: Callable[[dict], None],
    on_err: Callable[[str], None]
) {
    w: any = window;
    q = query.strip();
    if not q {
        on_err("Enter an address or place name.");
        return;
    }
    ok_cb = on_ok;
    err_cb = on_err;
    if not w.google or not w.google.maps {
        nominatim_geocode(q, ok_cb, err_cb);
        return;
    }
    gm: any = w.google.maps;
    geo: any = new(gm.Geocoder);
    sw = new(gm.LatLng, campus_lat() - 0.18, campus_lng() - 0.22);
    ne = new(gm.LatLng, campus_lat() + 0.18, campus_lng() + 0.22);
    bounds = new(gm.LatLngBounds, sw, ne);
    geo.geocode(
        {
            "address": q,
            "bounds": bounds,
            "region": "us"
        },
        lambda (results: any, status: any) {
            if status == "OK" and results and len(results) > 0 {
                r: any = results[0];
                loc: any = r.geometry.location;
                ok_cb(
                    {
                        "lat": loc.lat(),
                        "lng": loc.lng(),
                        "label": r.formatted_address
                    }
                );
            } else {
                # Geocoding API often disabled on Maps-only keys — fall back.
                nominatim_geocode(q, ok_cb, err_cb);
            }
        }
    );
}

def search_pin_html(label: str, dark: bool) -> str {
    bg = "#232322" if dark else "#fafaf9";
    fg = "#f5f5f4" if dark else "#0c0a09";
    muted = "#a8a29e" if dark else "#57534e";
    return (
        "<div style='max-width:240px;font-family:Geist Variable,system-ui,sans-serif;"
        + "background:"
        + bg
        + ";color:"
        + fg
        + ";border-radius:16px;padding:12px 14px;box-shadow:0 10px 28px rgba(0,0,0,0.35);border:none'>"
        + "<div style='font-size:11px;color:"
        + muted
        + ";font-weight:600;letter-spacing:0.02em;margin-bottom:4px'>Search</div>"
        + "<div style='font-size:14px;font-weight:650;line-height:1.3'>"
        + label
        + "</div></div>"
    );
}

def:pub place_search_pin(
    map_obj: any,
    info: any,
    dark: bool,
    lat: float,
    lng: float,
    label: str,
    prev: any
) -> any {
    if not map_obj {
        return None;
    }
    if prev {
        prev.setMap(None);
    }
    w: any = window;
    gm: any = w.google.maps;
    mk: any = new(
        gm.Marker,
        {
            "position": {"lat": lat, "lng": lng},
            "map": map_obj,
            "title": label,
            "zIndex": 40,
            "icon": maps_marker_icon(gm, "place", True, dark)
        }
    );
    if info {
        info.setContent(search_pin_html(label, dark));
        info.open(map_obj, mk);
    }
    pan_to_item(map_obj, lat, lng);
    return mk;
}

def:pub clear_search_pin(prev: any) {
    if prev {
        prev.setMap(None);
    }
}
