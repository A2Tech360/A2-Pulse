"""Unit tests for speakable(): edge cases plus every road name in the seed data."""

import re;
import from datetime { date }
import from services.seed_data { PLACES, VENUES, ORGANIZERS, EVENTS, ALERTS, CIVIC, PERSONAS, SOURCES }

# Saturday, September 26th 2026: the demo "today", so month/day dates resolve deterministically.
glob TODAY: date = date(2026, 9, 26);

# Anything still matching this after speakable() is an abbreviation or symbol TTS would stumble on.
glob FORBIDDEN: str = r"\b(Rd|St|Ave|Av|Blvd|Dr|Hwy|Pkwy|Ln|Ct|Mon|Tue|Tues|Wed|Thu|Thur|Thurs|Fri|Sat|Sun|Jan|Feb|Sep|Sept|Oct|Nov|Dec|AM|PM|U-M|AADL|UMS|DDA|SEAS)\b|\b[NSEW]\b|[&@$%()\[\]{}*#_`<>|]|https?:|www\.";

def sp(text: str) -> str {
    return speakable(text, TODAY);
}

def assert_clean(text: str) {
    out = sp(text);
    found = re.findall(FORBIDDEN, out);
    assert len(found) == 0, f"{text!r} -> {out!r} still has {found!r}";
}

# ---------------------------------------------------------------- road names in the seed data
test "seed place names" {
    assert sp("Plymouth Rd corridor") == "Plymouth Road corridor";
    assert sp("Washtenaw Ave") == "Washtenaw Avenue";
    assert sp("State Street") == "State Street";
    assert sp("Main Street") == "Main Street";
}

test "seed venue addresses" {
    assert sp("316 S Main St") == "316 South Main Street";
    assert sp("825 N University Ave") == "825 North University Avenue";
    assert sp("530 S State St") == "530 South State Street";
    assert sp("314 S Main St") == "314 South Main Street";
    assert sp("343 S Fifth Ave") == "343 South Fifth Avenue";
    assert sp("2101 Bonisteel Blvd") == "2101 Bonisteel Boulevard";
    assert sp("3000 Fuller Rd") == "3000 Fuller Road";
    assert sp("315 Detroit St") == "315 Detroit Street";
    assert sp("301 E Huron St") == "301 East Huron Street";
}

test "seed alert and civic names" {
    assert sp("Plymouth Rd lane closure") == "Plymouth Road lane closure";
    assert sp("Main St road work") == "Main Street road work";
    assert sp("State St sidewalk closure") == "State Street sidewalk closure";
    assert sp("Plymouth Rd protected bike lane plan") == "Plymouth Road protected bike lane plan";
    assert sp("Eastbound right lane closed for water main work between Huron Pkwy and Nixon.") == "Eastbound right lane closed for water main work between Huron Parkway and Nixon.";
    assert sp("Main St narrowed to one lane between Washington and William; loading zones moved.") == "Main Street narrowed to one lane between Washington and William; loading zones moved.";
    assert sp("Route 4 detours off Washtenaw Ave via Packard for utility work.") == "Route 4 detours off Washtenaw Avenue via Packard for utility work.";
    assert sp("Leave 10 minutes early or take the Fuller Rd path instead.") == "Leave 10 minutes early or take the Fuller Road path instead.";
}

test "seed organizer and persona names" {
    assert sp("U-M Jazz Collective") == "University of Michigan Jazz Collective";
    assert sp("U-M Career Center") == "University of Michigan Career Center";
    assert sp("Maya, Main St shop owner") == "Maya, Main Street shop owner";
    assert sp("Jordan, U-M junior") == "Jordan, University of Michigan junior";
    assert sp("U-M buses skip the Pierpont stop during event setup.") == "University of Michigan buses skip the Pierpont stop during event setup.";
    assert sp("Tech & Startups Career Mixer") == "Tech and Startups Career Mixer";
    assert sp("North Campus Pizza & Game Night") == "North Campus Pizza and Game Night";
    assert sp("Happening @ Michigan") == "Happening at Michigan";
}

test "seed time strings" {
    assert sp("Fri 8:00 PM") == "Friday at 8 p.m.";
    assert sp("Sat 7:30 PM") == "Saturday at 7:30 p.m.";
    assert sp("Sun 11:00 AM") == "Sunday at 11 a.m.";
    assert sp("Wed to Fri, 7 AM to 5 PM") == "Wednesday to Friday, 7 a.m. to 5 p.m.";
    assert sp("Mon to Thu, 6 AM to 3 PM") == "Monday to Thursday, 6 a.m. to 3 p.m.";
    assert sp("Thu all day") == "Thursday all day";
    assert sp("Mon 7:00 PM, public comment sign-up by Mon noon") == "Monday at 7 p.m., public comment sign-up by Monday at noon";
    assert sp("Comment deadline Tue 5:00 PM") == "Comment deadline Tuesday at 5 p.m.";
    assert sp("Wed 6:30 PM hearing") == "Wednesday at 6:30 p.m. hearing";
    assert sp("Sat afternoon") == "Saturday afternoon";
}

