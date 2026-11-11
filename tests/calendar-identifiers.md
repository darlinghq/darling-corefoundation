# Calendar identifiers

`calendar-identifiers.m` creates an `NSCalendar` from each of the 16 calendar
identifiers supported by Apple's Foundation / CoreFoundation, asserts that the
calendar is non-nil and round-trips its identifier. Build it as an Objective-C
executable linked to Foundation and CoreFoundation and run with the candidate
CoreFoundation library. Success prints:

```
PASS: all sixteen calendar identifiers create a calendar and round-trip
```

Addresses VibeDarling/darling#1139. Previous versions of CoreFoundation only
supported seven identifiers in `CFCalendarCreateWithIdentifier()`. The remaining
nine identifiers (Chinese, Coptic, EthiopicAmeteMihret, EthiopicAmeteAlem,
Indian, Persian, RepublicOfChina, IslamicTabular, and IslamicUmmAlQura) returned
nil due to a legacy OS X 10.5 check.
