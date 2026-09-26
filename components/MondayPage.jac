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
            <div className="flex flex-col gap-3">
                <div className="flex items-center gap-3">
                    <span className="h-px w-10 bg-primary" />
                    <span className="kicker text-primary">{"The Monday Edition"}</span>
                </div>
                <h2 className="font-display text-4xl font-black leading-[0.95] tracking-tight sm:text-5xl md:text-6xl">
                    {"Five things. "}<span className="text-primary">{"Your week."}</span>
                </h2>
                <p className="max-w-lg text-base leading-relaxed text-foreground/80">
                    {"A walker starts at you, follows your home, route and interests through the graph, and returns what actually touches your week, with what to do about it."}
                </p>
            </div>
            <div className="flex flex-col gap-2">
                <span className="kicker text-muted-foreground">{"Read the edition for"}</span>
                <div className="grid grid-cols-3 border border-foreground">
                    {for p in PERSONA_TABS {
                        <button key={p["id"]} type="button" onClick={lambda (e: MouseEvent) { persona = p["id"]; }} className={"flex flex-col gap-0.5 border-r pt-2.5 pb-2.5 pl-3 pr-3 text-left transition-colors last:border-r-0 " + ("bg-foreground text-background" if persona == p["id"] else "bg-card hover:bg-muted")}>
                            <span className="kicker">{p["label"]}</span>
                            <span className={"text-xs " + ("text-background/70" if persona == p["id"] else "text-muted-foreground")}>{p["hint"]}</span>
                        </button>
                    }}
                </div>
            </div>
        </div>

        {#* profile + audio strip *#}
        <div className="rule-double flex flex-col gap-4 border-t border-foreground pt-4 pb-4 md:flex-row md:items-center md:justify-between">
            <div className="flex flex-wrap items-center gap-2">
                {if brief is None {
                    <Skeleton className="h-6 w-64" />
                    skip;
                }}
                {brief and <span className="font-display text-lg font-bold">{brief.profile_name}</span>}
                {brief and <span className="kicker border pt-0.5 pb-0.5 pl-2 pr-2">{"Home: " + brief.home}</span>}
                {brief and <span className="kicker border pt-0.5 pb-0.5 pl-2 pr-2">{"Commute: " + brief.commute}</span>}
                {for i in (brief.interests if brief else []) {
                    <span key={i} className="kicker border border-primary/40 pt-0.5 pb-0.5 pl-2 pr-2 text-primary">{i}</span>
                }}
            </div>
            <div className="flex flex-wrap items-center gap-2">
                <Button variant="outline" onClick={lambda (e: MouseEvent) { generate(); }} disabled={loading}>
                    <HugeiconsIcon icon={SparklesIcon} strokeWidth={2} />
                    {"Writing..." if loading else "Regenerate brief"}
                </Button>
                <Button onClick={lambda (e: MouseEvent) { play_audio(); }} disabled={not brief} className="shadow-[3px_3px_0_var(--foreground)]">
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
            <article className="border border-foreground bg-card pt-6 pb-6 pl-6 pr-6 shadow-[5px_5px_0_var(--foreground)]">
                <div className="flex items-center justify-between gap-3">
                    <span className="kicker text-primary">{"Lead · Your Monday, read aloud"}</span>
                    <span className="kicker text-muted-foreground">{"Written by AI" if brief.ai else "Assembled by the Editor walker"}</span>
                </div>
                <p className="mt-3 font-sans text-lg leading-relaxed first-letter:float-left first-letter:mr-2 first-letter:font-display first-letter:text-6xl first-letter:font-black first-letter:leading-[0.8] first-letter:text-primary">
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
                <article key={it.key} className={"group flex flex-col gap-3 border bg-card pt-5 pb-4 pl-5 pr-5 transition-all hover:-translate-y-0.5 hover:border-foreground hover:shadow-[4px_4px_0_var(--foreground)] " + ("md:col-span-2 lg:col-span-1 lg:row-span-2" if idx == 0 else "")}>
                    <div className="flex items-start justify-between gap-3">
                        <span className="font-display text-5xl font-black leading-none text-primary/80 tabular-nums">{str(idx + 1)}</span>
                        <span className="kicker flex items-center gap-1.5" style={{"color": kind_color(it.kind)}}>
                            <span className="size-2 rounded-full" style={{"backgroundColor": kind_color(it.kind)}} />
                            {kind_label(it.kind)}
                        </span>
                    </div>
                    <h3 className={"font-display font-bold leading-tight " + ("text-2xl" if idx == 0 else "text-xl")}>{it.name}</h3>
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
