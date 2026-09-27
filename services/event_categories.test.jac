"""Tests for live-listing categories (services/event_parse.py guess_cats)."""


test "whole words only: no tags from pieces of other words" {
    assert guess_cats("Wacky Flower and Shroom Tour of Ann Arbor", "", "Eventbrite Ann Arbor") == ["outdoor"];
    assert "music" not in guess_cats("Magic: The Gathering (MTG): Sylvan Factory", "", "Ann Arbor Observer");
    assert "arts" not in guess_cats("Lucky Strike Ann Arbor Lucky Launch Party!", "", "Eventbrite Ann Arbor");
    assert "nightlife" not in guess_cats("Melges15 Regatta: U-M Sailing Club", "", "Ann Arbor Observer");
    assert "civic" not in guess_cats("University of Michigan Alumnae Council Fall Hybrid Event", "", "Eventbrite Ann Arbor");
}

test "museum and campus tours are not concerts" {
    assert guess_cats("Museum Highlight Tours: U-M Museum of Natural History", "", "Ann Arbor Observer") == ["arts"];
    assert guess_cats("Michigan Engineering North Campus Tour", "", "Eventbrite Ann Arbor") == ["academic"];
}

test "event part of Observer titles decides, host adds performers and places" {
    assert split_host_title("Chime Concert: Kerrytown Market & Shops") == ("Chime Concert", "Kerrytown Market & Shops");
    assert guess_cats("Chime Concert: Kerrytown Market & Shops", "", "Ann Arbor Observer") == ["music"];
    assert "music" in guess_cats("Market Performances: Ann Arbor Symphony Orchestra", "", "Ann Arbor Observer");
    assert guess_cats("“Bastard”: Purple Rose Theatre Company", "", "Ann Arbor Observer") == ["arts"];
}

test "venue sources: The Ark is music, UMS is performing arts" {
    assert guess_cats("Wheelchair Sports Camp & Gaelynn Lea", "", "The Ark") == ["music"];
    assert guess_cats("Off Book – Tour de Force", "An evening of improv.", "The Ark") == ["music", "comedy"];
    assert guess_cats("Anthony McGill, clarinet", "", "University Musical Society") == ["music"];
    assert guess_cats("Indigo Park Tour", "", "University Musical Society") == ["arts"];
}

test "Eventbrite bucket is only a fallback" {
    assert guess_cats("Mystery Night Thing", "", "Eventbrite Ann Arbor", ["nightlife"]) == ["nightlife"];
    assert guess_cats("Gandy Dancer Caymus Vineyards Wine Dinner", "", "Eventbrite Ann Arbor", ["music"]) == ["food"];
}

test "duplicate keys: same title and time across sources match" {
    assert norm_title("“The Tallest Man on Earth”") == norm_title("Tallest Man On Earth");
    assert norm_title("The Ark’s Open Stage") == "ark s open stage";
    assert time_slot("2026-10-02 20:00:00") == time_slot("2026-10-02T20:00");
    assert time_slot("2026-10-02 20:00") != time_slot("2026-10-03 20:00");
    assert time_slot("2026-10-02") == "2026-10-02";
    assert time_slot("Fri 8:00 PM") == "fri 8:00 pm";
}
