"""Ann Arbor fixture data for the A2 Pulse graph (cached, demo-safe)."""

glob SRC_UM: str = "https://events.umich.edu";
glob SRC_EB: str = "https://www.eventbrite.com/d/mi--ann-arbor/events/";
glob SRC_CITY: str = "https://www.a2gov.org/calendar";
glob SRC_RIDE: str = "https://www.theride.org/alerts";
glob SRC_LEG: str = "https://a2gov.legistar.com/Calendar.aspx";
glob SRC_ROAD: str = "https://www.a2gov.org/road-closures";

glob SOURCES: list[dict] = [
    {"key": "src-um", "name": "Happening @ Michigan", "url": SRC_UM},
    {"key": "src-eb", "name": "Eventbrite", "url": SRC_EB},
    {"key": "src-city", "name": "City of Ann Arbor", "url": SRC_CITY},
    {"key": "src-ride", "name": "TheRide", "url": SRC_RIDE},
    {"key": "src-leg", "name": "Legistar", "url": SRC_LEG},
    {"key": "src-road", "name": "City Road Closures", "url": SRC_ROAD}
];

glob CATEGORIES: list[str] = [
    "music", "food", "sports", "academic", "social", "arts", "community",
    "outdoor", "civic", "networking", "nightlife", "comedy"
];

glob PLACES: list[dict] = [
    {"key": "pl-central", "name": "Central Campus", "lat": 42.2770, "lng": -83.7382},
    {"key": "pl-north", "name": "North Campus", "lat": 42.2920, "lng": -83.7160},
    {"key": "pl-main", "name": "Main Street", "lat": 42.2800, "lng": -83.7483},
    {"key": "pl-kerry", "name": "Kerrytown", "lat": 42.2846, "lng": -83.7456},
    {"key": "pl-plymouth", "name": "Plymouth Rd corridor", "lat": 42.3000, "lng": -83.7120},
    {"key": "pl-state", "name": "State Street", "lat": 42.2755, "lng": -83.7405},
    {"key": "pl-washtenaw", "name": "Washtenaw Ave", "lat": 42.2730, "lng": -83.7280},
    {"key": "pl-ypsi", "name": "Ypsilanti", "lat": 42.2411, "lng": -83.6130}
];

glob VENUES: list[dict] = [
    {"key": "v-ark", "name": "The Ark", "address": "316 S Main St", "lat": 42.2793, "lng": -83.7485, "place": "pl-main"},
    {"key": "v-hill", "name": "Hill Auditorium", "address": "825 N University Ave", "lat": 42.2791, "lng": -83.7383, "place": "pl-central"},
    {"key": "v-union", "name": "Michigan Union", "address": "530 S State St", "lat": 42.2750, "lng": -83.7416, "place": "pl-state"},
    {"key": "v-llama", "name": "Blue LLama Jazz Club", "address": "314 S Main St", "lat": 42.2796, "lng": -83.7488, "place": "pl-main"},
    {"key": "v-aadl", "name": "AADL Downtown Library", "address": "343 S Fifth Ave", "lat": 42.2787, "lng": -83.7456, "place": "pl-main"},
    {"key": "v-pier", "name": "Pierpont Commons", "address": "2101 Bonisteel Blvd", "lat": 42.2913, "lng": -83.7171, "place": "pl-north"},
    {"key": "v-gallup", "name": "Gallup Park", "address": "3000 Fuller Rd", "lat": 42.2745, "lng": -83.7040, "place": "pl-washtenaw"},
    {"key": "v-market", "name": "Ann Arbor Farmers Market", "address": "315 Detroit St", "lat": 42.2851, "lng": -83.7453, "place": "pl-kerry"},
    {"key": "v-cityhall", "name": "Larcom City Hall", "address": "301 E Huron St", "lat": 42.2820, "lng": -83.7460, "place": "pl-main"},
    {"key": "v-blindpig", "name": "The Blind Pig", "address": "208 S First St", "lat": 42.2802, "lng": -83.7498, "place": "pl-main"},
    {"key": "v-michtheater", "name": "Michigan Theater", "address": "603 E Liberty St", "lat": 42.2790, "lng": -83.7415, "place": "pl-state"},
    {"key": "v-power", "name": "Power Center", "address": "121 Fletcher St", "lat": 42.2798, "lng": -83.7365, "place": "pl-central"},
    {"key": "v-rackham", "name": "Rackham Auditorium", "address": "915 E Washington St", "lat": 42.2805, "lng": -83.7380, "place": "pl-central"},
    {"key": "v-clubabove", "name": "Club Above", "address": "215 S Ashley St", "lat": 42.2795, "lng": -83.7495, "place": "pl-main"},
    {"key": "v-liminal", "name": "Liminal Lounge", "address": "215 S Ashley St", "lat": 42.2796, "lng": -83.7496, "place": "pl-main"},
    {"key": "v-funhouse", "name": "Ann Arbor Funhouse", "address": "2370 Carpenter Rd", "lat": 42.2505, "lng": -83.6780, "place": "pl-washtenaw"},
    {"key": "v-literati", "name": "Literati Bookstore", "address": "124 E Washington St", "lat": 42.2802, "lng": -83.7468, "place": "pl-main"},
    {"key": "v-freighthouse", "name": "Ypsi Freighthouse", "address": "100 Market Pl, Ypsilanti", "lat": 42.2448, "lng": -83.6115, "place": "pl-ypsi"}
];

