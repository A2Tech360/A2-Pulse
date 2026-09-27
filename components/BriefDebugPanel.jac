"""Hidden My Monday debug panel (only with ?debug=1 in the URL): how every
candidate item for the current profile was scored, rule by rule.

Uses GenerateBrief(score_only=True, debug=True), so it never calls the LLM,
never overwrites the stored spoken brief and never writes to the log.
"""

import from .ui.button { Button }
sv import from ..services.pulse { GenerateBrief }

glob RULE_COLS: list[dict] = [
    {"id": "home_alert", "label": "Home", "hint": "Alert near home (+3)"},
    {"id": "route_alert", "label": "Route", "hint": "Alert on commute route (+2.6)"},
    {"id": "affects_place", "label": "Place", "hint": "Civic item affecting home or route (+2.2)"},
    {"id": "near_venue", "label": "Near", "hint": "Event at a venue near home or route (+1)"},
    {"id": "interest", "label": "Interest", "hint": "Tagged with an interest (+1.5 x weight)"},
    {"id": "follows", "label": "Follows", "hint": "From a followed organizer (+2)"},
    {"id": "weight", "label": "Weight", "hint": "Category weight multiplier from thumbs feedback"},
    {"id": "soon", "label": "Soon", "hint": "Civic or alert in the next 3 days (+0.6)"}
];

def debug_enabled -> bool {
    w: any = window;
    q: any = new(w.URLSearchParams, w.location.search);
    return q.get("debug") == "1";
}

def fmt(v: any) -> str {
    if not v {
        return "";
    }
    n: any = v;
    return n.toFixed(2);
}

def names(rows: any) -> str {
    if not rows {
        return "none";
    }
    return ", ".join([r["name"] for r in rows]) or "none";
}

def:pub BriefDebugPanel(persona: str) -> JsxElement {
    has trace: any = None,
        loading: bool = False,
        error: str = "",
        shown: bool = False;

    async def load(p: str) -> None {
        loading = True;
        error = "";
        try {
            res = root spawn GenerateBrief(persona=p, use_ai=False, debug=True, score_only=True);
            b: any = res.reports[0] if res.reports and len(res.reports) > 0 else None;
            trace = b.trace if b else None;
        } except Exception {
            error = "Could not load the score breakdown.";
        }
        loading = False;
    }

    can with [persona] entry {
        on: bool = debug_enabled();
        shown = on;
        if on {
            load(persona);
        }
    }

    if not shown {
        return <div hidden={True} />;
    }
    w: any = window;
    prof: any = trace["profile"] if trace else None;
    timing: any = trace["timing_ms"] if trace else None;
    llm: any = trace["llm"] if trace else None;
    rows: list[any] = trace["scored"] if trace else [];
    return <section className="flex flex-col gap-3 rounded-xl border border-dashed pt-4 pb-4 pl-4 pr-4 text-xs">
        <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="kicker text-muted-foreground">{"Debug: score breakdown for " + persona}</span>
            <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { load(persona); }} disabled={loading}>
                {"Loading..." if loading else "Refresh"}
            </Button>
        </div>
        {error and <p className="text-destructive">{error}</p>}
        {prof and <dl className="grid gap-x-4 gap-y-1 sm:grid-cols-[auto_1fr]">
            <dt className="text-muted-foreground">{"Home / via"}</dt>
            <dd>{names(prof["home"]) + " / " + names(prof["via"])}</dd>
            <dt className="text-muted-foreground">{"Commute"}</dt>
            <dd>{prof["commute"]}</dd>
            <dt className="text-muted-foreground">{"Interests"}</dt>
            <dd>{", ".join(prof["interests"]) or "none"}</dd>
            <dt className="text-muted-foreground">{"Follows"}</dt>
            <dd>{names(prof["follows"])}</dd>
            <dt className="text-muted-foreground">{"Weights"}</dt>
            <dd className="font-mono">{w.JSON.stringify(prof["weights"])}</dd>
            <dt className="text-muted-foreground">{"LLM"}</dt>
            <dd>{(llm["model"] if llm and llm["on"] else "off, using templates")}</dd>
            <dt className="text-muted-foreground">{"Timing"}</dt>
            <dd className="font-mono">{"profile " + fmt(timing["profile_ms"]) + " ms, relevance " + fmt(timing["relevance_ms"]) + " ms, actions " + fmt(timing["actions_ms"]) + " ms" if timing else ""}</dd>
        </dl>}
        {len(rows) > 0 and <div className="overflow-x-auto">
            <table className="w-full border-collapse text-right tabular-nums">
                <thead>
                    <tr className="border-b text-muted-foreground">
                        <th className="pt-1 pb-1 pr-2 text-left font-medium">{"#"}</th>
                        <th className="pt-1 pb-1 pr-2 text-left font-medium">{"Item"}</th>
                        {for c in RULE_COLS {
                            <th key={c["id"]} title={c["hint"]} className="pt-1 pb-1 pl-2 font-medium">{c["label"]}</th>
                        }}
                        <th className="pt-1 pb-1 pl-2 font-semibold text-foreground">{"Total"}</th>
                    </tr>
                </thead>
                <tbody>
                    {for s in rows {
                        <tr key={s["key"]} className={"border-b " + ("bg-primary/5 font-medium" if s["selected"] else "text-muted-foreground")}>
                            <td className="pt-1 pb-1 pr-2 text-left">{s["rank"]}</td>
                            <td className="pt-1 pb-1 pr-2 text-left" title={", ".join([r["detail"] for r in s["rules"]])}>
                                {s["name"]}
                                <span className="ml-1.5 text-muted-foreground">{s["kind"]}</span>
                            </td>
                            {for c in RULE_COLS {
                                <td key={c["id"]} className="pt-1 pb-1 pl-2">{fmt(s["by_rule"][c["id"]])}</td>
                            }}
                            <td className="pt-1 pb-1 pl-2 font-semibold text-foreground">{fmt(s["score"])}</td>
                        </tr>
                    }}
                </tbody>
            </table>
        </div>}
        <p className="text-muted-foreground">{"Highlighted rows are the top 5 in the brief. Full traces with Editor input, raw LLM output and per-stage timing: GenerateBrief(debug=true) or logs/briefs.jsonl."}</p>
    </section>;
}
