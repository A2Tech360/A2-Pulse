"""Categories for live listings. The rules live in services/event_parse.py
(guess_cats); this module gives them a Jac home and a test annex that doesn't
pull in the whole Pulse graph."""

import from services.event_parse { guess_cats, split_host_title, norm_title, time_slot }
