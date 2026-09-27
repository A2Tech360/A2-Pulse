"""Live event ingestion: fetch public calendars, normalize, upsert into the Pulse graph."""

import from services.pulse {
    Hub,
    Event,
    Venue,
    Organizer,
    Category,
    SourceDoc,
    Place,
    HostedAt,
    OrganizedBy,
    TaggedAs,
    SourcedFrom,
    Near,
    seed_pulse
}

# ---------------------------------------------------------------- transfer shapes
obj RawEvent {
    has name: str = "",
        desc: str = "",
        when: str = "",
        venue: str = "",
        organizer: str = "",
        price: float = -1.0,    # -1 = unknown; 0 only when the source says free
        categories: list[str] = [],
        source_url: str = "",
        day: int = -1;
}

obj SyncReport {
    has ok: bool = True,
        fetched: int = 0,
        created: int = 0,
        updated: int = 0,
        skipped: int = 0,
        sources: list[str] = [],
        errors: list[str] = [],
        message: str = "";
}

# ---------------------------------------------------------------- LLM extract (optional)
def llm_extract_events(
    source_name: str, page_text: str, allowed_categories: list[str]
) -> list[RawEvent] by llm(temperature=0.1, max_tokens=2500);
sem llm_extract_events = "Extract upcoming Ann Arbor / Ypsilanti / U-M public events from page text. Return at most 20 distinct events. Prefer concerts, club nights, comedy, talks, workshops, festivals, and nightlife. Skip navigation fluff, ads, and past-event banners. categories must be chosen only from allowed_categories. day is weekday 0=Monday .. 6=Sunday when a date is known, else -1. price is 0 only when the page says free / pay-what-you-wish, the stated ticket floor when one is given, and -1 when the page gives no price. Keep name under 80 chars and desc under 220 chars.";
sem llm_extract_events.source_name = "Human-readable name of the calendar site.";
sem llm_extract_events.page_text = "Fetched page text (HTML tags mostly stripped).";
sem llm_extract_events.allowed_categories = "Only these category slugs may appear in categories.";

# ---------------------------------------------------------------- public API
"""Pull public calendars and merge events into the living graph.
force=True ignores the short cooldown between automatic syncs."""
def:pub sync_online_events(force: bool = False) -> SyncReport;

"""Return recently ingested live events (keys starting with live-)."""
def:pub list_live_events(limit: int = 40) -> list[dict];
