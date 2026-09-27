"""Guards for speak_brief: a per-profile and per-IP rate limit, the caller's IP,
and the list of voices a caller may pick.

The limit is in memory (per server process) and sliding-window:
TTS_RATE_LIMIT speaks per TTS_RATE_WINDOW_S seconds (default 5 per 600).
"""

import os;
import sys;
import time;
import threading;
import from http.server { BaseHTTPRequestHandler }

glob _hits: dict[str, list[float]] = {},
     _lock: threading.Lock = threading.Lock(),
     _voice_ids: list[str] = [],
     _voice_ids_at: float = 0.0,
     VOICE_CACHE_S: float = 3600.0;

def _env_num(name: str, fallback: float) -> float {
    try {
        return float(os.environ.get(name, "") or fallback);
    } except ValueError {
        return fallback;
    }
}

def speak_limit -> int {
    return int(_env_num("TTS_RATE_LIMIT", 5.0));
}

def speak_window_s -> float {
    return _env_num("TTS_RATE_WINDOW_S", 600.0);
}

"""Record one speak for every key, or refuse if any key is at its limit.
Returns 0.0 when allowed, else seconds until the oldest hit leaves the window.
Refused attempts are not recorded."""
def rate_check(keys: list[str], limit: int, window: float, now: float = -1.0) -> float {
    t = now if now >= 0.0 else time.time();
    with _lock {
        retry = 0.0;
        for k in keys {
            recent = [h for h in _hits.get(k, []) if t - h < window];
            _hits[k] = recent;
            if len(recent) >= limit {
                retry = max(retry, recent[0] + window - t);
            }
        }
        if retry > 0.0 {
            return round(retry, 1);
        }
        for k in keys {
            _hits[k].append(t);
        }
        return 0.0;
    }
}

def reset_rate_limits {
    with _lock {
        _hits.clear();
    }
}

glob LOOPBACK: list[str] = ["127.0.0.1", "::1", "::ffff:127.0.0.1"];

"""Client IP from a peer address and its X-Forwarded-For header. The header is
trusted only from a loopback peer, i.e. our own proxy (the Vite dev server)."""
def _pick_ip(peer: str, forwarded: str) -> str {
    if peer in LOOPBACK {
        fwd = forwarded.split(",")[0].strip();
        if fwd {
            return fwd;
        }
    }
    return peer or "unknown";
}

"""IP of the HTTP client calling the current endpoint, read from the request
object on the call stack: a FastAPI/Starlette `request` (jac-scale, what
`jac start` serves) or an http.server handler (plain Jac server).
Call it from an async def:pub body before any await/to_thread: sync
def:pub functions run in a worker thread whose stack has no request.
Returns "unknown" when no request is found."""
def client_ip -> str {
    f: any = sys._getframe(1);
    while f is not None {
        loc: any = f.f_locals;
        req: any = loc.get("request");
        if req is not None and hasattr(req, "client") and hasattr(req, "headers") {
            peer = str(req.client.host) if req.client else "";
            return _pick_ip(peer, str(req.headers.get("x-forwarded-for", "") or ""));
        }
        h: any = loc.get("self");
        if isinstance(h, BaseHTTPRequestHandler) {
            return _pick_ip(str(h.client_address[0]), str(h.headers.get("X-Forwarded-For", "") or ""));
        }
        f = f.f_back;
    }
    return "unknown";
}

"""Voice ids a caller may pick: whatever list_voices() offers (account or
premade), cached for an hour so a speak does not re-list voices."""
def known_voice_ids(list_voices_fn: any) -> list[str] {
    if len(_voice_ids) == 0 or time.time() - _voice_ids_at > VOICE_CACHE_S {
        res: any = list_voices_fn();
        ids = [str(v["id"]) for v in res.get("voices", [])];
        if ids {
            _voice_ids = ids;
            _voice_ids_at = time.time();
        }
    }
    return list(_voice_ids);
}
