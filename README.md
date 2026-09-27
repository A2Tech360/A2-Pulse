# A2 Pulse

**Your Ann Arbor, briefed and mapped. Don't scroll it, feel it.**

A2 Pulse pulls Ann Arbor’s scattered local information into one graph — U-M events,
downtown venues, road closures, transit detours, and City Council items — then turns
that graph into a one-minute spoken brief for your week, plus an interactive map and
a graph explorer.

Built with [Jac](https://www.jaseci.org/) for the A2Tech360 Hackathon (Local Impact
track), University of Michigan, Sept 26–27, 2026.

| Page | URL | What it does |
|------|-----|----------------|
| My Monday | `/monday` | Personalized weekly brief + voice |
| Map | `/map` | Pins and road-snapped closures |
| Network | `/network` | Living knowledge graph + dossiers |
| Welcome | `/welcome` | First-time onboarding |

---

## Features

- **My Monday (voice brief).** The five items that matter most this week, each with a
  short “why” and “what to do,” written as a spoken brief and read aloud by
  ElevenLabs. Switch between demo personas (Student, Shop owner) or **You**. Thumbs
  up/down adjusts that profile’s interest weights for the next brief.
- **Onboarding.** Three quick steps (home, commute, interests, who to follow) that
  turn this browser’s “You” profile into a real node in the graph, then land on My
  Monday.
- **Map.** Events, clubs, closures, and council items on Google Maps. Closures and
  detours are snapped onto the road network. Filter by category, price, day, and
  distance, or ask in plain English (“free music near campus”).
- **Network.** Browse the knowledge graph by places, topics, and hosts; open a
  dossier (with photos) for any node. A single sidebar switches between **Here**
  (where you are in the graph) and **Detail** (the selected node). Hover starts
  prefetching the dossier so clicks feel instant. Filters stay in sync with the Map.
- **Live sync (manual).** Use **Sync live events** on the Network page to pull
  public calendars into the graph. The server skips repeat syncs within a few
  minutes and never runs two at once. Sync is **not** automatic on every page open.

### Special feature: Post your own events

Anyone can add a neighbor-made event from the **Network** page. Your post becomes a real event node on the shared graph — tagged by topic, filterable with everything else, and visible on the Map and in briefs when community posts are included — so local happenings don’t have to wait for a calendar scraper.

---

## How the brief works

Each profile is linked into the graph:

```
User ─lives_at──────→ Place ←─affects_route─ Alert / Council item
User ─commutes_via──→ Place ←─near─ Venue ←─hosted_at─ Event
User ─interested_in─→ Category ←─tagged_as─ Event
User ─follows───────→ Organizer ←─organized_by─ Event
```

`GenerateBrief` starts at the profile, walks those edges, and scores what it
reaches: closures on your home or commute weigh most, then organizers you follow,
your interests, and things near you. Items in the brief’s Monday–Sunday week get a
boost. Candidate walks are capped so ranking stays responsive after a large live
sync.

The top five go to the Editor (`services/brief_editor.jac`). With an LLM
configured, it writes a short spoken brief (about 120–150 words); otherwise a
conversational template (`services/brief_narrative.jac`) is used. Each LLM call has
an **8-second** deadline and falls back to the template. `services/speakable.jac`
then cleans times, dates, and abbreviations for ElevenLabs.

Open My Monday with `?debug=1` to see how every candidate was scored.

---

## Getting started

Use the **same Jac version** as the team. This project uses `sv import` and
`.cl.jac` files (Jac **0.34.x**; check with `jac --version`).

```bash
jac install                 # Python + npm deps
cp .env.example .env        # then fill in keys you have
jac start --dev main.jac    # http://localhost:8000 (or --port 8010)
```

New visitors hit `/welcome` once; returning visitors open on `/monday`.

### Environment variables

Full comments live in `.env.example`.

| Variable | Needed for | Without it |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | Map (Maps JS API); Roads API for snapping closures | Map shows setup help; closures snap via OSRM |
| `ELEVENLABS_API_KEY` | Spoken brief | Text-only brief |
| `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL` | Default voice / model | Built-in defaults |
| `LLM_MODEL` + provider key | LLM brief, Ask-box filters, pin/dossier helpers. LiteLLM names, e.g. `gpt-4o-mini`, `claude-haiku-4-5`, `gemini/gemini-3.1-flash-lite` | Templates + heuristics only (LLM off) |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) | Provider auth for the model you chose | That provider won’t run |
| `LLM_API_KEY`, `LLM_API_BASE` | One key for any provider, or an OpenAI-compatible gateway | Named provider key is used |

Leave `LLM_MODEL` unset (or `off`) to run with **no** LLM calls.

---

## Data sources