glob ORGANIZERS: list[dict] = [
    {"key": "o-ums", "name": "UMS", "org_type": "nonprofit", "venue": "v-hill"},
    {"key": "o-jazz", "name": "U-M Jazz Collective", "org_type": "club", "venue": "v-union"},
    {"key": "o-hike", "name": "Michigan Hiking Club", "org_type": "club", "venue": "v-union"},
    {"key": "o-llama", "name": "Blue LLama", "org_type": "business", "venue": "v-llama"},
    {"key": "o-city", "name": "City of Ann Arbor", "org_type": "city", "venue": "v-cityhall"},
    {"key": "o-ride", "name": "TheRide", "org_type": "city", "venue": "v-cityhall"},
    {"key": "o-aadl", "name": "Ann Arbor District Library", "org_type": "nonprofit", "venue": "v-aadl"},
    {"key": "o-career", "name": "U-M Career Center", "org_type": "club", "venue": "v-union"},
    {"key": "o-zing", "name": "Zingerman's", "org_type": "restaurant", "venue": "v-market"},
    {"key": "o-msaa", "name": "Main Street Area Association", "org_type": "business", "venue": "v-ark"},
    {"key": "o-blindpig", "name": "The Blind Pig", "org_type": "business", "venue": "v-blindpig"},
    {"key": "o-michtheater", "name": "Michigan Theater", "org_type": "nonprofit", "venue": "v-michtheater"},
    {"key": "o-clubabove", "name": "Club Above", "org_type": "business", "venue": "v-clubabove"}
];

