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

# Unambiguous Ann Arbor landmarks for map pins (matched in name / desc / address).
glob LANDMARKS: list[dict] = [
    {"name": "The Diag", "lat": 42.2769, "lng": -83.7382, "aliases": ["the diag", "michigan diag", "um diag", "u-m diag", "on the diag", "at the diag", "at diag"]},
    {"name": "Burns Park", "lat": 42.2714, "lng": -83.7275, "aliases": ["burns park"]},
    {"name": "Gallup Park", "lat": 42.2745, "lng": -83.7040, "aliases": ["gallup park"]},
    {"name": "Michigan Union", "lat": 42.2750, "lng": -83.7416, "aliases": ["michigan union", "the union"]},
    {"name": "Central Campus", "lat": 42.2770, "lng": -83.7382, "aliases": ["central campus"]},
    {"name": "North Campus", "lat": 42.2920, "lng": -83.7160, "aliases": ["north campus"]},
    {"name": "Main Street", "lat": 42.2800, "lng": -83.7483, "aliases": ["main street", "main st"]},
    {"name": "Kerrytown", "lat": 42.2846, "lng": -83.7456, "aliases": ["kerrytown"]},
    {"name": "State Street", "lat": 42.2755, "lng": -83.7405, "aliases": ["state street", "state st"]},
    {"name": "Pierpont Commons", "lat": 42.2913, "lng": -83.7171, "aliases": ["pierpont"]},
    {"name": "Hill Auditorium", "lat": 42.2791, "lng": -83.7383, "aliases": ["hill auditorium", "hill aud"]},
    {"name": "The Ark", "lat": 42.2793, "lng": -83.7485, "aliases": ["the ark"]},
    {"name": "Blue LLama", "lat": 42.2796, "lng": -83.7488, "aliases": ["blue llama"]},
    {"name": "Michigan Theater", "lat": 42.2790, "lng": -83.7415, "aliases": ["michigan theater", "michigan theatre"]},
    {"name": "The Blind Pig", "lat": 42.2802, "lng": -83.7498, "aliases": ["blind pig"]}
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
    {"key": "e-lecture", "name": "Public Lecture: Great Lakes Futures", "desc": "SEAS faculty on climate and water in Michigan.", "venue": "v-hill", "org": "o-ums", "cats": ["academic", "outdoor"], "day": 3, "time": "Thu 4:00 PM", "price": 0.0, "src": "src-um", "related": []},
    {"key": "e-blindpig-indie", "name": "Indie Night at The Blind Pig", "desc": "Local bands and touring acts in the First Street basement.", "venue": "v-blindpig", "org": "o-blindpig", "cats": ["music", "nightlife"], "day": 4, "time": "Fri 9:00 PM", "price": 12.0, "src": "src-eb", "related": []},
    {"key": "e-clubabove", "name": "Club Above Late Set", "desc": "House and disco upstairs above the Pig — doors at 10.", "venue": "v-clubabove", "org": "o-clubabove", "cats": ["nightlife", "music"], "day": 5, "time": "Sat 10:00 PM", "price": 10.0, "src": "src-eb", "related": ["e-blindpig-indie"]},
    {"key": "e-mich-comedy", "name": "Michigan Theater Comedy Night", "desc": "Regional comics in the historic downtown theater.", "venue": "v-michtheater", "org": "o-michtheater", "cats": ["comedy", "arts"], "day": 5, "time": "Sat 8:00 PM", "price": 18.0, "src": "src-eb", "related": []}
];

