# NSTimeZone abbreviationForDate:

Build `nstimezone-abbreviation-for-date.m` against Foundation and run it under Darling.

`-abbreviationForDate:` is documented as returning the abbreviation for the given date. For `America/New_York`, that means EST in winter and EDT in summer. The fixed UTC timestamps in the test are 2024-01-15 12:00 and 2024-07-15 12:00, both well away from the DST transitions. The test also checks that the no-argument `-abbreviation` agrees with `-abbreviationForDate:` for the current date.

Installed baseline: the implementation looks up the zone's name in the abbreviation dictionary and returns the same abbreviation for every date (`EST` for New York in both winter and summer); candidate: zero failures.

## Provenance

Behavior is taken from the public Foundation API contract for `NSTimeZone` and the public IANA time zone rules for `America/New_York`. No restricted material was used.
