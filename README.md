# A2 Pulse

**Your Ann Arbor, briefed and mapped.**

A2 Pulse pulls Ann Arbor's scattered local information into one graph: U-M events,
downtown venues, road closures, transit detours and City Council items. It turns
that graph into a one-minute spoken brief for your week, plus an interactive map
and a graph explorer. Built with [Jac](https://www.jaseci.org/) for the A2Tech360
Hackathon (Local Impact track), University of Michigan, Sept 26–27, 2026.

## Features

- **My Monday (voice brief).** The five items that matter most to you this week,
  each with a short "why" and "what to do", written as a spoken brief and read
  aloud by ElevenLabs in the voice you pick. Switch between the demo personas or
  your own profile. Thumbs up/down on an item adjusts that profile's weights for
  the next brief.
- **Onboarding.** New visitors get three quick steps (home, commute route,
  interests, who to follow) that turn this browser's "You" profile into a real
  node in the graph, then land on My Monday.
- **Map.** Every event, club, closure and council item on Google Maps. Closures
  and detours are snapped onto the road network. Filter by category, price, day
  and distance, or ask in plain English ("free music near campus").
- **Network.** The knowledge graph itself: browse by places, topics and hosts,
  open a dossier for any node, and follow its links. Filters are shared with the
  map.
- **Live sync.** Opening the app pulls seven public calendars into the graph
  (see [Data sources](#data-sources)), then refreshes the map and network. The
  server skips repeat syncs within 3 minutes and never runs two at once; "Sync
  live events" on the Network page forces one.

## How the brief works

The graph links each profile to where they live, how they commute, what they're
into, and who they follow:

```
User ─lives_at──────→ Place ←─affects_route─ Alert / Council item
User ─commutes_via──→ Place ←─near─ Venue ←─hosted_at─ Event
User ─interested_in─→ Category ←─tagged_as─ Event
User ─follows───────→ Organizer ←─organized_by─ Event
```

The `GenerateBrief` walker starts at the profile, walks those edges and scores
everything it reaches: closures on your home or commute route weigh most, then
organizers you follow, your interests, and things happening near you. Items due
this week get a boost. The top five go to the Editor (`services/brief_editor.jac`),
which has the LLM write a 120–150 word brief when one is configured, and falls
back to a conversational template (`services/brief_narrative.jac`) otherwise.
`services/speakable.jac` then rewrites the text for text-to-speech (times,
dates, abbreviations) before it goes to ElevenLabs.

To see how every candidate was scored, open My Monday with `?debug=1`.

## Getting started

Everyone on the team must run the **same Jac version**. The code uses `sv import`
and `.cl.jac` files, which Jac 0.35 and later reject, so use the release the
team is on (check with `jac --version`).

```bash
jac install              # install Python and npm dependencies
cp .env.example .env     # then fill in your keys
jac start main.jac       # serves the app on http://localhost:8000
```

The app opens on My Monday (`/monday`); new visitors see onboarding
(`/welcome`) first. The other pages are `/map` and `/network`.

### Environment variables

See `.env.example` for the full list with comments.

| Variable | Needed for | Without it |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | The map (Maps JavaScript API); also the Roads API for snapping closures | The Map page shows setup instructions; closures snap via OSRM instead |
| `ELEVENLABS_API_KEY` | Reading the brief aloud | The brief is text only |
| `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL` | Default voice and model (optional) | Built-in defaults |
| `LLM_MODEL` + that provider's key | LLM-written brief, plain-English search, pin summaries. Any LiteLLM model name, e.g. `gpt-4o-mini` (`OPENAI_API_KEY`), `claude-haiku-4-5` (`ANTHROPIC_API_KEY`), `gemini/gemini-2.0-flash` (`GEMINI_API_KEY`) | **Off by default**: template brief and keyword search, no LLM calls |
| `LLM_API_KEY`, `LLM_API_BASE` | One key for any provider, or an OpenAI-compatible gateway (optional) | The provider-specific key is used |

Each LLM call has an 8-second deadline and falls back to the templates on failure.

## Data sources

**Live**, synced when the app opens (`services/event_ingest.jac`):

| Source | How it's read |
|---|---|
| Happening @ Michigan | JSON API, this week and next ([below](#happening--michigan)) |
| The Ark, Ann Arbor Observer | The Events Calendar (Tribe) JSON API |
| Eventbrite (Ann Arbor) | Page data embedded in the listing page |
| UMS, Ann Arbor District Library, Marquee Arts | Page text, with LLM extraction when an LLM is configured |

**Built-in demo data** (`services/seed_data.jac`): venues, clubs, road closures,
TheRide detours, City Council items and the demo personas. Closure and detour
paths are snapped onto roads by `services/road_snap.py` (Google Roads API when a
Maps key is set, otherwise OSRM), cached in `services/.road_snap_cache.json`.

### Happening @ Michigan

`services/umich_feed.py` fetches `events.umich.edu/week/<date>/json?v=2` for this
week and next. It keeps only events that haven't ended, and finds each
building's coordinates with OpenStreetMap's Nominatim, cached in
`services/.geocache.json`. Online events, away games and events that name only
a room aren't pinned on the map. Prices are left unknown unless the listing
states one.

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
per second), and stops for that sync if Nominatim rate-limits it, so the number
of placed events climbs over the first few syncs.

## Project structure

```
main.jac                       App entry: mounts AppShell
components/
  AppShell.jac                 Header, routes, shared filters, theme, sync on open
  WelcomePage.jac              Onboarding
  MondayPage.jac               Voice brief, personas, voice picker
  BriefDebugPanel.jac          Per-item scoring (My Monday with ?debug=1)
  MapPage.jac, MapChrome.jac   Map page, legend and address search
  NetworkPage.jac              Graph explorer and dossiers
  FilterBar.jac                Category, price, day and distance filters
  google_maps.cl.jac           Google Maps loader, pins and closure lines
  profile_store.cl.jac         This browser's profile ID
  net.cl.jac                   Timeouts and fallbacks for server calls
  pulse_theme.cl.jac           Shared palette, labels and filter defaults
  ui/                          jac-shadcn components
services/
  pulse.jac, pulse.impl.jac    Graph schema, walkers and endpoints
  seed_data.jac                Demo graph: places, venues, events, alerts, personas
  brief_*.jac                  Brief week window, Editor, template, debug traces
  pulse_llm.jac, llm_env.jac   Provider-neutral LLM setup
  speakable.jac                Text-to-speech cleanup
  voice_guard.jac              Rate limits and allowed voices for speak_brief
  event_ingest.jac/.impl.jac   Live calendar sync
  umich_feed.py                Happening @ Michigan fetch and geocoding
  road_snap.py                 Snaps closure paths onto roads
  event_parse.py, event_*.jac  Per-site parsers, categories, dates and times
scripts/eval_briefs            Brief quality eval on a throwaway graph
```

## API

Every `walker:pub` and `def:pub` is a POST endpoint (`/walker/<name>` and
`/function/<name>`), for example:

```bash
# Sync live calendars into the graph
curl -X POST localhost:8000/function/sync_online_events \
  -H 'content-type: application/json' -d '{"force": true}'

# A persona's brief ("student", "shop" or "custom")
curl -X POST localhost:8000/walker/GenerateBrief \
  -H 'content-type: application/json' -d '{"persona": "student"}'
```

## Development

- Tests live next to the code as `*.test.jac`; run them with `jac test`.
- `scripts/eval_briefs` generates briefs for the demo personas and six synthetic
  profiles on a throwaway graph and writes `reports/eval_briefs.md`
  (`--require-llm` fails if the LLM is off).
- Server changes need a restart. The graph persists between runs in `.jac/`.

## Tech

[Jac](https://www.jaseci.org/) (graph, walkers, full-stack app) ·
[byLLM](https://www.jaseci.org/) via LiteLLM (any provider) ·
[ElevenLabs](https://elevenlabs.io) (voice) ·
[Google Maps JavaScript API and Roads API](https://developers.google.com/maps) ·
[OpenStreetMap](https://www.openstreetmap.org) (Nominatim geocoding, OSRM routing) ·
[jac-shadcn](https://ui.shadcn.com) and Tailwind (UI)
