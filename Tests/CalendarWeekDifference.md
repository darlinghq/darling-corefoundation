# NSCalendar week differences (#858)

Build CalendarWeekDifference.m against Foundation/CoreFoundation and run it under Darling. It uses a UTC Gregorian calendar with first weekday 1 and minimum days in first week 1, and asks `components:fromDate:toDate:options:` for week-of-month or week-of-year plus day over 10, 24 and 424 days from 2021-01-01. It also decomposes 2021-02-10 into its week fields to check that the reordered component vector is read back in the same order.

Installed baseline: five failures, each reporting 0 weeks and all elapsed days (10, 24, 424), because the day component was computed before the week component. Candidate: zero failures.
