# NSCalendar gregorianStartDate

`calendar-gregorian-start-date.m` sets a Gregorian start date on an `NSCalendar`
and reads it back. Build it as an Objective-C executable linked to Foundation
and run with the candidate CoreFoundation library. Success prints:

```
PASS: gregorianStartDate round-trips the date passed to the setter
```

`-setGregorianStartDate:` passed the calendar itself to
`CFCalendarSetGregorianStartDate` instead of the `date` argument, so the setter
never applied the date (VibeDarling/darling#987). Apple documents the property:
https://developer.apple.com/documentation/foundation/nscalendar/gregorianstartdate
