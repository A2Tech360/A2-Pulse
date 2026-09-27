"""This browser's own A2 Pulse profile: a random ID kept in localStorage, and a
shared (cached) request for the server-side profile so pages don't race to create it."""

import from .net { with_timeout }
sv import from ..services.pulse { get_profile }

glob UID_KEY: str = "a2pulse.uid";
glob SKIP_KEY: str = "a2pulse.skipOnboarding";

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

"""Start fresh: give this browser a brand-new ID (and so a new, not-onboarded profile).
Used by /welcome?reset=1 for re-running onboarding on stage."""
def:pub reset_identity() -> str {
    w: any = window;
    uid: str = new_uid();
    try {
        localStorage.setItem(UID_KEY, uid);
    } except Exception {
        print("A2 Pulse: storage unavailable, new profile lasts this session only");
    }
    try {
        sessionStorage.removeItem(SKIP_KEY);
    } except Exception {
        print("A2 Pulse: session storage unavailable");
    }
    w.__pulseUid = uid;
    w.__pulseProfileReq = None;
    w.__pulseSkipOnboarding = False;
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
        pending = with_timeout(get_profile(browser_uid()), {"ok": False, "onboarded": False, "timeout": True});
        w.__pulseProfileReq = pending;
    }
    res: dict = {"ok": False, "onboarded": False};
    try {
        res = await pending;
    } except Exception {
        res = {"ok": False, "onboarded": False};
    }
    if not res["ok"] {
        w.__pulseProfileReq = None;    # don't cache a failure; the next call retries
    }
    return res;
}

"""Commute mode as a short label, e.g. "bikes"."""
def:pub commute_verb(mode: str) -> str {
    verbs: dict[str, str] = {"walk": "walks", "bike": "bikes", "car": "drives", "bus": "takes the bus"};
    return verbs[mode] if mode in verbs else mode;
}
