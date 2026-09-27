"""GenerateBrief debug traces, appended as JSON lines to logs/briefs.jsonl (gitignored)."""

import json;
import time;
import uuid;
import threading;
import from pathlib { Path }
import from datetime { datetime }

glob _log_lock: threading.Lock = threading.Lock();

def log_path -> Path {
    return Path(str(__file__ or ".")).resolve().parent.parent / "logs" / "briefs.jsonl";
}

def new_trace(persona: str) -> dict[str, any] {
    return {"id": uuid.uuid4().hex[:12], "ts": datetime.now().isoformat(timespec="seconds"), "persona": persona};
}

"""Milliseconds between two time.perf_counter() readings."""
def ms(start: float, end: float = -1.0) -> float {
    stop = end if end >= 0.0 else time.perf_counter();
    return round((stop - start) * 1000, 2);
}

"""Append one trace line. Never raises; returns the log path, or "" when the write failed."""
def append_trace(trace: dict[str, any]) -> str {
    try {
        p = log_path();
        p.parent.mkdir(parents=True, exist_ok=True);
        line = json.dumps(trace, default=lambda (o: any) -> str { return str(o); }, ensure_ascii=False);
        with _log_lock {
            with open(p, "a", encoding="utf-8") as f {
                f.write(line + "\n");
            }
        }
        return str(p);
    } except Exception as e {
        print(f"brief trace: could not write log ({type(e).__name__})");
        return "";
    }
}

"""Total points per rule for one scored item, e.g. {"interest": 3.0, "weight": -0.6}."""
def sum_by_rule(rules: list[dict[str, any]]) -> dict[str, float] {
    out: dict[str, float] = {};
    for r in rules {
        name = str(r["rule"]);
        out[name] = round(out.get(name, 0.0) + float(r["points"]), 3);
    }
    return out;
}
