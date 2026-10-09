// Run linked against the candidate Foundation/CoreFoundation runtime.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

static void checkIdentifier(NSString *name, NSString *identifier) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:identifier];
    if (!calendar || ![[calendar calendarIdentifier] isEqual:identifier]) {
        fprintf(stderr, "FAIL %s (%s)\n", [name UTF8String], [identifier UTF8String]);
        exit(1);
    }
    [calendar release];
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    checkIdentifier(@"Gregorian", NSCalendarIdentifierGregorian);
    checkIdentifier(@"Buddhist", NSCalendarIdentifierBuddhist);
    checkIdentifier(@"Hebrew", NSCalendarIdentifierHebrew);
    checkIdentifier(@"Islamic", NSCalendarIdentifierIslamic);
    checkIdentifier(@"IslamicCivil", NSCalendarIdentifierIslamicCivil);
    checkIdentifier(@"Japanese", NSCalendarIdentifierJapanese);
    // The other identifiers still return nil: CFCalendarCreateWithIdentifier only creates these calendars
    // (and iso8601, covered by calendar-iso8601.m, not asserted here).
    [pool drain];
    puts("PASS: each of the six calendars CoreFoundation supports creates a calendar and round-trips");
    return 0;
}
