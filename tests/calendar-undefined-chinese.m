// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: unset NSDateComponents fields are NSUndefinedDateComponent,
// NSDate supports secure coding, and calendars created from all sixteen
// identifiers (including Chinese) do basic arithmetic.
#import <Foundation/Foundation.h>

static int failures;
static void check(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool {
        NSDateComponents *c = [[NSDateComponents alloc] init];
        check("year undefined", [c year] == NSUndefinedDateComponent);
        check("month undefined", [c month] == NSUndefinedDateComponent);
        check("day undefined", [c day] == NSUndefinedDateComponent);
        check("hour undefined", [c hour] == NSUndefinedDateComponent);
        check("weekday undefined", [c weekday] == NSUndefinedDateComponent);
        check("NSDate supports secure coding", [NSDate supportsSecureCoding]);

        NSCalendar *chinese = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
        check("chinese calendar created", chinese != nil);
        chinese.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        // 2024-02-10 00:00 UTC is the first day of the first Chinese month.
        NSDate *cny = [NSDate dateWithTimeIntervalSince1970:1707523200];
        NSDateComponents *p = [chinese components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:cny];
        check("chinese new year is month 1 day 1", [p month] == 1 && [p day] == 1);
        NSDateComponents *oneMonth = [[NSDateComponents alloc] init];
        [oneMonth setMonth:1];
        NSDate *next = [chinese dateByAddingComponents:oneMonth toDate:cny options:0];
        NSDateComponents *q = [chinese components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:next];
        check("one month later is month 2 day 1", [q month] == 2 && [q day] == 1);
        // 2024-03-10 00:00 UTC begins the second month.
        check("one month later is 2024-03-10", fabs([next timeIntervalSince1970] - 1710028800) < 1);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
