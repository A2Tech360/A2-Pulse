"""A2 Pulse: Ann Arbor's living local graph - schema, walkers and endpoints."""

import os;
import time;
import asyncio;
import math;
import time;
import threading;
import json;
import base64;
import urllib.error;
import from urllib.parse { urlencode }
import from urllib.request { Request, urlopen }
import from datetime { datetime, timedelta }
import from services.seed_data {
    SOURCES, CATEGORIES, PLACES, VENUES, ORGANIZERS, EVENTS, ALERTS, CIVIC, PERSONAS
}
import from services { pulse_llm }
import from services.brief_editor { edit_brief, strongest_first }
import from services.speakable { speakable }
import from services.brief_trace { new_trace, append_trace, ms, sum_by_rule }
import from services.voice_guard { rate_check, client_ip, known_voice_ids, speak_limit, speak_window_s }

# ---------------------------------------------------------------- nodes
node Hub {
    has city: str = "Ann Arbor";
}

node PulseNode {
    has key: str = "",
        name: str = "",
        kind: str = "",
        desc: str = "",
        lat: float = 0.0,
        lng: float = 0.0,
        when: str = "",
        day: int = 0,
        price: float = 0.0,
        sub: str = "",
        address: str = "",
        source_name: str = "",
        source_url: str = "",
        path: list[list[float]] = [];
}

node Event(PulseNode) {}
node Venue(PulseNode) {}
node Organizer(PulseNode) {}
node Category(PulseNode) {}
node Alert(PulseNode) {}
node CivicItem(PulseNode) {}
node Place(PulseNode) {}
node SourceDoc(PulseNode) {}

node UserProfile {
    has persona: str = "",
        name: str = "",
        commute: str = "walk",
        weights: dict[str, float] = {},
        uid: str = "",
        onboarded: bool = False,
        home_label: str = "",
        home_lat: float = 0.0,
        home_lng: float = 0.0,
        dest_key: str = "",
        dest_label: str = "",
        # Last spoken brief (already speakable), so speak_brief can read it server-side.
        last_summary: str = "",
        last_summary_at: str = "";
}

# ---------------------------------------------------------------- edges
edge HostedAt {}
edge OrganizedBy {}
edge TaggedAs {}
edge InterestedIn {}
edge Follows {}
edge LivesAt {}
edge CommutesVia {}
edge Near {}
edge AffectsRoute {}
edge Related {}
edge SourcedFrom {}

# ---------------------------------------------------------------- transfer objs
obj GNode {
    has id: str = "",
        key: str = "",
        name: str = "",
        kind: str = "",
        sub: str = "",
        depth: int = 0,
        expandable: bool = True,
        x: float = 0.0,
        y: float = 0.0;
}

obj GEdge {
    has source: str = "",
        target: str = "",
        label: str = "";
}

obj Snapshot {
    has center: str = "",
        nodes: list[GNode] = [],
        edges: list[GEdge] = [];
}

obj MapItem {
    has id: str = "",
        key: str = "",
        name: str = "",
        kind: str = "",
        desc: str = "",
        when: str = "",
        price: float = 0.0,
        lat: float = 0.0,
        lng: float = 0.0,
        venue: str = "",
        categories: list[str] = [],
        source_name: str = "",
        source_url: str = "",
        path: list[list[float]] = [],
        dist: float = 0.0;
}

obj Dossier {
    has id: str = "",
        key: str = "",
        name: str = "",
        kind: str = "",
        desc: str = "",
        when: str = "",
        venue: str = "",
        address: str = "",
        organizer: str = "",
        price: float = 0.0,
        categories: list[str] = [],
        source_name: str = "",
        source_url: str = "",
        lat: float = 0.0,
        lng: float = 0.0,
        links: list[GNode] = [];
}

obj BriefItem {
    has id: str = "",
        key: str = "",
        name: str = "",
        kind: str = "",
        when: str = "",
        why: str = "",
        action: str = "",
        category: str = "",
        source_name: str = "",
        source_url: str = "",
        score: float = 0.0;
}

obj Brief {
    has persona: str = "",
        profile_name: str = "",
        home: str = "",
        commute: str = "",
        interests: list[str] = [],
        summary: str = "",
        ai: bool = False,
        items: list[BriefItem] = [],
        # Debug trace (profile read, per-rule scores, actions, editor I/O, timings); only with debug=True.
        trace: dict = {};
}

obj FilterSpec {
    has query: str = "",
        categories: list[str] = [],
        kinds: list[str] = [],
        price: str = "any",
        time: str = "week",
        date: str = "",
        distance: float = 0.0,
        reply: str = "";
}

