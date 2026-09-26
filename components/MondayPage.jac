"""My Monday: persona-aware brief from the Monday crew walkers, read aloud."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { SparklesIcon, ArrowUpRight01Icon, ThumbsUpIcon, ThumbsDownIcon, PlayIcon, StopIcon, Calendar03Icon }
import from .ui.button { Button }
import from .ui.skeleton { Skeleton }
import from .pulse_theme { kind_color, kind_label }
sv import from ..services.pulse { GenerateBrief, Feedback, Brief, BriefItem, list_personas }

glob PERSONA_TABS: list[dict] = [
    {"id": "student", "label": "Student", "hint": "Jordan, North Campus, bikes"},
    {"id": "shop", "label": "Shop owner", "hint": "Maya, Main St, drives"},
    {"id": "custom", "label": "You", "hint": "Central Campus, walks"}
];

def:pub MondayPage() -> JsxElement {
    has persona: str = "student",
        brief: Brief | None = None,
        loading: bool = False,
        error: str = "",
        votes: dict = {},
        speaking: bool = False,
        note: str = "";

    async def generate -> None {
        loading = True;
        error = "";
        note = "";
        try {
            res = root spawn GenerateBrief(persona=persona, use_ai=True);
            brief = res.reports[0] if res.reports and len(res.reports) > 0 else None;
            votes = {};
        } except Exception {
            error = "The Monday crew could not finish the brief.";
        }
        loading = False;
    }

    can with [persona] entry {
        stop_audio();
        generate();
    }

    async def vote(it: BriefItem, up: bool) -> None {
        nxt: dict = {**votes};
        nxt[it.key] = "up" if up else "down";
        votes = nxt;
        root spawn Feedback(persona=persona, item_key=it.key, up=up);
        note = ("Noted. More " if up else "Noted. Less ") + it.category + " next week. Regenerate to see the new ranking.";
    }

    def stop_audio() {
        w: any = window;
        if w.speechSynthesis {
            w.speechSynthesis.cancel();
        }
        speaking = False;
    }

    def play_audio() {
        w: any = window;
        if not brief or not w.speechSynthesis {
            return;
        }
        if speaking {
            stop_audio();
            return;
        }
        u: any = new(w.SpeechSynthesisUtterance, brief.summary);
        u.rate = 1.03;
        u.onend = lambda { speaking = False; };
        w.speechSynthesis.cancel();
        w.speechSynthesis.speak(u);
        speaking = True;
    }

    return <div className="mx-auto flex w-full max-w-6xl flex-col gap-8 pt-8 pb-12 pl-4 pr-4 sm:pl-6 sm:pr-6 animate-in fade-in slide-in-from-bottom-2 duration-500">
        {#* headline *#}
        <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr] lg:items-end">
            <div className="flex flex-col gap-1.5">
                <h2 className="text-2xl font-semibold tracking-tight">{"My Monday"}</h2>
                <p className="max-w-lg text-sm text-muted-foreground">{"The five things that touch your week, with what to do about each."}</p>
            </div>
            <div className="flex flex-col gap-2">
                <div className="grid grid-cols-3 gap-1 rounded-lg bg-muted pt-1 pb-1 pl-1 pr-1">
                    {for p in PERSONA_TABS {
                        <button key={p["id"]} type="button" onClick={lambda (e: MouseEvent) { persona = p["id"]; }} className={"flex flex-col gap-0.5 rounded-md pt-2 pb-2 pl-3 pr-3 text-left transition-colors " + ("bg-foreground text-background" if persona == p["id"] else "hover:bg-background")}>
                            <span className="kicker">{p["label"]}</span>
                            <span className={"text-xs " + ("text-background/70" if persona == p["id"] else "text-muted-foreground")}>{p["hint"]}</span>
                        </button>
                    }}
                </div>
            </div>
        </div>

        {#* profile + audio strip *#}
        <div className="flex flex-col gap-4 border-t border-b pt-4 pb-4 md:flex-row md:items-center md:justify-between">
            <div className="flex flex-wrap items-center gap-2">
                {if brief is None {
                    <Skeleton className="h-6 w-64" />
                    skip;
                }}
                {brief and <span className="mr-1 text-sm font-semibold">{brief.profile_name}</span>}
                {brief and <span className="rounded-full bg-muted pt-0.5 pb-0.5 pl-2.5 pr-2.5 text-xs">{"Home: " + brief.home}</span>}
                {brief and <span className="rounded-full bg-muted pt-0.5 pb-0.5 pl-2.5 pr-2.5 text-xs">{"Commute: " + brief.commute}</span>}
                {for i in (brief.interests if brief else []) {
                    <span key={i} className="rounded-full border pt-0.5 pb-0.5 pl-2.5 pr-2.5 text-xs capitalize text-muted-foreground">{i}</span>
                }}
            </div>
            <div className="flex flex-wrap items-center gap-2">
                <Button variant="outline" onClick={lambda (e: MouseEvent) { generate(); }} disabled={loading}>
                    <HugeiconsIcon icon={SparklesIcon} strokeWidth={2} />
                    {"Writing..." if loading else "Regenerate brief"}
                </Button>
                <Button onClick={lambda (e: MouseEvent) { play_audio(); }} disabled={not brief}>
                    <HugeiconsIcon icon={(StopIcon if speaking else PlayIcon)} strokeWidth={2} />
                    {"Stop" if speaking else "Play 60-second brief"}
                </Button>
            </div>
        </div>

        {error and <div className="flex items-center gap-3">
            <p className="text-sm text-destructive">{error}</p>
            <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { generate(); }}>{"Retry"}</Button>
        </div>}

        {#* lead story: spoken summary *#}
        {brief and <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
            <article className="rounded-xl border bg-card pt-6 pb-6 pl-6 pr-6 shadow-sm">
                <div className="flex items-center justify-between gap-3">
                    <span className="text-xs font-medium">{"Your brief"}</span>
                    <span className="text-xs text-muted-foreground">{"Written by AI" if brief.ai else "Assembled by the Editor walker"}</span>
                </div>
                <p className="mt-3 text-base leading-relaxed text-foreground/90">
                    {brief.summary}
                </p>
            </article>
            <div className="flex flex-col gap-3 border-l-0 lg:border-l lg:pl-6">
                <span className="kicker text-muted-foreground">{"How it was ranked"}</span>
                <ol className="flex flex-col gap-2 text-sm">
                    <li><span className="font-semibold">{"Profile agent: "}</span>{"loads your home, route and interests from your node."}</li>
                    <li><span className="font-semibold">{"Relevance agent: "}</span>{"walks to alerts on your route, events near you, and items tagged with your interests."}</li>
                    <li><span className="font-semibold">{"Action agent: "}</span>{"attaches a to-do to each item."}</li>
                    <li><span className="font-semibold">{"Editor agent: "}</span>{"picks the top 5 and writes the brief."}</li>
                </ol>
                {note and <p className="border-l-2 border-primary pl-3 text-sm text-primary">{note}</p>}
            </div>
        </div>}

        {#* the five items *#}
        {if loading and brief is None {
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                <Skeleton className="h-48" />
                <Skeleton className="h-48" />
                <Skeleton className="h-48" />
            </div>
            skip;
        }}
        {brief and len(brief.items) == 0 and <div className="flex flex-col items-center gap-2 border border-dashed pt-10 pb-10 text-center">
            <div className="flex size-10 items-center justify-center bg-primary/10 text-primary">
                <HugeiconsIcon icon={Calendar03Icon} strokeWidth={2} className="size-5" />
            </div>
            <p className="font-display text-lg font-bold">{"A quiet week"}</p>
            <p className="text-sm text-muted-foreground">{"Nothing in the graph touches this profile yet."}</p>
        </div>}
        {brief and len(brief.items) > 0 and <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {for (idx, it) in enumerate(brief.items if brief else []) {
                <article key={it.key} className="group flex flex-col gap-3 rounded-xl border bg-card pt-5 pb-4 pl-5 pr-5 transition-shadow hover:shadow-md">
                    <div className="flex items-start justify-between gap-3">
                        <span className="text-sm font-medium tabular-nums text-muted-foreground">{str(idx + 1).zfill(2)}</span>
                        <span className="kicker flex items-center gap-1.5" style={{"color": kind_color(it.kind)}}>
                            <span className="size-2 rounded-full" style={{"backgroundColor": kind_color(it.kind)}} />
                            {kind_label(it.kind)}
                        </span>
                    </div>
                    <h3 className="text-base font-semibold leading-snug">{it.name}</h3>
                    <span className="kicker text-muted-foreground">{it.when}</span>
                    <div className="flex flex-col gap-2 text-sm">
                        <p><span className="kicker mr-1 text-primary">{"Why"}</span>{it.why}</p>
                        <p><span className="kicker mr-1 text-primary">{"Do"}</span>{it.action}</p>
                    </div>
                    <div className="mt-auto flex items-center justify-between gap-2 border-t pt-3">
                        {it.source_url and <a href={it.source_url} target="_blank" rel="noreferrer" className="kicker inline-flex items-center gap-1 text-foreground hover:text-primary">
                            {it.source_name}
                            <HugeiconsIcon icon={ArrowUpRight01Icon} strokeWidth={2} className="size-3.5" />
                        </a>}
                        <div className="flex items-center gap-1">
                            <button type="button" aria-label="More like this" onClick={lambda (e: MouseEvent) { vote(it, True); }} className={"flex size-8 items-center justify-center border transition-colors " + ("border-foreground bg-foreground text-background" if votes.get(it.key) == "up" else "hover:border-foreground")}>
                                <HugeiconsIcon icon={ThumbsUpIcon} strokeWidth={2} className="size-4" />
                            </button>
                            <button type="button" aria-label="Less like this" onClick={lambda (e: MouseEvent) { vote(it, False); }} className={"flex size-8 items-center justify-center border transition-colors " + ("border-primary bg-primary text-primary-foreground" if votes.get(it.key) == "down" else "hover:border-foreground")}>
                                <HugeiconsIcon icon={ThumbsDownIcon} strokeWidth={2} className="size-4" />
                            </button>
                        </div>
                    </div>
                </article>
            }}
        </div>}
    </div>;
}
