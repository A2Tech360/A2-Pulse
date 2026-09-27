"""My Monday: persona-aware brief from the Monday crew walkers, read aloud."""

import from "@jac/runtime" { useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { SparklesIcon, ArrowUpRight01Icon, ThumbsUpIcon, ThumbsDownIcon, PlayIcon, StopIcon, Calendar03Icon }
import from .ui.button { Button }
import from .ui.skeleton { Skeleton }
import from .ui.select { Select, SelectTrigger, SelectValue, SelectContent, SelectItem }
import from .FilterBar { FilterBar }
import from .pulse_theme { kind_color, kind_label, campus_lat, campus_lng }
import from .profile_store { my_persona, load_profile, commute_verb }
import from .net { with_timeout }
import from .BriefDebugPanel { BriefDebugPanel }
sv import from ..services.pulse { GenerateBrief, Feedback, Brief, BriefItem, list_personas, speak_brief, list_voices }

glob PERSONA_TABS: list[dict] = [
    {"id": "student", "label": "Student", "hint": "Jordan, North Campus, bikes"},
    {"id": "shop", "label": "Shop owner", "hint": "Maya, Main St, drives"},
    {"id": "custom", "label": "You", "hint": "Central Campus, walks"}
];

glob VOICE_STORAGE_KEY: str = "a2pulse.voice";

def split_brief_words(text: str) -> list[str] {
    raw: list[str] = text.split(" ");
    out: list[str] = [];
    for w in raw {
        if w {
            out = out + [w];
        }
    }
    return out;
}

def word_index_at_char(text: str, char_idx: int) -> int {
    if char_idx < 0 {
        return 0;
    }
    words = split_brief_words(text);
    if len(words) == 0 {
        return -1;
    }
    pos: int = 0;
    i: int = 0;
    for w in words {
        end = pos + len(w);
        if char_idx < end {
            return i;
        }
        pos = end + 1;    # space after word
        i += 1;
    }
    return len(words) - 1;
}

def word_index_at_time(words: list[str], t: float, dur: float) -> int {
    if len(words) == 0 or dur <= 0.0 {
        return -1;
    }
    total: float = 0.0;
    for w in words {
        total = total + float(max(len(w), 1));
    }
    if total <= 0.0 {
        return 0;
    }
    # Slight lead so the highlight feels on the word being spoken.
    target: float = (max(0.0, min(t + 0.04, dur)) / dur) * total;
    acc: float = 0.0;
    i: int = 0;
    for w in words {
        acc = acc + float(max(len(w), 1));
        if target <= acc {
            return i;
        }
        i += 1;
    }
    return len(words) - 1;
}

# Starting tab from ?who=you|student|shop (onboarding lands on "you").
def initial_tab() -> str {
    w: any = window;
    q: str = w.location.search or "";
    if "who=you" in q {
        return "custom";
    }
    if "who=shop" in q {
        return "shop";
    }
    return "student";
}

def:pub MondayPage(
    filters: dict, onFilters: Callable[[dict], None]
) -> JsxElement {
    has persona: str = initial_tab(),
        brief: Brief | None = None,
        loading: bool = False,
        error: str = "",
        votes: dict = {},
        speaking: bool = False,
        voice_loading: bool = False,
        voices: list[dict] = [],
        voice_id: str = "",
        me: dict = {},
        voice_note: str = "",
        note: str = "",
        spoken_idx: int = -1;

    nav = useNavigate();

    # "custom" is the "You" tab: this browser's own profile on the server.
    def target_persona(p: str) -> str {
        return my_persona() if p == "custom" else p;
    }

    # Explicit comparison: an empty dict is truthy once compiled to JS.
    def me_onboarded() -> bool {
        return me["onboarded"] == True;
    }

    # Next step from a thin brief: edit your own profile, or go make one.
    def widen_label() -> str {
        return "Add interests" if persona == "custom" else ("See your brief" if me_onboarded() else "Build your profile");
    }

    def widen_brief() {
        stop_audio();
        if persona == "custom" {
            nav("/welcome?edit=1");
        } elif me_onboarded() {
            persona = "custom";
        } else {
            nav("/welcome");
        }
    }

    def tab_hint(tab: dict) -> str {
        if tab["id"] != "custom" or not me["home_name"] {
            return tab["hint"];
        }
        home: str = me["home_name"];
        mode: str = me["commute"];
        return home + ", " + commute_verb(mode);
    }

    def include_posted() -> bool {
        return filters["community"] != False;
    }

    async def run_brief(who: str, ai: bool) -> any {
        res = root spawn GenerateBrief(
            persona=who,
            use_ai=ai,
            categories=filters["categories"] or [],
            kinds=filters["kinds"] or [],
            price=filters["price"] or "any",
            time=filters["time"] or "week",
            date=filters["date"] or "",
            community=include_posted(),
            community_only=False,
            distance=filters["distance"] or 0.0,
            clat=campus_lat(),
            clng=campus_lng()
        );
        return res;
    }

    # Brief with deadlines: the full (AI) brief gets 8 s, then the instant template
    # brief gets 8 s, then a plain error with Retry. The skeleton shows meanwhile.
    async def generate -> None {
        loading = True;
        error = "";
        note = "";
        who: str = target_persona(persona);
        w: any = window;
        req: int = (w.__pulseBriefReq or 0) + 1;
        w.__pulseBriefReq = req;
        if brief is not None and brief.persona != who {
            brief = None;    # switching people: show the skeleton, not the last person's brief
        }
        got: any = None;
        quick: bool = False;
        try {
            if persona == "custom" {
                await load_profile();
            }
            got = await with_timeout(run_brief(who, True), None);
            if got is None and w.__pulseBriefReq == req {
                quick = True;
                got = await with_timeout(run_brief(who, False), None);
            }
        } except Exception {
            got = None;
        }
        if w.__pulseBriefReq != req {
            return;    # a newer request (tab switch / regenerate) owns the screen
        }
        if got is None {
            error = "Can't reach the A2 Pulse server right now. Check your connection, then retry.";
        } else {
            brief = got.reports[0] if got.reports and len(got.reports) > 0 else None;
            votes = {};
            if quick {
                note = "The full brief was taking too long, so this is the quick version. Regenerate to try again.";
            }
        }
        loading = False;
    }

    async can with entry {
        prof: dict = await load_profile();
        if prof["ok"] {
            me = prof;
        }
        saved: str = "";
        try {
            saved = localStorage.getItem(VOICE_STORAGE_KEY) or "";
        } except Exception {
            saved = "";
        }
        try {
            res: dict = await with_timeout(list_voices(), {"voices": []});
            loaded: list[dict] = res["voices"] or [];
            voices = loaded;
            ids: list[str] = [v["id"] for v in loaded];
            voice_id = saved if saved in ids else (ids[0] if len(ids) > 0 else "");
        } except Exception {
            voices = [];
        }
    }

    def choose_voice(vid: str) {
        stop_audio();
        voice_id = vid;
        try {
            localStorage.setItem(VOICE_STORAGE_KEY, vid);
        } except Exception {
            return;
        }
    }

    can with (persona, filters) entry {
        stop_audio();
        generate();
    }

    async def vote(it: BriefItem, up: bool) -> None {
        nxt: dict = {**votes};
        nxt[it.key] = "up" if up else "down";
        votes = nxt;
        root spawn Feedback(persona=target_persona(persona), item_key=it.key, up=up);
        note = ("Noted. More " if up else "Noted. Less ") + it.category + " next week. Regenerate to see the new ranking.";
    }

    def stop_audio() {
        w: any = window;
        if w.speechSynthesis {
            w.speechSynthesis.cancel();
        }
        p: any = w.__pulsePlayer;
        if p {
            p.pause();
            w.__pulsePlayer = None;
        }
        raf: any = w.__pulseSpeakRaf;
        if raf {
            w.cancelAnimationFrame(raf);
            w.__pulseSpeakRaf = None;
        }
        # Invalidate any in-flight voice request (state reads are stale inside async handlers).
        w.__pulseVoiceReq = (w.__pulseVoiceReq or 0) + 1;
        speaking = False;
        voice_loading = False;
        spoken_idx = -1;
    }

    def finish_speak() {
        speaking = False;
        spoken_idx = -1;
        w: any = window;
        raf: any = w.__pulseSpeakRaf;
        if raf {
            w.cancelAnimationFrame(raf);
            w.__pulseSpeakRaf = None;
        }
    }

    # Browser voice, used when ElevenLabs is not configured or fails.
    def speak_fallback(text: str) {
        w: any = window;
        if not w.speechSynthesis {
            return;
        }
        words = split_brief_words(text);
        spoken_idx = 0 if len(words) > 0 else -1;
        u: any = new(w.SpeechSynthesisUtterance, text);
        u.rate = 1.03;
        u.onboundary = lambda (e: any) {
            name: str = str(e.name or "");
            if name == "word" or name == "Word" or not name {
                spoken_idx = word_index_at_char(text, int(e.charIndex or 0));
            }
        };
        u.onend = lambda { finish_speak(); };
        u.onerror = lambda { finish_speak(); };
        w.speechSynthesis.cancel();
        w.speechSynthesis.speak(u);
        speaking = True;
    }

    def track_audio_words(a: any, text: str) {
        words = split_brief_words(text);
        if len(words) == 0 {
            return;
        }
        w: any = window;
        def tick() {
            player: any = w.__pulsePlayer;
            if not player or player != a {
                return;
            }
            dur: float = float(player.duration or 0.0);
            cur: float = float(player.currentTime or 0.0);
            if dur > 0.0 and not player.paused {
                spoken_idx = word_index_at_time(words, cur, dur);
            }
            w.__pulseSpeakRaf = w.requestAnimationFrame(lambda (_t: any) { tick(); });
        }
        a.ontimeupdate = lambda {
            dur2: float = float(a.duration or 0.0);
            if dur2 > 0.0 {
                spoken_idx = word_index_at_time(words, float(a.currentTime or 0.0), dur2);
            }
        };
        spoken_idx = 0;
        w.__pulseSpeakRaf = w.requestAnimationFrame(lambda (_t: any) { tick(); });
    }

    async def play_audio -> None {
        if not brief {
            return;
        }
        if speaking or voice_loading {
            stop_audio();
            return;
        }
        w: any = window;
        req: int = (w.__pulseVoiceReq or 0) + 1;
        w.__pulseVoiceReq = req;
        text: str = brief.summary;
        voice_loading = True;
        voice_note = "";
        spoken_idx = -1;
        res: dict = {"audio": "", "error": ""};
        try {
            # 12 s, not the usual 8: ElevenLabs needs ~5 s for a full brief, plus a cold voice-list check.
            res = await with_timeout(speak_brief(target_persona(persona), voice_id), {"audio": "", "error": "timeout", "code": "timeout"}, 12000);
        } except Exception {
            res = {"audio": "", "error": "Voice request failed"};
        }
        if w.__pulseVoiceReq != req {
            return;    # stopped (or restarted) while loading
        }
        voice_loading = False;
        if not res["audio"] {
            print("ElevenLabs unavailable, using browser voice:", res["error"]);
            code: str = res["code"] or "";
            if not w.speechSynthesis {
                voice_note = "Voice isn't available right now. The brief is written above.";
            } elif code == "rate_limited" {
                voice_note = "The studio voice is taking a short break, so your browser is reading the brief.";
            } else {
                voice_note = "The studio voice didn't respond, so your browser is reading the brief.";
            }
            speak_fallback(text);
            return;
        }
        a: any = new(w.Audio, res["audio"]);
        a.onended = lambda { finish_speak(); };
        a.onerror = lambda {
            voice_note = "The studio voice couldn't play, so your browser is reading the brief.";
            speak_fallback(text);
        };
        w.__pulsePlayer = a;
        speaking = True;
        track_audio_words(a, text);
        a.play();
    }

    return <div className="flex flex-1 flex-col bg-background text-foreground lg:flex-row">
        <div className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-8 pt-8 pb-12 pl-4 pr-4 sm:pl-6 sm:pr-6 animate-in fade-in slide-in-from-bottom-2 duration-500 lg:max-w-none">
        {#* headline *#}
        <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr] lg:items-end">
            <div className="flex flex-col gap-1.5">
                <h2 className="text-2xl font-semibold tracking-tight">{"My Monday"}</h2>
                <p className="max-w-lg text-sm text-muted-foreground">{"The five things that touch your week — same filters as Network and Map."}</p>
            </div>
            <div className="flex flex-col gap-2">
                <div className="flex items-center justify-end gap-3">
                    <button type="button" onClick={lambda (e: MouseEvent) { stop_audio(); nav("/welcome?edit=1"); }} className="text-xs font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline">
                        {"Edit your profile" if me_onboarded() else "Set up your profile"}
                    </button>
                    <span className="text-xs text-muted-foreground/50" aria-hidden="true">{"·"}</span>
                    <button type="button" onClick={lambda (e: MouseEvent) { stop_audio(); nav("/welcome?reset=1"); }} className="text-xs font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline" title="Give this browser a new, blank profile and onboard again">
                        {"Start fresh"}
                    </button>
                </div>
                <div className="grid grid-cols-3 gap-1 rounded-lg bg-muted pt-1 pb-1 pl-1 pr-1">
                    {for p in PERSONA_TABS {
                        <button key={p["id"]} type="button" onClick={lambda (e: MouseEvent) { persona = p["id"]; }} className={"flex flex-col gap-0.5 rounded-md pt-2 pb-2 pl-3 pr-3 text-left transition-colors " + ("bg-foreground text-background" if persona == p["id"] else "hover:bg-background")}>
                            <span className="kicker">{p["label"]}</span>
                            <span className={"text-xs " + ("text-background/70" if persona == p["id"] else "text-muted-foreground")}>{tab_hint(p)}</span>
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
            <div className="flex flex-wrap items-center gap-2 md:shrink-0 md:flex-nowrap">
                <Button variant="outline" onClick={lambda (e: MouseEvent) { generate(); }} disabled={loading}>
                    <HugeiconsIcon icon={SparklesIcon} strokeWidth={2} />
                    {"Writing..." if loading else "Regenerate brief"}
                </Button>
                {len(voices) > 0 and <Select value={voice_id} onValueChange={lambda (v: str) { choose_voice(v); }}>
                    <SelectTrigger className="w-32 [&_.voice-desc]:hidden" aria-label="Voice">
                        <SelectValue placeholder="Voice" />
                    </SelectTrigger>
                    <SelectContent position="popper" align="end">
                        {for v in voices {
                            <SelectItem key={v["id"]} value={v["id"]}>
                                {v["name"]}
                                <span className="voice-desc ml-1.5 text-xs text-muted-foreground">{v["desc"]}</span>
                            </SelectItem>
                        }}
                    </SelectContent>
                </Select>}
                <Button onClick={lambda (e: MouseEvent) { play_audio(); }} disabled={not brief}>
                    <HugeiconsIcon icon={(StopIcon if speaking or voice_loading else PlayIcon)} strokeWidth={2} />
                    {"Loading voice..." if voice_loading else ("Stop" if speaking else "Play 60-second brief")}
                </Button>
            </div>
        </div>

        {voice_note and <p className="-mt-4 text-xs text-muted-foreground" role="status">{voice_note}</p>}

        {error and <div className="flex items-center gap-3">
            <p className="text-sm text-destructive">{error}</p>
            <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { generate(); }}>{"Retry"}</Button>
        </div>}

        {#* lead story: spoken summary *#}
        {brief and <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
            <article className="rounded-xl border bg-card pt-6 pb-6 pl-6 pr-6 shadow-sm">
                <div className="flex items-center justify-between gap-3">
                    <span className="text-xs font-medium">{"Your brief"}</span>
                    <span className="text-xs text-muted-foreground">
                        {(
                            "Following along"
                                if speaking
                                else (
                                    "Written by AI"
                                        if brief.ai
                                        else "Assembled by the Editor walker"
                                )
                        )}
                    </span>
                </div>
                <p className="mt-3 text-base leading-relaxed text-foreground/90">
                    {for (wi, word) in enumerate(
                        split_brief_words(brief.summary if brief else "")
                    ) {
                        <span
                            key={wi}
                            className={
                                "rounded-sm transition-colors duration-100 "
                                + (
                                    "bg-amber-300/90 px-0.5 font-medium text-stone-900 dark:bg-amber-400/50 dark:text-foreground"
                                        if wi == spoken_idx
                                        else ""
                                )
                            }
                        >
                            {(word + " ")}
                        </span>
                    }}
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
            <div className="flex flex-col gap-8" aria-busy="true" aria-label="Building your brief">
                <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
                    <Skeleton className="h-56 rounded-xl" />
                    <div className="flex flex-col gap-3 lg:pl-6">
                        <Skeleton className="h-3 w-28" />
                        <Skeleton className="h-4 w-full" />
                        <Skeleton className="h-4 w-5/6" />
                        <Skeleton className="h-4 w-4/6" />
                        <Skeleton className="h-4 w-5/6" />
                    </div>
                </div>
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                    <Skeleton className="h-48 rounded-xl" />
                    <Skeleton className="h-48 rounded-xl" />
                    <Skeleton className="h-48 rounded-xl" />
                </div>
            </div>
            skip;
        }}
        {brief and len(brief.items) == 0 and <div className="flex flex-col items-center gap-2 border border-dashed pt-10 pb-10 text-center">
            <div className="flex size-10 items-center justify-center bg-primary/10 text-primary">
                <HugeiconsIcon icon={Calendar03Icon} strokeWidth={2} className="size-5" />
            </div>
            <p className="font-display text-lg font-bold">{"A quiet week"}</p>
            <p className="text-sm text-muted-foreground">{"Nothing in the graph touches this profile yet."}</p>
            <Button variant="outline" size="sm" className="mt-2" onClick={lambda (e: MouseEvent) { widen_brief(); }}>{widen_label()}</Button>
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
        {brief and len(brief.items) > 0 and len(brief.items) < 5 and <div className="flex flex-col items-start gap-3 rounded-xl border border-dashed pt-4 pb-4 pl-5 pr-5 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-sm text-muted-foreground">
                {f"Only {len(brief.items)} " + ("thing touches" if len(brief.items) == 1 else "things touch") + " this profile this week. "}
                {"Add interests or follow a few groups to widen it." if persona == "custom" else "Build your own profile to see what touches you."}
            </p>
            <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { widen_brief(); }}>{widen_label()}</Button>
        </div>}
        <BriefDebugPanel persona={target_persona(persona)} />
        </div>
        <aside className="flex w-full flex-col gap-4 border-t border-border bg-background pt-6 pb-6 pl-6 pr-6 lg:w-[360px] lg:shrink-0 lg:border-l lg:border-t-0 lg:pt-8">
            <div className="flex flex-col gap-1">
                <h3 className="text-sm font-semibold text-foreground">{"Shared filters"}</h3>
                <p className="text-xs text-muted-foreground">
                    {"Same chips as Network and Map — narrow the brief when the graph is crowded."}
                </p>
            </div>
            <FilterBar filters={filters} onChange={onFilters} showDistance={True}/>
        </aside>
    </div>;
}