obj PlaceSuggestion {
    has id: str = "",
        title: str = "",
        sub: str = "",
        label: str = "",
        lat: float = 0.0,
        lng: float = 0.0;
}

obj MapOverview {
    has headline: str = "",
        blurb: str = "",
        tip: str = "",
        ai: bool = False;
}

obj DossierImage {
    has url: str = "",
        caption: str = "",
        credit: str = "",
        source: str = "";
}

obj DossierMedia {
    has images: list[DossierImage] = [],
        queries: list[str] = [],
        ai: bool = False;
}

obj ImageQueryPlan {
    has queries: list[str] = [];
}

# ---------------------------------------------------------------- LLM layer
# Model, key check and 8s deadline live in services/pulse_llm.jac (LLM_MODEL in .env).
def llm_parse_filters(text: str, prior: FilterSpec, allowed_categories: list[str]) -> FilterSpec by pulse_llm.brief_llm(temperature=0.1, max_output_retries=1);
sem llm_parse_filters = "Turn an Ann Arbor resident's natural-language request into graph filters. Follow-ups like 'anything with food?' or 'add music' must ADD to the prior filters, not reset them. kinds may only contain event, organizer, alert, civic. price is any, free or under10. time is today, weekend or week. date is an optional YYYY-MM-DD calendar day (empty string means any day); set date when the user names a specific day like 'this Saturday' or 'October 4'. distance is miles from campus (0 means any; near campus means 1). reply is one short friendly sentence describing what you are showing.";
sem llm_parse_filters.text = "The user's request.";
sem llm_parse_filters.prior = "The filters currently active in the app.";
sem llm_parse_filters.allowed_categories = "The only category names that may appear in categories.";
# The Editor's spoken-brief prompt lives in services/brief_editor.jac (llm_write_brief).

def llm_map_overview(
    name: str, kind: str, when: str, venue: str, desc: str, categories: str
) -> MapOverview by llm(temperature=0.35, max_tokens=220);
sem llm_map_overview = "Write a short map-pin overview for an Ann Arbor resident tapping a marker. headline: punchy title under 8 words (can match the name). blurb: 1-2 friendly sentences (about 35-55 words) on what it is and why it matters locally. tip: one short practical line (when to go, free/paid cue, or what to do next). Plain text only, no markdown or emojis. Set ai=true.";
sem llm_map_overview.name = "Official name of the place or event.";
sem llm_map_overview.kind = "event, venue, organizer, alert, or civic.";
sem llm_map_overview.when = "Time or date string if any.";
sem llm_map_overview.venue = "Venue or neighborhood if known.";
sem llm_map_overview.desc = "Existing archive description.";
sem llm_map_overview.categories = "Comma-separated category tags.";

def search_public_images(query: str) -> list[DossierImage];
sem search_public_images = "Search public Creative Commons / Wikipedia photos for a place, venue, performer, or event. Returns up to a few image hits with url, caption, credit, and source.";
sem search_public_images.query = "A short search phrase, e.g. 'Blue Llama Jazz Club Ann Arbor' or 'Hill Auditorium'.";

def llm_image_queries(
    name: str, kind: str, venue: str, organizer: str, desc: str
) -> ImageQueryPlan by llm(temperature=0.2, max_tokens=120);
sem llm_image_queries = "Propose 1 to 3 short web-image search queries for an Ann Arbor dossier card. Prefer the venue or storefront when the event itself is obscure. Include 'Ann Arbor' when it helps. No quotes, no punctuation fluff. queries must be concrete place/people names.";
sem llm_image_queries.name = "Node title (event, venue, organizer, alert, or civic item).";
sem llm_image_queries.kind = "event, venue, organizer, alert, civic, or category.";
sem llm_image_queries.venue = "Venue name if known.";
sem llm_image_queries.organizer = "Organizer or host if known.";
sem llm_image_queries.desc = "Short archive description.";

def llm_curate_images(
    name: str, kind: str, venue: str, organizer: str, desc: str
) -> DossierMedia by llm(
    tools=[search_public_images],
    temperature=0.2,
    max_tokens=400,
    max_react_iterations=4
);
sem llm_curate_images = "Gather 1-3 relevant public photos for an Ann Arbor dossier sidebar. Call search_public_images with concrete queries (venue, store name, landmark, performer). Prefer venue/storefront/campus photos when the event itself has no poster. Return only real URLs from tool results — never invent URLs. Fill caption/credit/source from the tool. Set ai=true and echo the queries you used.";
sem llm_curate_images.name = "Node title.";
sem llm_curate_images.kind = "Node kind.";
sem llm_curate_images.venue = "Venue if any.";
sem llm_curate_images.organizer = "Organizer if any.";
sem llm_curate_images.desc = "Archive description.";

