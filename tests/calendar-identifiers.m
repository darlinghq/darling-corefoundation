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
    checkIdentifier(@"Chinese", NSCalendarIdentifierChinese);
    checkIdentifier(@"Coptic", NSCalendarIdentifierCoptic);
    checkIdentifier(@"EthiopicAmeteMihret", NSCalendarIdentifierEthiopicAmeteMihret);
    checkIdentifier(@"EthiopicAmeteAlem", NSCalendarIdentifierEthiopicAmeteAlem);
    checkIdentifier(@"Indian", NSCalendarIdentifierIndian);
    checkIdentifier(@"Persian", NSCalendarIdentifierPersian);
    checkIdentifier(@"RepublicOfChina", NSCalendarIdentifierRepublicOfChina);
    checkIdentifier(@"IslamicTabular", NSCalendarIdentifierIslamicTabular);
    checkIdentifier(@"IslamicUmmAlQura", NSCalendarIdentifierIslamicUmmAlQura);
    checkIdentifier(@"ISO8601", NSCalendarIdentifierISO8601);
    [pool drain];
    puts("PASS: all sixteen calendar identifiers create a calendar and round-trip");
    return 0;
}