# day: 0 = Monday ... 6 = Sunday of the current week
glob EVENTS: list[dict] = [
    {"key": "e-jazz-fri", "name": "Free Jazz Night", "desc": "Student combos and local players trade sets. Walk-ins welcome.", "venue": "v-llama", "org": "o-jazz", "cats": ["music", "social"], "day": 4, "time": "Fri 8:00 PM", "price": 0.0, "src": "src-um", "related": ["e-ark-folk"]},
    {"key": "e-ark-folk", "name": "Folk Songwriters Round", "desc": "Four Michigan songwriters share the stage in the round.", "venue": "v-ark", "org": "o-msaa", "cats": ["music", "arts"], "day": 5, "time": "Sat 7:30 PM", "price": 15.0, "src": "src-eb", "related": []},
    {"key": "e-ums-sym", "name": "UMS Symphony: Rachmaninoff 2", "desc": "Full orchestra with guest pianist at Hill Auditorium.", "venue": "v-hill", "org": "o-ums", "cats": ["music", "arts"], "day": 6, "time": "Sun 4:00 PM", "price": 12.0, "src": "src-um", "related": []},
    {"key": "e-career-mixer", "name": "Tech & Startups Career Mixer", "desc": "Meet 30 Ann Arbor employers hiring interns and new grads.", "venue": "v-union", "org": "o-career", "cats": ["networking", "academic"], "day": 1, "time": "Tue 5:30 PM", "price": 0.0, "src": "src-um", "related": []},
    {"key": "e-hike", "name": "Sunset Hike at Gallup Park", "desc": "Easy 3-mile loop along the Huron River. Meet at the canoe livery.", "venue": "v-gallup", "org": "o-hike", "cats": ["outdoor", "social"], "day": 5, "time": "Sat 6:00 PM", "price": 0.0, "src": "src-um", "related": []},
    {"key": "e-market", "name": "Saturday Farmers Market", "desc": "Local produce, bread and coffee in Kerrytown.", "venue": "v-market", "org": "o-city", "cats": ["food", "community"], "day": 5, "time": "Sat 7:00 AM", "price": 0.0, "src": "src-city", "related": ["e-zing-tasting"]},
    {"key": "e-zing-tasting", "name": "Zingerman's Cheese Tasting", "desc": "Guided tasting of Michigan cheeses and breads.", "venue": "v-market", "org": "o-zing", "cats": ["food"], "day": 3, "time": "Thu 6:30 PM", "price": 25.0, "src": "src-eb", "related": []},
    {"key": "e-first-friday", "name": "First Friday Art Walk", "desc": "Galleries and shops downtown stay open late with live art.", "venue": "v-ark", "org": "o-msaa", "cats": ["arts", "community", "social"], "day": 4, "time": "Fri 6:00 PM", "price": 0.0, "src": "src-city", "related": ["e-jazz-fri"]},
    {"key": "e-aadl-maker", "name": "AADL Maker Night", "desc": "3D printers, sewing machines and synths open to all.", "venue": "v-aadl", "org": "o-aadl", "cats": ["academic", "community"], "day": 2, "time": "Wed 6:00 PM", "price": 0.0, "src": "src-city", "related": []},
    {"key": "e-north-pizza", "name": "North Campus Pizza & Game Night", "desc": "Board games, free pizza and new friends at Pierpont.", "venue": "v-pier", "org": "o-career", "cats": ["social", "food"], "day": 5, "time": "Sat 7:00 PM", "price": 0.0, "src": "src-um", "related": []},
    {"key": "e-pickup", "name": "Pickup Soccer on the Diag", "desc": "Casual pickup game, all levels, bring water.", "venue": "v-union", "org": "o-hike", "cats": ["sports", "outdoor", "social"], "day": 6, "time": "Sun 2:00 PM", "price": 0.0, "src": "src-um", "related": []},
    {"key": "e-llama-brunch", "name": "Jazz Brunch at Blue LLama", "desc": "Live trio with a seasonal brunch menu.", "venue": "v-llama", "org": "o-llama", "cats": ["music", "food"], "day": 6, "time": "Sun 11:00 AM", "price": 8.0, "src": "src-eb", "related": ["e-jazz-fri"]},
    {"key": "e-small-biz", "name": "Downtown Small Business Breakfast", "desc": "Owners share holiday-season plans with the DDA.", "venue": "v-aadl", "org": "o-msaa", "cats": ["networking", "community"], "day": 2, "time": "Wed 8:00 AM", "price": 5.0, "src": "src-city", "related": []},
    {"key": "e-lecture", "name": "Public Lecture: Great Lakes Futures", "desc": "SEAS faculty on climate and water in Michigan.", "venue": "v-hill", "org": "o-ums", "cats": ["academic"], "day": 3, "time": "Thu 4:00 PM", "price": 0.0, "src": "src-um", "related": []},
    {"key": "e-blindpig-indie", "name": "Indie Night at The Blind Pig", "desc": "Local bands and touring acts in the First Street basement.", "venue": "v-blindpig", "org": "o-blindpig", "cats": ["music", "nightlife"], "day": 4, "time": "Fri 9:00 PM", "price": 12.0, "src": "src-eb", "related": []},
    {"key": "e-clubabove", "name": "Club Above Late Set", "desc": "House and disco upstairs above the Pig — doors at 10.", "venue": "v-clubabove", "org": "o-clubabove", "cats": ["nightlife", "music"], "day": 5, "time": "Sat 10:00 PM", "price": 10.0, "src": "src-eb", "related": ["e-blindpig-indie"]},
    {"key": "e-mich-comedy", "name": "Michigan Theater Comedy Night", "desc": "Regional comics in the historic downtown theater.", "venue": "v-michtheater", "org": "o-michtheater", "cats": ["comedy", "arts"], "day": 5, "time": "Sat 8:00 PM", "price": 18.0, "src": "src-eb", "related": []}
];

