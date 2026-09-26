"""A2 Pulse - Ann Arbor's living local graph. Entry: endpoints + router."""

import from services.pulse {
    EgoSnapshot, MapSnapshot, SearchArchive, GetDossier, GenerateBrief, Feedback,
    seed_pulse, converse_query, list_personas, update_custom_profile, maps_config,
    Snapshot, GNode, GEdge, MapItem, Dossier, Brief, BriefItem, FilterSpec
}

import ".styles.global.css";
import from "@jac/runtime" { Router }
import from .components.AppShell { AppShell }

def:pub app() -> JsxElement {
    return <Router>
        <AppShell />
    </Router>;
}
