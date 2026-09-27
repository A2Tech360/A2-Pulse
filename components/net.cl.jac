"""Network deadlines for the UI: every server call gets a timeout and a fallback,
so a slow or dead API never leaves a spinner running forever."""

glob NET_TIMEOUT_MS: int = 8000;

"""Resolve with p's value, or with fallback if p takes longer than ms.
A rejected p still rejects, so callers keep their try/except."""
def:pub with_timeout(p: any, fallback: any, ms: int = 8000) -> any {
    w: any = window;
    timer: any = new(w.Promise, lambda (resolve: any) -> None {
        setTimeout(lambda { resolve(fallback); }, ms);
    });
    return w.Promise.race([p, timer]);
}