glob ALERTS: list[dict] = [
    {"key": "a-plymouth", "name": "Plymouth Rd lane closure", "desc": "Eastbound right lane closed for water main work between Huron Pkwy and Nixon.", "alert_type": "closure", "when": "Wed to Fri, 7 AM to 5 PM", "day": 2, "src": "src-road", "org": "o-city", "cats": ["community"], "places": ["pl-plymouth", "pl-north"], "lat": 42.3010, "lng": -83.7100, "path": [[42.2955, -83.7210], [42.2990, -83.7150], [42.3015, -83.7090], [42.3040, -83.7010]]},
    {"key": "a-main-work", "name": "Main St road work", "desc": "Main St narrowed to one lane between Washington and William; loading zones moved.", "alert_type": "closure", "when": "Mon to Thu, 6 AM to 3 PM", "day": 0, "src": "src-road", "org": "o-city", "cats": ["community"], "places": ["pl-main"], "lat": 42.2795, "lng": -83.7483, "path": [[42.2812, -83.7483], [42.2795, -83.7484], [42.2778, -83.7485]]},
    {"key": "a-route4", "name": "TheRide Route 4 detour", "desc": "Route 4 detours off Washtenaw Ave via Packard for utility work.", "alert_type": "detour", "when": "Thu all day", "day": 3, "src": "src-ride", "org": "o-ride", "cats": ["community"], "places": ["pl-washtenaw", "pl-central"], "lat": 42.2735, "lng": -83.7290, "path": [[42.2760, -83.7360], [42.2742, -83.7300], [42.2722, -83.7230], [42.2700, -83.7160]]},
    {"key": "a-state-sidewalk", "name": "State St sidewalk closure", "desc": "West sidewalk closed near the Union; use the east side crossing.", "alert_type": "closure", "when": "All week", "day": 0, "src": "src-road", "org": "o-city", "cats": ["community"], "places": ["pl-state", "pl-central"], "lat": 42.2752, "lng": -83.7412, "path": [[42.2765, -83.7410], [42.2740, -83.7411]]},
    {"key": "a-bus-north", "name": "Bursley-Baits bus reroute", "desc": "U-M buses skip the Pierpont stop during event setup.", "alert_type": "detour", "when": "Sat afternoon", "day": 5, "src": "src-ride", "org": "o-ride", "cats": ["community"], "places": ["pl-north"], "lat": 42.2915, "lng": -83.7180, "path": [[42.2930, -83.7210], [42.2913, -83.7171], [42.2900, -83.7120]]}
];

glob CIVIC: list[dict] = [
    {"key": "c-housing", "name": "Council vote: housing density near campus", "desc": "City Council considers rezoning to allow more housing along State and Packard.", "when": "Mon 7:00 PM, public comment sign-up by Mon noon", "day": 0, "src": "src-leg", "org": "o-city", "cats": ["civic", "community"], "places": ["pl-central", "pl-state"], "lat": 42.2820, "lng": -83.7460},
    {"key": "c-seating", "name": "Outdoor seating ordinance", "desc": "Proposed year-round sidewalk seating rules for downtown restaurants and shops.", "when": "Comment deadline Tue 5:00 PM", "day": 1, "src": "src-leg", "org": "o-city", "cats": ["civic", "food"], "places": ["pl-main", "pl-kerry"], "lat": 42.2805, "lng": -83.7478},
    {"key": "c-bikelanes", "name": "Plymouth Rd protected bike lane plan", "desc": "Transportation Commission hearing on a protected bike lane from North Campus to downtown.", "when": "Wed 6:30 PM hearing", "day": 2, "src": "src-leg", "org": "o-city", "cats": ["civic", "outdoor"], "places": ["pl-plymouth", "pl-north"], "lat": 42.2990, "lng": -83.7140}
];

glob PERSONAS: list[dict] = [
    {"persona": "student", "name": "Jordan, U-M junior", "home": "pl-north", "commute": "bike", "via": ["pl-north", "pl-plymouth", "pl-central"], "interests": ["music", "social", "networking", "food"], "follows": ["o-jazz", "o-career"]},
    {"persona": "shop", "name": "Maya, Main St shop owner", "home": "pl-main", "commute": "car", "via": ["pl-main", "pl-kerry"], "interests": ["arts", "community", "civic", "food"], "follows": ["o-msaa", "o-city"]},
    {"persona": "custom", "name": "You", "home": "pl-central", "commute": "walk", "via": ["pl-central"], "interests": ["music", "outdoor"], "follows": []}
];
