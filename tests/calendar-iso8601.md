# ISO 8601 calendar

`calendar-iso8601.m` creates an `NSCalendar` from the identifier `iso8601`,
checks that it reports that identifier, uses Monday as first weekday with a
minimum of 4 days in the first week, and computes the ISO week of 2021-01-03
(week 53). Build it as an Objective-C executable linked to Foundation and run
with the candidate CoreFoundation library. Success prints:

```
PASS: iso8601 calendar identifier, ISO week defaults and week-of-year
```

`kCFCalendarIdentifierISO8601` was an empty string and
`CFCalendarCreateWithIdentifier` rejected it (VibeDarling/darling#981). The
identifier string is `iso8601` as in Apple's `NSCalendar.Identifier.iso8601`
documentation, and the ISO week rules are those of ISO 8601 (Monday start,
first week contains at least four days).
