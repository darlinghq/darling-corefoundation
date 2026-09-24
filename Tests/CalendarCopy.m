#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool
    {
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:(NSString *)kCFGregorianCalendar];
        [calendar setLocale:[NSLocale localeWithLocaleIdentifier:@"de_DE"]];
        [calendar setTimeZone:[NSTimeZone timeZoneWithName:@"America/New_York"]];
        [calendar setFirstWeekday:4];
        [calendar setMinimumDaysInFirstWeek:3];

        NSCalendar *copy = [calendar copy];
        check_result("copy is a calendar", copy != nil);
        check_result("identifier", [[copy calendarIdentifier] isEqualToString:[calendar calendarIdentifier]]);
        check_result("locale", [[[copy locale] localeIdentifier] isEqualToString:@"de_DE"]);
        check_result("time zone", [[[copy timeZone] name] isEqualToString:@"America/New_York"]);
        check_result("first weekday", [copy firstWeekday] == 4);
        check_result("minimum days in first week", [copy minimumDaysInFirstWeek] == 3);

        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
        check_result("same hour", [copy component:NSCalendarUnitHour fromDate:date] == [calendar component:NSCalendarUnitHour fromDate:date]);

        [copy setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        check_result("copy is independent", [[[calendar timeZone] name] isEqualToString:@"America/New_York"]);
    }
    return failures != 0;
}
