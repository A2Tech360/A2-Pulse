"""A2 Pulse - Ann Arbor's living local graph. Entry: endpoints + router."""

import from services.pulse {
    EgoSnapshot, MapSnapshot, SearchArchive, GetDossier, GenerateBrief, Feedback,
    seed_pulse, converse_query, list_personas, update_custom_profile, maps_config,
    suggest_places, geocode_address, speak_brief, list_voices,
    Snapshot, GNode, GEdge, MapItem, Dossier, Brief, BriefItem, FilterSpec, PlaceSuggestion
}
# Per-browser profiles + onboarding endpoints.
import from services.pulse { get_profile }

import ".styles.global.css";
import from "@jac/runtime" { Router }
import from .components.AppShell { AppShell }

def:pub app() -> JsxElement {
    return <Router>
        <AppShell />
    </Router>;
}