# ---------------------------------------------------------------- helpers (bodies in pulse.impl.jac)
def _has_llm -> bool;
def _ensure_seed -> Hub;
def _migrate_seed_extras(hub: Hub);
def _hub -> Hub;
def _miles(lat1: float, lng1: float, lat2: float, lng2: float) -> float;
def _cats_of(n: PulseNode) -> list[str];
def _venue_of(n: PulseNode) -> PulseNode | None;
def llm_event_on_date(when_text: str, event_name: str, target_iso: str) -> bool by llm(
    temperature=0.0, max_tokens=20
);
sem llm_event_on_date = "Return true only if this Ann Arbor listing clearly happens on the calendar day target_iso (YYYY-MM-DD). Use the when_text and event name. If the when text is only a weekday with no date, treat it as that weekday in the same week as target_iso. If you cannot tell, return false.";
sem llm_event_on_date.when_text = "Free-form when / date string from the listing.";
sem llm_event_on_date.event_name = "Event title.";
sem llm_event_on_date.target_iso = "Target calendar day as YYYY-MM-DD.";

def _passes(n: PulseNode, spec: FilterSpec, clat: float, clng: float) -> bool;
def _node_on_date(n: PulseNode, date_iso: str) -> bool;
def _has_dated_event(host: PulseNode, spec: FilterSpec, clat: float, clng: float) -> bool;
def _edge_label(a: PulseNode, b: PulseNode) -> str;
def _gnode(n: PulseNode, depth: int) -> GNode;
def _is_expandable(kind: str) -> bool;
def _find_key(key: str) -> PulseNode | None;
def _action_for(n: PulseNode, reasons: list[str], commute: str) -> str;
def _bus_action_for(n: PulseNode, reasons: list[str]) -> str;
def _heuristic_filters(text: str, prior: FilterSpec) -> FilterSpec;
def _profile_for(uid: str) -> UserProfile | None;
def _profile_dict(p: UserProfile) -> dict;
def _nearest_place_node(lat: float, lng: float) -> Place | None;
def _radial_layout(nodes: list[GNode]);
def _browse_child_nodes(
    focus_key: str, spec: FilterSpec, clat: float, clng: float
) -> list[PulseNode];

# ---------------------------------------------------------------- walkers
"""Traverse N hops out from a center node, keeping only paths that pass every filter."""
walker:pub EgoSnapshot {
    has center_key: str = "",
        hops: int = 2,
        categories: list[str] = [],
        kinds: list[str] = [],
        price: str = "any",
        time: str = "week",
        date: str = "",
        distance: float = 0.0,
        clat: float = 42.2780,
        clng: float = -83.7382,
        depth_of: dict[str, int] = {},
        out_nodes: list[GNode] = [],
        out_edges: list[GEdge] = [],
        edge_seen: list[str] = [],
        reports: list[Snapshot] = [];

    can start with Root entry;
    can expand with PulseNode entry;
    can finish with Root exit;
}

"""Lens browse: root → Places / What's on / Who / City pulse, then drill one layer at a time."""
walker:pub NetworkBrowse {
    has focus_key: str = "root",
        categories: list[str] = [],
        kinds: list[str] = [],
        price: str = "any",
        time: str = "week",
        date: str = "",
        distance: float = 0.0,
        clat: float = 42.2780,
        clng: float = -83.7382,
        reports: list[Snapshot] = [];

    can start with Root entry;
}

"""Project the same filtered graph truth into map pins and closure lines.

Optional `persona` pulls in alerts/civic that AffectsRoute the persona's home
or commute places, even when outside the distance slider.
"""
walker:pub MapSnapshot {
    has categories: list[str] = [],
        kinds: list[str] = [],
        price: str = "any",
        time: str = "week",
        date: str = "",
        distance: float = 0.0,
        clat: float = 42.2780,
        clng: float = -83.7382,
        persona: str = "",
        route_keys: list[str] = [],
        items: list[MapItem] = [],
        reports: list[list[MapItem]] = [];

    can start with Root entry;
    can scan with Hub entry;
    can pin with PulseNode entry;
    can finish with Root exit;
}

"""Find candidate center nodes by name, kind or category."""
walker:pub SearchArchive {
    has query: str = "",
        found: list[GNode] = [],
        reports: list[list[GNode]] = [];

    can start with Root entry;
    can scan with Hub entry;
    can finish with Root exit;
}

"""Build the detail card for one node: when, where, who, source and neighbors."""
walker:pub GetDossier {
    has node_id: str = "",
        reports: list[Dossier] = [];

    can start with Root entry;
    can read with PulseNode entry;
}

