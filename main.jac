"""A2 Pulse - Ann Arbor's living local graph. Entry: endpoints + router."""

import from services.pulse {
    EgoSnapshot, NetworkBrowse, MapSnapshot, SearchArchive, GetDossier, GenerateBrief,
    Feedback,
    seed_pulse, converse_query, list_personas, update_custom_profile, maps_config,
    suggest_places, geocode_address, speak_brief, list_voices, map_pin_overview,
    dossier_images,
    Snapshot, GNode, GEdge, MapItem, Dossier, Brief, BriefItem, FilterSpec,
    PlaceSuggestion, MapOverview, DossierMedia, DossierImage
}
import from services.pulse { sync_online_events, list_live_events, SyncReport }

import ".styles.global.css";
import from "@jac/runtime" { Router }
import from .components.AppShell { AppShell }

def:pub app() -> JsxElement {
    return <Router>
        <AppShell />
    </Router>;
}
