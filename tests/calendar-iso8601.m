// Run linked against the candidate Foundation/CoreFoundation runtime.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>

extern CFStringRef const kCFCalendarIdentifierISO8601;

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    assert([(NSString *)kCFCalendarIdentifierISO8601 isEqual:@"iso8601"]);
    NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier:@"iso8601"] autorelease];
    assert(calendar != nil);
    assert([[calendar calendarIdentifier] isEqual:@"iso8601"]);
    assert([calendar firstWeekday] == 2);
    assert([calendar minimumDaysInFirstWeek] == 4);

    // 2021-01-03 is a Sunday that ISO 8601 counts in week 53 of 2020.
    CFCalendarRef cf = (CFCalendarRef)calendar;
    CFTimeZoneRef utc = CFTimeZoneCreateWithTimeIntervalFromGMT(NULL, 0);
    CFCalendarSetTimeZone(cf, utc);
    CFAbsoluteTime at = 0;
    assert(CFCalendarComposeAbsoluteTime(cf, &at, "yMd", 2021, 1, 3));
    int week = 0;
    assert(CFCalendarDecomposeAbsoluteTime(cf, at, "w", &week));
    assert(week == 53);
    CFRelease(utc);
    [pool drain];
    puts("PASS: iso8601 calendar identifier, ISO week defaults and week-of-year");
    return 0;
}
