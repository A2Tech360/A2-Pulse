# A2 Pulse

**Your Ann Arbor, briefed and mapped.**

A2 Pulse pulls Ann Arbor's scattered local information into one graph: U-M events,
downtown venues, road closures, transit detours and City Council items. It turns
that graph into a short spoken brief for your week, plus an interactive map and a
graph explorer. Built with [Jac](https://www.jaseci.org/) for the A2Tech360
Hackathon (Local Impact track), University of Michigan, Sept 26–27, 2026.

## Features

- **My Monday (voice brief).** Pick a persona and get the five items that matter
  most this week, each with a short "why" and "what to do". An LLM writes it as a
  spoken brief, and ElevenLabs reads it aloud in the voice you choose. Thumbs
  up/down on an item adjusts that persona's weights for the next brief.
- **Map.** Every event, club, closure and council item on Google Maps. Closures
  and detours are drawn along the actual streets. Filter by category, price,
  day and distance, or ask in plain English ("free music near campus").
- **Network.** The knowledge graph itself: browse by places, topics and hosts,
  open a dossier for any node, and follow its links. The day and category
  filters you set here carry over to the map.
- **Live sync.** Opening the app pulls seven public calendars into the graph
  (see [Data sources](#data-sources)), then refreshes the map and network. The
  server skips repeat syncs within 3 minutes; "Sync live events" on the Network
  page forces one.

## How the brief works

The graph links each user to where they live, how they commute, what they're
into, and who they follow:

```
User ─lives_at──────→ Place ←─affects_route─ Alert / Council item
User ─commutes_via──→ Place ←─near─ Venue ←─hosted_at─ Event
User ─interested_in─→ Category ←─tagged_as─ Event
User ─follows───────→ Organizer ←─organized_by─ Event
```

The `GenerateBrief` walker starts at the user's profile and walks those edges.
It scores everything it reaches: closures on your home or commute route weigh
most, then organizers you follow, then your interests, then things happening
near you. Items in the next couple of days get a boost. The top five go to the
LLM, which writes the brief (without an LLM key, a template writes it instead).
The ranking is plain graph logic, so every item carries the reason it was
picked.

## Getting started

Requires [Jac](https://www.jaseci.org/) **0.37.x**. Older versions use syntax
this code no longer accepts (see [Development](#development)).

```bash
jac install              # install Python and npm dependencies
cp .env.example .env     # then fill in your keys
jac run --serve empty    # serves the app on http://localhost:8000
```

The app opens on My Monday (`/monday`); the other pages are `/map` and `/network`.

### Environment variables

| Variable | Needed for | Without it |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | The map (Maps JavaScript API; a browser key restricted by referrer) | The Map page shows setup instructions instead of a map |
| `ELEVENLABS_API_KEY` | Reading the brief aloud | The brief is text only |
| `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL` | Default voice and model (optional) | Uses "George" and `eleven_flash_v2_5` |
| `OPENAI_API_KEY` | Writing the brief, plain-English map search, pin summaries, dossier photos | Template brief and keyword-only search |
| `LLM_MODEL` | Which model byLLM uses (optional) | `gpt-4o-mini` |

## Data sources

**Live**, synced when the app opens (`services/event_ingest.jac`):

| Source | How it's read |
|---|---|
| Happening @ Michigan | JSON API, this week and next ([below](#happening--michigan)) |
| The Ark, Ann Arbor Observer | The Events Calendar (Tribe) JSON API |
| Eventbrite (Ann Arbor) | Page data embedded in the listing page |
| UMS, Ann Arbor District Library, Marquee Arts | Page text, with LLM extraction when a key is set |

**Built-in demo data** (`services/seed_data.jac`): venues, clubs, road closures,
TheRide detours, City Council items and the demo personas. Closure and detour
lines were traced from OpenStreetMap street geometry.

### Happening @ Michigan

`services/umich_feed.py` fetches `events.umich.edu/week/<date>/json?v=2` for this
week and next. It keeps only events that haven't ended, and finds each
building's coordinates with OpenStreetMap's Nominatim, cached in
`services/.geocache.json`. Online events, away games and events that name only
a room aren't pinned on the map.

The feed sits behind Cloudflare, which often blocks server requests with a 403.
When that happens, sync uses the last good response in
`services/.um_feed_cache.json`. To refresh it by hand, open
`http://events.umich.edu/week/<today's date>/json?v=2` in your browser, save the
page as `services/.um_feed_cache.json`, and sync again. The server log shows
which was used:

```
[umich_feed] using cached feed from Sun Sep 27 11:48 AM
[umich_feed] placed 150/210 upcoming events (0 past skipped, 60 new geocodes)
```

Each sync looks up at most 60 new buildings (Nominatim allows about one request
per second), so the number of placed events climbs over the first few syncs.

## Project structure

```
main.jac                      App entry: mounts AppShell
components/
  AppShell.jac                Header, routes, shared filters, theme
  NetworkPage.jac             Graph explorer and dossiers
  MapPage.jac, MapChrome.jac  Map page, legend and address search
  google_maps.jac             Google Maps loader, pins and closure lines
  MondayPage.jac              Voice brief, personas, voice picker
  FilterBar.jac               Category, price, day and distance filters
  pulse_theme.jac             Shared palette, labels and filter defaults
  ui/                         jac-shadcn components
services/
  pulse.jac, pulse.impl.jac   Graph schema, walkers and endpoints (the "pulse" app)
  seed_data.jac               Demo graph: places, venues, events, alerts, personas
  event_ingest.jac/.impl.jac  Live calendar sync (runs inside the pulse app)
  umich_feed.py               Happening @ Michigan fetch and geocoding
  event_parse.py              Per-site calendar parsers
  event_dates.py              Date matching for the day filter
```

`jac.toml` declares two apps: `empty` (the web app) and `pulse` (the service
holding the graph, served under `/pulse`). The live sync writes graph nodes, so
it runs inside `pulse`, and its endpoints are exposed through `services/pulse.jac`.

## API

Every `walker:pub` and `def:pub` in `services/pulse.jac` is a POST endpoint
under `/pulse`, for example:

```bash
# Sync live calendars into the graph
curl -X POST localhost:8000/pulse/function/sync_online_events \
  -H 'content-type: application/json' -d '{"force": true}'

# Map pins for a given day
curl -X POST localhost:8000/pulse/walker/MapSnapshot \
  -H 'content-type: application/json' -d '{"date": "2026-09-28"}'

# A persona's brief ("student", "shop" or "custom")
curl -X POST localhost:8000/pulse/walker/GenerateBrief \
  -H 'content-type: application/json' -d '{"persona": "student"}'
```

The full list is at `http://localhost:8000/openapi.json` while the server runs.

## Development

- `jac check` type-checks both apps; run it before pushing.
- Server changes need a restart; the running server won't reload them.
- The graph persists between runs. Seeding is idempotent, and seed changes to
  alert paths are applied to existing graphs on startup.
- **Everyone on the team needs the same Jac version.** Code written for older Jac
  (`sv import`, `.cl.jac` files, bare `dict`, edges without endpoints) fails on
  0.37. `jac fix placement` migrates the placement markers; `jac guide` lists the
  reference guides for the current syntax.

## Tech

[Jac](https://www.jaseci.org/) (graph, walkers, full-stack app) ·
[byLLM](https://www.jaseci.org/) with OpenAI `gpt-4o-mini` ·
[ElevenLabs](https://elevenlabs.io) (voice) ·
[Google Maps JavaScript API](https://developers.google.com/maps) ·
[OpenStreetMap](https://www.openstreetmap.org) (Nominatim geocoding, street
geometry) · [jac-shadcn](https://ui.shadcn.com) and Tailwind (UI)
