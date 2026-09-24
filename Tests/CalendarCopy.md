# NSCalendar copy

Build CalendarCopy.m against Foundation/CoreFoundation (ARC or MRC) and run it under Darling. It configures a Gregorian calendar (de_DE locale, America/New_York time zone, first weekday 4, minimum days in first week 3, all different from de_DE's defaults), copies it and checks that the copy keeps every setting, computes the same hour and is independent of the original.

Installed baseline: five failures (locale, time zone, first weekday, minimum days, hour); candidate: zero failures.
