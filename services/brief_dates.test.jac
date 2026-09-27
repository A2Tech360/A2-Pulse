"""Brief week rule: weekends look ahead to next Monday, weekdays use this Monday."""

import from datetime { date, datetime }

test "weekend briefs are for the next Monday" {
    assert brief_monday(date(2026, 9, 26)) == date(2026, 9, 28);   # Saturday
    assert brief_monday(date(2026, 9, 27)) == date(2026, 9, 28);   # Sunday
}

test "weekday briefs are for this week's Monday" {
    assert brief_monday(date(2026, 9, 28)) == date(2026, 9, 28);   # Monday
    assert brief_monday(date(2026, 9, 30)) == date(2026, 9, 28);   # Wednesday
    assert brief_monday(date(2026, 10, 2)) == date(2026, 9, 28);   # Friday
    assert brief_monday(datetime(2026, 9, 26, 23, 59)) == date(2026, 9, 28);
}

test "day index counts from the brief Monday" {
    assert brief_day_index(date(2026, 9, 26)) == -2;
    assert brief_day_index(date(2026, 9, 27)) == -1;
    assert brief_day_index(date(2026, 9, 28)) == 0;
    assert brief_day_index(date(2026, 9, 30)) == 2;
}

test "week label" {
    assert brief_week_label(date(2026, 9, 26)) == "Monday, September 28, 2026";
}
