"""Shared filter chips + natural-language Ask bar (ConverseQuery)."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    SparklesIcon,
    FilterHorizontalIcon,
    SentIcon
}
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.slider { Slider }
import from .ui.toggle_group { ToggleGroup, ToggleGroupItem }
import from .pulse_theme { all_categories, kind_options, default_filters, kind_color }
sv import from ..services.pulse { converse_query, FilterSpec }

def:pub FilterChip(
    label: str, active: bool, onToggle: Callable[[], None], color: str = ""
) -> JsxElement {
    base = "inline-flex h-7 items-center gap-1.5 rounded-full border pl-3 pr-3 text-xs font-medium capitalize transition-colors ";
    tone = "border-foreground bg-foreground text-background"
        if active
        else "bg-card text-muted-foreground hover:text-foreground";
    return
        <button
            type="button"
            onClick={lambda (e: MouseEvent) { onToggle(); }}
            className={base + tone}
        >
            {color
                and <span
                    className="size-2 rounded-full"
                    style={{"backgroundColor": color}}
                />}{label}
        </button>;
}

def:pub FilterBar(
    filters: dict, onChange: Callable[[dict], None], showDistance: bool = True
) -> JsxElement {
    has draft: str = "",
        asking: bool = False,
        askError: str = "";

    cats: list[str] = filters["categories"] or [];
    kinds: list[str] = filters["kinds"] or [];
    price: str = filters["price"] or "any";
    time: str = filters["time"] or "week";
    distance: float = filters["distance"] or 0.0;
    reply: str = filters["reply"] or "";

    def patch(key: str, val: any) {
        nxt = {** filters};
        nxt[key] = val;
        onChange(nxt);
    }

    def toggle_cat(c: str) {
        if c in cats {
            patch(
                "categories",
                [
                    x
                    for x in cats
                    if x != c
                ]
            );
        } else {
            patch("categories", cats + [c]);
        }
    }

    def toggle_kind(k: str) {
        if k in kinds {
            patch(
                "kinds",
                [
                    x
                    for x in kinds
                    if x != k
                ]
            );
        } else {
            patch("kinds", kinds + [k]);
        }
    }

    async def ask -> None {
        text = draft.strip();
        if not text {
            return;
        }
        asking = True;
        askError = "";
        try {
            # Plain dict: FilterSpec is a server type with no constructor in the browser
            # bundle (new FilterSpec threw, so Ask always failed). The server builds it.
            prior: any = {
                "query": filters["query"] or "",
                "categories": cats,
                "kinds": kinds,
                "price": price,
                "time": time,
                "distance": distance,
                "reply": ""
            };
            spec = await converse_query(text, prior);
            onChange(
                {
                    "categories": spec.categories,
                    "kinds": spec.kinds,
                    "price": spec.price,
                    "time": spec.time,
                    "distance": spec.distance,
                    "reply": spec.reply,
                    "query": text
                }
            );
            draft = "";
        } except Exception {
            askError = "Could not read that request. Try again.";
        }
        asking = False;
    }

    def on_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            ask();
        }
    }

    active_count = len(cats)
        + len(kinds)
        + (1 if price != "any" else 0)
        + (1 if time != "week" else 0)
        + (1 if distance > 0.0 else 0);

    return
        <div className="flex flex-col gap-3">
            <div
                className="flex items-center gap-2 rounded-lg border bg-card pt-1 pb-1 pl-3 pr-1 shadow-sm focus-within:ring-2 focus-within:ring-ring/40"
            >
                <HugeiconsIcon
                    icon={SparklesIcon}
                    strokeWidth={2}
                    className="size-4 shrink-0 text-primary"
                />
                <Input
                    value={draft}
                    onChange={lambda (e: ChangeEvent) { draft = e.target.value; }}
                    onKeyDown={on_key}
                    placeholder="Ask: free social stuff near campus Saturday"
                    className="h-8 border-0 bg-transparent pl-0 shadow-none focus-visible:ring-0"
                />
                <Button
                    size="sm"
                    onClick={lambda (e: MouseEvent) { ask(); }}
                    disabled={asking or not draft.strip()}
                >
                    <HugeiconsIcon icon={SentIcon} strokeWidth={2}/>
                    {"Refining..." if asking else "Ask"}
                </Button>
            </div>
            {reply and <p className="text-xs text-primary">{reply}</p>}
            {askError and <p className="text-xs text-destructive">{askError}</p>}
            <div className="flex flex-col gap-2">
                <div className="flex items-center justify-between">
                    <span
                        className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground"
                    >
                        <HugeiconsIcon
                            icon={FilterHorizontalIcon}
                            strokeWidth={2}
                            className="size-3.5"
                        />
                        {"Show"}
                    </span>
                    {active_count > 0
                        and <button
                            type="button"
                            onClick={lambda (e: MouseEvent) { onChange(
                                default_filters()
                            ); }}
                            className="text-xs font-medium text-primary hover:underline"
                        >
                            {"Clear " + str(active_count)}
                        </button>}
                </div>
                <div className="flex flex-wrap gap-1.5">
                    {for k in kind_options() {
                        <FilterChip
                            key={k["value"]}
                            label={k["label"]}
                            active={k["value"] in kinds}
                            onToggle={lambda { toggle_kind(k["value"]); }}
                            color={kind_color(k["value"])}
                        />
                    }}
                </div>
            </div>
            <div className="flex flex-col gap-2">
                <span className="text-xs font-medium text-muted-foreground">
                    {"Categories"}
                </span>
                <div className="flex flex-wrap gap-1.5">
                    {for c in all_categories() {
                        <FilterChip
                            key={c}
                            label={c}
                            active={c in cats}
                            onToggle={lambda { toggle_cat(c); }}
                        />
                    }}
                </div>
            </div>
            <div className="flex flex-col gap-3">
                <div className="flex flex-col gap-2">
                    <span className="text-xs font-medium text-muted-foreground">
                        {"Price"}
                    </span>
                    <ToggleGroup
                        type="single"
                        variant="outline"
                        size="sm"
                        value={price}
                        onValueChange={lambda (v: str) { patch("price", v or "any"); }}
                    >
                        <ToggleGroupItem value="any">{"Any"}</ToggleGroupItem>
                        <ToggleGroupItem value="free">{"Free"}</ToggleGroupItem>
                        <ToggleGroupItem value="under10">{"Under $10"}</ToggleGroupItem>
                    </ToggleGroup>
                </div>
                <div className="flex flex-col gap-2">
                    <span className="text-xs font-medium text-muted-foreground">
                        {"When"}
                    </span>
                    <ToggleGroup
                        type="single"
                        variant="outline"
                        size="sm"
                        value={time}
                        onValueChange={lambda (v: str) { patch("time", v or "week"); }}
                    >
                        <ToggleGroupItem value="today">{"Today"}</ToggleGroupItem>
                        <ToggleGroupItem value="weekend">{"Weekend"}</ToggleGroupItem>
                        <ToggleGroupItem value="week">{"Week"}</ToggleGroupItem>
                    </ToggleGroup>
                </div>
            </div>
            {showDistance
                and <div className="flex flex-col gap-2">
                    <div className="flex items-center justify-between text-xs">
                        <span className="font-medium text-muted-foreground">
                            {"Distance from campus"}
                        </span>
                        <span className="font-medium tabular-nums">
                            {("Any" if distance == 0.0 else f"{distance:.1f} mi")}
                        </span>
                    </div>
                    <Slider
                        min={0}
                        max={5}
                        step={0.5}
                        value={[distance]}
                        onValueChange={lambda (v: list[float]) { patch(
                            "distance", v[0]
                        ); }}
                    />
                </div>}
        </div>;
}