**Live** (when you sync from Network), via `services/event_ingest.jac`:

| Source | How it’s read |
|---|---|
| Happening @ Michigan | JSON API for this week and next ([below](#happening--michigan)) |
| The Ark, Ann Arbor Observer | The Events Calendar (Tribe) JSON API |
| Eventbrite (Ann Arbor) | Embedded listing page data |
| UMS, Ann Arbor District Library, Marquee Arts | Page text; LLM extraction when an LLM is on |

**Built-in demo data** (`services/seed_data.jac`): venues, clubs, road closures,
TheRide detours, City Council items, and demo personas. Paths are snapped by
`services/road_snap.py` (Google Roads when a Maps key is set, else OSRM) and
cached in `services/.road_snap_cache.json`.

### Happening @ Michigan

`services/umich_feed.py` fetches `events.umich.edu/week/<date>/json?v=2` for this
week and next, keeps events that haven’t ended, and geocodes buildings with
Nominatim (cached in `services/.geocache.json`). Online-only / away / room-only
listings aren’t pinned. Prices stay unknown unless the listing states one.

Cloudflare often blocks server fetches (403). Sync then reuses
`services/.um_feed_cache.json`. To refresh by hand: open the JSON URL in a
browser, save it as that cache file, and sync again. Logs look like:

```
[umich_feed] using cached feed from Sun Sep 27 11:48 AM
[umich_feed] placed 150/210 upcoming events (0 past skipped, 60 new geocodes)
```

Each sync geocodes at most ~60 new buildings (Nominatim ~1 req/s).

---

## Project structure

```
main.jac                       Entry: mounts AppShell + public walkers/functions
components/
  AppShell.jac                 Header, routes, shared filters, theme
  WelcomePage.jac              Onboarding
  MondayPage.jac               Voice brief, personas, voice picker
  BriefDebugPanel.jac          Scoring panel (?debug=1)
  MapPage.jac, MapChrome.jac   Map, legend, address search
  NetworkPage.jac              Graph explorer, dossiers, manual sync
  FilterBar.jac                Shared filters (Map / Network)
  google_maps.cl.jac           Maps loader, pins, closure lines
  profile_store.cl.jac         Per-browser profile ID
  net.cl.jac                   Client timeouts / Promise helpers
  pulse_theme.cl.jac           Palette, labels, filter defaults
  ui/                          jac-shadcn primitives
services/
  pulse.jac, pulse.impl.jac    Graph schema, walkers, dossiers, brief ranking
  seed_data.jac                Demo graph
  brief_*.jac                  Week window, Editor, template, traces
  pulse_llm.jac, llm_env.jac   Provider-neutral LLM setup
  speakable.jac, voice_guard.jac   TTS cleanup + rate limits
  event_ingest.jac/.impl.jac   Live calendar sync
  umich_feed.py, road_snap.py  Feed + road snapping
  event_parse.py, event_*.jac  Parsers, categories, dates/times
scripts/eval_briefs            Brief quality eval on a throwaway graph
```

Graph state persists under `.jac/data/` between runs.

---

## API

Every `walker:pub` / `def:pub` is a POST endpoint (`/walker/<name>`,
`/function/<name>`). Examples (adjust host/port to match `jac start`):

```bash
# Force-pull live calendars into the graph
curl -X POST localhost:8000/function/sync_online_events \
  -H 'content-type: application/json' -d '{"force": true}'

# Persona brief: "student", "shop", or "custom"
curl -X POST localhost:8000/walker/GenerateBrief \
  -H 'content-type: application/json' \
  -d '{"persona": "student", "use_ai": true}'
```

---

## Development

- Tests sit next to the code as `*.test.jac` — run with `jac test`.
- `jac check <file>` type-checks; follow `jac guide …` hints in diagnostics.
- `scripts/eval_briefs` scores demo + synthetic profiles into
  `reports/eval_briefs.md` (`--require-llm` fails if the LLM is off).
- **Client** Jac (`.cl.jac` / JSX) hot-reloads; **server** Jac needs a process
  restart after changes.
- After schema changes, a stale `.jac/data/anchor_store.db` can slow loads
  (schema-drift warnings). Resetting that DB and re-seeding (then syncing live
  events again if you need them) clears it.

---

## Tech

[Jac](https://www.jaseci.org/) (graph, walkers, full-stack) ·
[byLLM](https://www.jaseci.org/) via LiteLLM ·
[ElevenLabs](https://elevenlabs.io) ·
[Google Maps JavaScript + Roads APIs](https://developers.google.com/maps) ·
[OpenStreetMap](https://www.openstreetmap.org) (Nominatim, OSRM) ·
[jac-shadcn](https://ui.shadcn.com) + Tailwind