test "every seed string comes out clean" {
    strings: list[str] = [];
    for p in PLACES { strings.append(str(p["name"])); }
    for v in VENUES { strings.extend([str(v["name"]), str(v["address"])]); }
    for o in ORGANIZERS { strings.append(str(o["name"])); }
    for s in SOURCES { strings.append(str(s["name"])); }
    for e in EVENTS { strings.extend([str(e["name"]), str(e["desc"]), str(e["time"])]); }
    for a in ALERTS { strings.extend([str(a["name"]), str(a["desc"]), str(a["when"])]); }
    for c in CIVIC { strings.extend([str(c["name"]), str(c["desc"]), str(c["when"])]); }
    for pr in PERSONAS { strings.append(str(pr["name"])); }
    for s in strings {
        assert_clean(s);
    }
    assert len(strings) > 80;
}

# ---------------------------------------------------------------- ambiguous St. / Dr.
test "St before a name is Saint" {
    assert sp("St. Joseph Mercy Hospital") == "Saint Joseph Mercy Hospital";
    assert sp("Blood drive at St. Joseph Mercy on Sat") == "Blood drive at Saint Joseph Mercy on Saturday";
    assert sp("St Patrick's Day parade on Main St.") == "Saint Patrick's Day parade on Main Street.";
    assert sp("Visit St. Francis this week") == "Visit Saint Francis this week";
}

test "St after a street name is Street" {
    assert sp("Parking on State St. Then walk north.") == "Parking on State Street. Then walk north.";
    assert sp("Main St. is closed") == "Main Street is closed";
    assert sp("5th St and Liberty") == "5th Street and Liberty";
    assert sp("Detroit St, then left") == "Detroit Street, then left";
}

test "Dr before a person is Doctor" {
    assert sp("Dr. Lee speaks at Hill") == "Doctor Lee speaks at Hill";
    assert sp("Meet Dr. Smith at the Union") == "Meet Doctor Smith at the Union";
    assert sp("A talk with Dr. Rivera") == "A talk with Doctor Rivera";
}

test "Dr after a street name is Drive" {
    assert sp("Detour via Hubbard Dr.") == "Detour via Hubbard Drive.";
    assert sp("2200 Hubbard Dr") == "2200 Hubbard Drive";
    assert sp("Take Bonisteel Blvd to Murfin Dr, then park") == "Take Bonisteel Boulevard to Murfin Drive, then park";
}

# ---------------------------------------------------------------- symbols, formatting, dates
test "symbols become words" {
    assert sp("RSVP and grab a ticket ($15) for Sat 7:30 PM.") == "RSVP and grab a ticket, 15 dollars, for Saturday at 7:30 p.m.";
    assert sp("Tickets $12.50 & up") == "Tickets 12 dollars and 50 cents and up";
    assert sp("50% off") == "50 percent off";
    assert sp("within 1.0 mi of campus") == "within 1 mile of campus";
    assert sp("give yourself 10 min") == "give yourself 10 minutes";
}

test "no urls emoji markdown or parentheses" {
    out = sp("**Heads up** 🚧 Plymouth Rd (eastbound) is closed. Details: https://www.a2gov.org/road-closures");
    assert out == "Heads up Plymouth Road, eastbound, is closed. Details", out;
    out = sp("## Your week\n- Jazz night 🎷\n- [Council vote](https://a2gov.legistar.com) on housing");
    assert out == "Your week. Jazz night. Council vote on housing", out;
    assert_clean("Check a2gov.org or www.theride.org for updates (see map) #1 pick");
}

test "times read naturally" {
    assert sp("starts at 7pm") == "starts at 7 p.m.";
    assert sp("doors 6:45 PM") == "doors 6:45 p.m.";
    assert sp("7-9 PM") == "7 to 9 p.m.";
    assert sp("lunch at 12 PM") == "lunch at noon";
    assert sp("until 12:00 AM") == "until midnight";
    assert sp("Mon-Fri") == "Monday to Friday";
}

test "dates read as weekday month ordinal" {
    assert sp("Tue, Sep 29") == "Tuesday, September 29th";
    assert sp("on 2026-09-29") == "on Tuesday, September 29th";
    assert sp("due 9/29") == "due Tuesday, September 29th";
    assert sp("October 1") == "Thursday, October 1st";
    assert sp("Nov 3, 2027") == "Wednesday, November 3rd, 2027";
    assert sp("Dec 22") == "Tuesday, December 22nd";
    assert sp("Sep 11") == "Friday, September 11th";
}

test "speakable is idempotent" {
    for s in [
        "RSVP and grab a ticket ($15) for Sat 7:30 PM.",
        "301 E Huron St, Dr. Lee, St. Joseph, Tue, Sep 29 at 7:00 PM",
        "Mon 7:00 PM, public comment sign-up by Mon noon"
    ] {
        once = sp(s);
        assert sp(once) == once, once;
    }
}

test "empty text stays empty" {
    assert sp("") == "";
    assert sp("   ") == "";
}

test "brand names read as words" {
    assert sp("Check TheRide trip planner") == "Check The Ride trip planner";
    assert sp("Jazz Brunch at Blue LLama") == "Jazz Brunch at Blue Llama";
}
