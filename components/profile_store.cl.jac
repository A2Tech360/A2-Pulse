"""This browser's own A2 Pulse profile: a random ID kept in localStorage, and a
shared (cached) request for the server-side profile so pages don't race to create it."""

sv import from ..services.pulse { get_profile }

glob UID_KEY: str = "a2pulse.uid";

def new_uid() -> str {
    w: any = window;
    if w.crypto and w.crypto.randomUUID {
        return w.crypto.randomUUID();
    }
    return "u" + w.Date.now().toString(36) + w.Math.random().toString(36).slice(2, 10);
}

"""Stable per-browser ID. Falls back to an in-memory ID when storage is unavailable."""
def:pub browser_uid() -> str {
    w: any = window;
    if w.__pulseUid {
        return w.__pulseUid;
    }
    uid: str = "";
    try {
        uid = localStorage.getItem(UID_KEY) or "";
    } except Exception {
        uid = "";
    }
    if not uid {
        uid = new_uid();
        try {
            localStorage.setItem(UID_KEY, uid);
        } except Exception {
            print("A2 Pulse: storage unavailable, profile lasts this session only");
        }
    }
    w.__pulseUid = uid;
    return uid;
}

"""Persona key the server walkers use for this browser's profile."""
def:pub my_persona() -> str {
    return "u-" + browser_uid();
}

"""This browser's profile dict (see get_profile). One request is shared by every caller;
pass fresh=True after saving to refetch."""
async def:pub load_profile(fresh: bool = False) -> dict {
    w: any = window;
    pending: any = None if fresh else w.__pulseProfileReq;
    if not pending {
        pending = get_profile(browser_uid());
        w.__pulseProfileReq = pending;
    }
    try {
        return await pending;
    } except Exception {
        w.__pulseProfileReq = None;
        return {"ok": False, "onboarded": False};
    }
}

"""Commute mode as a short label, e.g. "bikes"."""
def:pub commute_verb(mode: str) -> str {
    verbs: dict[str, str] = {"walk": "walks", "bike": "bikes", "car": "drives", "bus": "takes the bus"};
    return verbs[mode] if mode in verbs else mode;
}