"""Monday crew: walk from a persona to its interests, places and follows, then rank what matters.
debug=True returns the trace on Brief.trace; every full run also appends it to logs/briefs.jsonl.
score_only=True stops after ranking (no Editor, nothing stored or logged) for the debug panel."""
walker:pub GenerateBrief {
    has persona: str = "student",
        use_ai: bool = True,
        debug: bool = False,
        score_only: bool = False,
        reports: list[Brief] = [];

    can start with Root entry;
    can rank with UserProfile entry;
}

"""Thumbs up/down: nudge the persona's category weights for next week's ranking."""
walker:pub Feedback {
    has persona: str = "student",
        item_key: str = "",
        up: bool = True,
        reports: list[dict] = [];

    can start with Root entry;
    can adjust with UserProfile entry;
}

# ---------------------------------------------------------------- functions
"""Seed (idempotently) and report graph size."""
def:pub seed_pulse() -> dict {
    hub = _ensure_seed();
    return {"nodes": len([hub -->]), "city": hub.city};
}

"""Update the custom persona's home, commute and interests."""
def:pub update_custom_profile(home_key: str, commute: str, interests: list[str]) -> dict;

"""Conversational refine: parse natural language into filters, merging with the prior view."""
def:pub converse_query(text: str, prior: FilterSpec) -> FilterSpec;

"""Persona catalogue with profile chips (shared demo personas only)."""
def:pub list_personas() -> list[dict];

"""This browser's own profile, created on first call from the "You" defaults.
uid is a random ID the browser keeps in localStorage; the profile's persona key is "u-<uid>"."""
def:pub get_profile(uid: str) -> dict;

"""Save onboarding answers to this browser's profile and mark it onboarded.
commute is walk, bike, car or bus; via, interests and follows are keys/names from onboarding_options."""
def:pub save_profile(
    uid: str,
    home_key: str,
    home_lat: float = 0.0,
    home_lng: float = 0.0,
    home_label: str = "",
    commute: str = "walk",
    via: list[str] = [],
    dest_key: str = "",
    dest_label: str = "",
    interests: list[str] = [],
    follows: list[str] = []
) -> dict;

"""The closest of the graph's neighborhoods to a point: {key, name, dist} (miles)."""
def:pub nearest_place(lat: float, lng: float) -> dict;

"""Neighborhoods a commute passes through, in order from home to destination.
TODO: straight-line approximation (places within ~0.5 mi of the segment); swap in real routing."""
def:pub route_places(home_key: str, dest_key: str) -> list[dict];

"""Everything the onboarding screens offer: neighborhoods, categories, and organizers with their categories."""
def:pub onboarding_options() -> dict;

"""Browser Maps JavaScript API key (a public, referrer-restricted key) from GOOGLE_MAPS_API_KEY."""
def:pub maps_config() -> dict {
    return {"key": os.environ.get("GOOGLE_MAPS_API_KEY", "").strip()};
}

"""Address / company autocomplete (2–3 hits), biased to Ann Arbor."""
def:pub suggest_places(query: str) -> list[PlaceSuggestion];

"""Resolve one address or place name to coordinates."""
def:pub geocode_address(query: str) -> PlaceSuggestion;

"""Read a profile's last generated brief aloud with ElevenLabs (ELEVENLABS_API_KEY /
_VOICE_ID / _MODEL). Takes a persona key or a profile id (jid), never text: it
speaks UserProfile.last_summary, generating the brief first if there is none.
voice_id must be one of list_voices() (empty uses ELEVENLABS_VOICE_ID or the
default). Rate limited per profile and per client IP (services/voice_guard.jac).
Returns {"audio": "data:audio/mpeg;base64,...", "error": ""}; on failure audio is ""
with "code" (tts_unavailable, unknown_profile, unknown_voice, rate_limited,
no_brief, tts_error, text_not_accepted) and, when rate limited, "retry_after"
seconds. The client falls back to the browser voice whenever audio is empty.
`text` exists only to refuse it explicitly: any value is an error."""
async def:pub speak_brief(persona: str = "", voice_id: str = "", profile_id: str = "", text: str = "") -> dict;

"""Voice actors for the brief: the account's voices when the key has voices_read,
otherwise a curated set of ElevenLabs premade voices. Each: {id, name, desc}."""
def:pub list_voices() -> dict;

"""Short AI (or heuristic) overview blurb for a map pin / dossier node."""
def:pub map_pin_overview(node_id: str) -> MapOverview;

"""Public photos for a dossier node (venue / event / organizer). Agent + CC search."""
def:pub dossier_images(node_id: str) -> DossierMedia;
