"""Tests for item dates and the brief week window."""

import from datetime { date }

# Brief for the week of Monday, September 28th 2026 (Monday to Sunday October 4th).
glob MONDAY: date = date(2026, 9, 28);

test "item_iso_date reads ISO, long and short dates" {
    assert item_iso_date("2026-10-10 19:30:00") == "2026-10-10";
    assert item_iso_date("2026-10-10 19:30") == "2026-10-10";
    assert item_iso_date("Saturday, October 10, 2026") == "2026-10-10";
    assert item_iso_date("Sat, Oct 10 · 7:30 PM", "", MONDAY) == "2026-10-10";
    assert item_iso_date("Fri 8:00 PM") == "";
    assert item_iso_date("", "2026-10-03") == "2026-10-03";
}

test "stored date wins over the when text" {
    assert item_iso_date("2026-11-07 20:00", "2026-10-02") == "2026-10-02";
}

test "live items inside the brief week stay" {
    assert in_brief_week("2026-09-28 19:00", "", True, MONDAY);
    assert in_brief_week("2026-10-03 20:00:00", "", True, MONDAY);
    assert in_brief_week("Sunday, October 4, 2026", "", True, MONDAY);
}

test "live items weeks or months away are dropped" {
    assert not in_brief_week("2026-10-16 20:00", "", True, MONDAY);
    assert not in_brief_week("2026-10-30 19:30", "", True, MONDAY);
    assert not in_brief_week("Saturday, November 7, 2026", "", True, MONDAY);
    assert not in_brief_week("2026-09-27 15:00", "", True, MONDAY);
    assert not in_brief_week("2026-10-05 09:00", "", True, MONDAY);
}

test "undated items: seed weekdays stay, live listings drop" {
    assert in_brief_week("Fri 8:00 PM", "", False, MONDAY);
    assert in_brief_week("Wed to Fri, 7 AM to 5 PM", "", False, MONDAY);
    assert not in_brief_week("Upcoming", "", True, MONDAY);
}

test "friendly_when: ISO date-times become card text" {
    assert friendly_when("2026-10-10 19:30") == "Sat, Oct 10 · 7:30 PM";
    assert friendly_when("2026-10-10 19:30:00") == "Sat, Oct 10 · 7:30 PM";
    assert friendly_when("2026-10-02T20:00:00-04:00") == "Fri, Oct 2 · 8:00 PM";
    assert friendly_when("2026-10-03 09:05") == "Sat, Oct 3 · 9:05 AM";
    assert friendly_when("2026-10-03 00:00") == "Sat, Oct 3 · 12:00 AM";
    assert friendly_when("2026-10-03 12:00") == "Sat, Oct 3 · 12:00 PM";
    assert friendly_when("2026-10-10") == "Sat, Oct 10";
}

test "friendly_when leaves human text alone" {
    assert friendly_when("Fri 8:00 PM") == "Fri 8:00 PM";
    assert friendly_when("Wed to Fri, 7 AM to 5 PM") == "Wed to Fri, 7 AM to 5 PM";
    assert friendly_when("Saturday, October 10, 2026") == "Saturday, October 10, 2026";
    assert friendly_when("") == "";
}