glob ALERTS: list[dict] = [
    {"key": "a-plymouth", "name": "Plymouth Rd lane closure", "desc": "Eastbound right lane closed for water main work between Huron Pkwy and Nixon.", "alert_type": "closure", "when": "Wed to Fri, 7 AM to 5 PM", "day": 2, "src": "src-road", "org": "o-city", "cats": ["community"], "places": ["pl-plymouth", "pl-north"], "lat": 42.301, "lng": -83.71, "path": [[42.29575, -83.72243], [42.29578, -83.72173], [42.29576, -83.72166], [42.29563, -83.72165], [42.29528, -83.72163], [42.29485, -83.72162], [42.2948, -83.72164], [42.29459, -83.72191], [42.29445, -83.72189], [42.29438, -83.7218], [42.29427, -83.72156], [42.29415, -83.72098], [42.29417, -83.72064], [42.29432, -83.72026], [42.29449, -83.72009], [42.30051, -83.71147], [42.30055, -83.71147], [42.30061, -83.71153], [42.30061, -83.71163], [42.30057, -83.7117], [42.30049, -83.71169], [42.3004, -83.71174], [42.30024, -83.71204], [42.30021, -83.71242], [42.30034, -83.71274], [42.30037, -83.71359], [42.30044, -83.71389], [42.3005, -83.714], [42.30063, -83.71425], [42.30126, -83.71351], [42.30159, -83.71309], [42.30201, -83.71234], [42.30214, -83.71197], [42.30227, -83.71154], [42.30239, -83.71096], [42.30241, -83.71071], [42.30246, -83.71001], [42.30248, -83.709], [42.30252, -83.70726], [42.30254, -83.70637], [42.30281, -83.70497], [42.30279, -83.70489], [42.3028, -83.70469], [42.30283, -83.70464], [42.30295, -83.70461]]},
    {"key": "a-main-work", "name": "Main St road work", "desc": "Main St narrowed to one lane between Washington and William; loading zones moved.", "alert_type": "closure", "when": "Mon to Thu, 6 AM to 3 PM", "day": 0, "src": "src-road", "org": "o-city", "cats": ["community"], "places": ["pl-main"], "lat": 42.2795, "lng": -83.7483, "path": [[42.2814, -83.74851], [42.28109, -83.74852], [42.2808, -83.74854], [42.2805, -83.74856], [42.28049, -83.74856], [42.28012, -83.74858], [42.27992, -83.74859], [42.27967, -83.7486], [42.27958, -83.74861], [42.27951, -83.74861], [42.27926, -83.74862], [42.27893, -83.74863], [42.27859, -83.74865], [42.2785, -83.74865], [42.27832, -83.74866], [42.27794, -83.74868], [42.27772, -83.74869], [42.2776, -83.7487], [42.27751, -83.74871]]},
    {"key": "a-route4", "name": "TheRide Route 4 detour", "desc": "Route 4 detours off Washtenaw Ave via Packard for utility work.", "alert_type": "detour", "when": "Thu all day", "day": 3, "src": "src-ride", "org": "o-ride", "cats": ["community"], "places": ["pl-washtenaw", "pl-central"], "lat": 42.2735, "lng": -83.729, "path": [[42.27692, -83.7354], [42.27727, -83.73465], [42.27732, -83.73464], [42.27745, -83.73443], [42.27732, -83.73421], [42.2769, -83.73372], [42.2767, -83.73346], [42.27659, -83.73332], [42.27642, -83.7332], [42.27629, -83.73307], [42.27593, -83.73319], [42.27569, -83.73318], [42.27554, -83.73316], [42.2755, -83.7331], [42.2753, -83.7331], [42.27511, -83.73314], [42.27505, -83.73136], [42.27457, -83.73076], [42.27423, -83.73097], [42.27389, -83.73113], [42.27374, -83.73143], [42.27343, -83.73146], [42.27334, -83.73141], [42.27332, -83.73084], [42.27332, -83.73058], [42.27326, -83.7305], [42.27312, -83.73043], [42.27266, -83.73042], [42.27248, -83.73039], [42.27236, -83.72998], [42.2724, -83.72878], [42.27243, -83.72826], [42.27245, -83.72808], [42.27056, -83.72721], [42.27058, -83.72584], [42.2706, -83.72572], [42.27014, -83.72503], [42.27013, -83.72426], [42.27002, -83.72262], [42.26952, -83.72261], [42.2681, -83.71967], [42.26747, -83.7171], [42.26698, -83.71615], [42.26675, -83.71589], [42.2672, -83.71517]]},
    {"key": "a-state-sidewalk", "name": "State St sidewalk closure", "desc": "West sidewalk closed near the Union; use the east side crossing.", "alert_type": "closure", "when": "All week", "day": 0, "src": "src-road", "org": "o-city", "cats": ["community"], "places": ["pl-state", "pl-central"], "lat": 42.2752, "lng": -83.7412, "path": [[42.27681, -83.74074], [42.27677, -83.74074], [42.27667, -83.74074], [42.27662, -83.74074], [42.27613, -83.74072], [42.2758, -83.74072], [42.27566, -83.74071], [42.2754, -83.74071], [42.27521, -83.7407], [42.27494, -83.7407], [42.2748, -83.74069], [42.27478, -83.74069], [42.27447, -83.74069], [42.2742, -83.74068], [42.2742, -83.74119], [42.2739, -83.74124]]},
    {"key": "a-bus-north", "name": "Bursley-Baits bus reroute", "desc": "U-M buses skip the Pierpont stop during event setup.", "alert_type": "detour", "when": "Sat afternoon", "day": 5, "src": "src-ride", "org": "o-ride", "cats": ["community"], "places": ["pl-north"], "lat": 42.2915, "lng": -83.718, "path": [[42.29338, -83.72062], [42.2934, -83.72065], [42.29344, -83.72077], [42.29346, -83.72086], [42.29346, -83.72096], [42.29345, -83.72105], [42.29342, -83.72118], [42.29339, -83.72125], [42.29337, -83.7213], [42.29328, -83.72137], [42.29324, -83.72139], [42.29317, -83.72139], [42.2931, -83.72139], [42.29295, -83.72137], [42.29281, -83.72133], [42.29283, -83.72126], [42.29287, -83.72111], [42.2929, -83.72095], [42.29292, -83.72069], [42.29291, -83.72063], [42.2929, -83.72049], [42.29284, -83.72016], [42.29283, -83.71954], [42.29283, -83.71919], [42.29283, -83.71877], [42.29148, -83.71854], [42.29129, -83.71849], [42.2905, -83.71848], [42.29038, -83.71847], [42.29021, -83.71835], [42.29022, -83.7183], [42.29023, -83.71823], [42.29025, -83.71794], [42.29025, -83.71755], [42.29025, -83.71711], [42.29024, -83.717], [42.29024, -83.71585], [42.29024, -83.71514], [42.29024, -83.71503], [42.29024, -83.7145], [42.29025, -83.7141], [42.29028, -83.71319], [42.29028, -83.71316], [42.28927, -83.71301], [42.28927, -83.71216]]}
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
