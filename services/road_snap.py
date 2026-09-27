"""Snap sparse closure/detour paths onto the road network.

Prefers Google Roads API (snapToRoads) when GOOGLE_MAPS_API_KEY is set;
falls back to OSRM. Results are cached in services/.road_snap_cache.json.

Map rendering should pass already-densified paths and use cache_only=True so
MapSnapshot never blocks on the network.
"""

from __future__ import annotations

import hashlib
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

CACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".road_snap_cache.json")
OSRM_URL = "http://router.project-osrm.org/route/v1/driving/"
MAX_OUT = 80
MIN_IN = 2


def _api_key() -> str:
    return (
        os.environ.get("GOOGLE_MAPS_API_KEY", "").strip()
        or os.environ.get("GOOGLE_API_KEY", "").strip()
    )


def _load_cache() -> dict[str, Any]:
    try:
        with open(CACHE_PATH) as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _save_cache(cache: dict[str, Any]) -> None:
    try:
        with open(CACHE_PATH, "w") as f:
            json.dump(cache, f, separators=(",", ":"))
    except OSError as ex:
        print(f"[road_snap] could not save cache: {ex}")


def _key(path: list[list[float]]) -> str:
    raw = json.dumps([[round(p[0], 5), round(p[1], 5)] for p in path], separators=(",", ":"))
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def _downsample(pts: list[list[float]], max_pts: int = MAX_OUT) -> list[list[float]]:
    if len(pts) <= max_pts:
        return pts
    step = (len(pts) - 1) / (max_pts - 1)
    out: list[list[float]] = []
    for i in range(max_pts):
        p = pts[int(round(i * step))]
        if not out or p != out[-1]:
            out.append(p)
    return out


def _clean(path: list[list[float]]) -> list[list[float]]:
    clean: list[list[float]] = []
    for p in path or []:
        if not isinstance(p, (list, tuple)) or len(p) < 2:
            continue
        try:
            lat = float(p[0])
            lng = float(p[1])
        except (TypeError, ValueError):
            continue
        if lat == 0.0 and lng == 0.0:
            continue
        pt = [lat, lng]
        if not clean or pt != clean[-1]:
            clean.append(pt)
    return clean


def _needs_snap(path: list[list[float]]) -> bool:
    if len(path) < MIN_IN:
        return False
    if len(path) >= 12:
        return False
    for i in range(len(path) - 1):
        dlat = abs(path[i][0] - path[i + 1][0])
        dlng = abs(path[i][1] - path[i + 1][1])
        if dlat > 0.0025 or dlng > 0.0025:
            return True
    return len(path) < 6


def _google_roads(path: list[list[float]]) -> list[list[float]]:
    key = _api_key()
    if not key:
        raise RuntimeError("no_google_key")
    # Roads API accepts up to 100 points; interpolate fills the centerline.
    pts = path[:100]
    q = urllib.parse.urlencode({
        "path": "|".join(f"{p[0]},{p[1]}" for p in pts),
        "interpolate": "true",
        "key": key,
    })
    url = "https://roads.googleapis.com/v1/snapToRoads?" + q
    req = urllib.request.Request(url, headers={"User-Agent": "A2-Pulse/0.1"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.load(resp)
    if data.get("error"):
        raise RuntimeError(str(data["error"]))
    out: list[list[float]] = []
    for sp in data.get("snappedPoints") or []:
        loc = sp.get("location") or {}
        lat = loc.get("latitude")
        lng = loc.get("longitude")
        if lat is None or lng is None:
            continue
        pt = [round(float(lat), 5), round(float(lng), 5)]
        if not out or pt != out[-1]:
            out.append(pt)
    if len(out) < 2:
        raise RuntimeError("roads_empty")
    return out


def _osrm_pair(a: list[float], b: list[float]) -> list[list[float]]:
    coords = f"{a[1]},{a[0]};{b[1]},{b[0]}"
    url = OSRM_URL + coords + "?overview=full&geometries=geojson"
    req = urllib.request.Request(url, headers={"User-Agent": "A2-Pulse/0.1"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.load(resp)
    if data.get("code") != "Ok":
        raise RuntimeError(str(data.get("code") or "osrm_error"))
    routes = data.get("routes") or []
    if not routes:
        raise RuntimeError("no_route")
    coords_out = (routes[0].get("geometry") or {}).get("coordinates") or []
    return [[round(lat, 5), round(lng, 5)] for lng, lat in coords_out]


def _osrm_route(path: list[list[float]]) -> list[list[float]]:
    snapped: list[list[float]] = []
    for i in range(len(path) - 1):
        part = _osrm_pair(path[i], path[i + 1])
        if not part:
            continue
        if not snapped:
            snapped.extend(part)
        else:
            snapped.extend(part[1:])
    if len(snapped) < 2:
        raise RuntimeError("osrm_empty")
    return snapped


def snap_path(path: list[list[float]], cache_only: bool = False) -> list[list[float]]:
    """Densify path along roads. cache_only skips network (safe for MapSnapshot)."""
    clean = _clean(path)
    if len(clean) < MIN_IN or not _needs_snap(clean):
        return clean

    cache = _load_cache()
    ck = _key(clean)
    hit = cache.get(ck)
    if isinstance(hit, list) and len(hit) >= 2:
        return hit
    if cache_only:
        return clean

    snapped: list[list[float]] = []
    try:
        snapped = _downsample(_google_roads(clean))
    except (urllib.error.URLError, TimeoutError, RuntimeError, ValueError, KeyError) as ex:
        print(f"[road_snap] Google Roads fallback ({ex})")
        try:
            snapped = _downsample(_osrm_route(clean))
        except (urllib.error.URLError, TimeoutError, RuntimeError, ValueError, KeyError) as ex2:
            print(f"[road_snap] OSRM fallback ({ex2})")
            return clean

    if len(snapped) >= 2:
        cache[ck] = snapped
        _save_cache(cache)
        return snapped
    return clean
