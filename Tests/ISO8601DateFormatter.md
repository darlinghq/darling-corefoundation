# ISO 8601 date formatter

Build ISO8601DateFormatter.m against CoreFoundation and run it under Darling. It formats two fixed dates with `CFDateFormatterCreateISO8601Formatter` for internet date-time (GMT and +02:00), fractional seconds, basic format, week dates (including the 2020-W53 boundary), ordinal dates, year only and time only, and parses each format with a calendar date and a time back to the same instant.

Before this change CoreFoundation does not export the function, so the test does not link. With it: zero failures.
