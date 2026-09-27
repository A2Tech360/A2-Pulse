import urllib.request
import json
import os
import ssl

def fetch_happening_umich():
    try:
        url = "http://events.umich.edu/day/json?v=2"
        ctx = ssl._create_unverified_context()
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://events.umich.edu/",
            "Cookie": ""
        })
        with urllib.request.urlopen(req, timeout=10, context=ctx) as r:
            data = json.loads(r.read())
            events = []
            for e in data:
                events.append({
                    "key": f"um-{e.get('id', '')}",
                    "name": e.get("event_title", ""),
                    "desc": (e.get("description", "") or "")[:200],
                    "when": e.get("time_start", ""),
                    "price": 0.0,
                    "lat": 42.2780,
                    "lng": -83.7382,
                    "cats": ["academic"],
                    "src": "src-um",
                    "source_url": e.get("permalink", "https://events.umich.edu")
                })
            return events
    except Exception as ex:
        print(f"[ingestion] happening@umich failed: {ex}")
        return []

def fetch_legistar():
    try:
        url = "https://webapi.legistar.com/v1/a2gov/events?$top=10&$orderby=EventDate+desc"
        with urllib.request.urlopen(url, timeout=5) as r:
            data = json.loads(r.read())
            if not isinstance(data, list):
                return []
            items = []
            for e in data:
                if not e:
                    continue
                items.append({
                    "key": f"leg-{e.get('EventId', '')}",
                    "name": e.get("EventBodyName") or "City Council Meeting",
                    "desc": (e.get("EventComment") or "Ann Arbor City Council meeting.")[:200],
                    "when": e.get("EventDate") or "",
                    "price": 0.0,
                    "lat": 42.2820,
                    "lng": -83.7460,
                    "cats": ["civic", "community"],
                    "src": "src-leg",
                    "source_url": e.get("EventAgendaFile") or "https://a2gov.legistar.com/Calendar.aspx"
                })
            return items
    except Exception as ex:
        print(f"[ingestion] legistar failed: {ex}")
        return []

def fetch_all():
    results = []
    umich = fetch_happening_umich()
    print(f"[ingestion] umich returned: {len(umich)}")
    legistar = fetch_legistar()
    print(f"[ingestion] legistar returned: {len(legistar)}")
    results.extend(umich)
    results.extend(legistar)
    print(f"[ingestion] total: {len(results)}")
    return results
