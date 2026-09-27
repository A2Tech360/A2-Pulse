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
    seed_pulse,
    SyncReport
}

# ---------------------------------------------------------------- transfer shapes
obj RawEvent {
    has name: str = "",
        desc: str = "",
        when: str = "",
        venue: str = "",
        organizer: str = "",
        price: float = 0.0,
        categories: list[str] = [],
        source_url: str = "",
        day: int = -1,
        # Set by geocoded feeds (Happening @ Michigan); 0,0 means no known location.
        lat: float = 0.0,
        lng: float = 0.0,
        address: str = "",
        # Stable id from the source, used for the event key when present.
        ext_id: str = "";
}

# ---------------------------------------------------------------- LLM extract (optional)
def llm_extract_events(
    source_name: str, page_text: str, allowed_categories: list[str]
) -> list[RawEvent] by llm(temperature=0.1, max_tokens=2500);
sem llm_extract_events = "Extract upcoming Ann Arbor / Ypsilanti / U-M public events from page text. Return at most 20 distinct events. Prefer concerts, club nights, comedy, talks, workshops, festivals, and nightlife. Skip navigation fluff, ads, and past-event banners. categories must be chosen only from allowed_categories. day is weekday 0=Monday .. 6=Sunday when a date is known, else -1. price is 0 for free / pay-what-you-wish, otherwise a best-guess ticket floor or 0 if unknown. Keep name under 80 chars and desc under 220 chars.";
sem llm_extract_events.source_name = "Human-readable name of the calendar site.";
sem llm_extract_events.page_text = "Fetched page text (HTML tags mostly stripped).";
sem llm_extract_events.allowed_categories = "Only these category slugs may appear in categories.";

# ---------------------------------------------------------------- API (served through services.pulse)
"""Pull public calendars and merge events into the living graph.
force=True ignores the short cooldown between automatic syncs."""
def sync_online_events(force: bool = False) -> SyncReport;

"""Return recently ingested live events (keys starting with live-)."""
def list_live_events(limit: int = 40) -> list[dict[str, any]];
