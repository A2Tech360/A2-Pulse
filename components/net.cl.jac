"""Network deadlines for the UI: every server call gets a timeout and a fallback,
so a slow or dead API never leaves a spinner running forever.

Matches the GitHub stage design: brief full→template each get ~8 s (see
commit 01e3e438), so My Monday never sits on a hung LLM/scoring call."""

glob NET_TIMEOUT_MS: int = 8000;
glob BROWSE_TIMEOUT_MS: int = 25000;
# One GenerateBrief call: allow scoring + LLM (server templates if LLM is slow).
# GitHub used 8s×2 client retries; that stacked requests on a large live graph.
# Ranking is capped server-side; LLM has its own 8s deadline then templates.
glob BRIEF_AI_TIMEOUT_MS: int = 15000;
glob BRIEF_QUICK_TIMEOUT_MS: int = 8000;
glob PHOTO_TIMEOUT_MS: int = 25000;

def:pub browse_timeout_ms() -> int {
    return BROWSE_TIMEOUT_MS;
}

def:pub brief_ai_timeout_ms() -> int {
    return BRIEF_AI_TIMEOUT_MS;
}

def:pub brief_quick_timeout_ms() -> int {
    return BRIEF_QUICK_TIMEOUT_MS;
}

def:pub photo_timeout_ms() -> int {
    return PHOTO_TIMEOUT_MS;
}

"""Resolve with p's value, or with fallback if p takes longer than ms.
A rejected p still rejects, so callers keep their try/except."""
def:pub with_timeout(p: any, fallback: any, ms: int = 8000) -> any {
    w: any = window;
    timer: any = new(w.Promise, lambda (resolve: any) -> None {
        setTimeout(lambda { resolve(fallback); }, ms);
    });
    return w.Promise.race([p, timer]);
}

"""Wait for every promise (already started). Rejects if any promise rejects."""
def:pub gather(promises: list[any]) -> any {
    w: any = window;
    return w.Promise.all(promises);
}
