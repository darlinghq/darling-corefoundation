#import <Foundation/Foundation.h>
#include <stdio.h>

static const NSTimeInterval kSecondsPerDay = 86400;
// 2021-01-01 00:00:00 UTC, a Friday.
static const NSTimeInterval kStart = 1609459200;

static int failures;

static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static void check_difference(NSCalendar *calendar, NSCalendarUnit weekUnit, int days, NSInteger expectedWeeks, NSInteger expectedDays)
{
    NSDate *from = [NSDate dateWithTimeIntervalSince1970:kStart];
    NSDate *to = [NSDate dateWithTimeIntervalSince1970:kStart + days * kSecondsPerDay];
    NSDateComponents *c = [calendar components:weekUnit | NSCalendarUnitDay fromDate:from toDate:to options:0];
    NSInteger weeks = weekUnit == NSCalendarUnitWeekOfMonth ? [c weekOfMonth] : [c weekOfYear];
    const char *name = weekUnit == NSCalendarUnitWeekOfMonth ? "weekOfMonth" : "weekOfYear";
    char label[128];
    snprintf(label, sizeof(label), "%s+day over %d days: got %ld weeks %ld days, want %ld weeks %ld days",
             name, days, (long)weeks, (long)[c day], (long)expectedWeeks, (long)expectedDays);
    check_result(label, c != nil && weeks == expectedWeeks && [c day] == expectedDays);
}

int main(void)
{
    @autoreleasepool
    {
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:(NSString *)kCFGregorianCalendar];
        [calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        [calendar setFirstWeekday:1];
        [calendar setMinimumDaysInFirstWeek:1];

        // #858: macOS reports 1 week 3 days for 10 days, Darling reported 0 weeks 10 days.
        check_difference(calendar, NSCalendarUnitWeekOfMonth, 10, 1, 3);
        check_difference(calendar, NSCalendarUnitWeekOfYear, 10, 1, 3);
        check_difference(calendar, NSCalendarUnitWeekOfMonth, 24, 3, 3);
        check_difference(calendar, NSCalendarUnitWeekOfYear, 24, 3, 3);
        check_difference(calendar, NSCalendarUnitWeekOfYear, 424, 60, 4);

        // Decomposition reads the same reordered vector; 2021-02-10 is a Wednesday.
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:kStart + 40 * kSecondsPerDay];
        NSDateComponents *c = [calendar components:NSCalendarUnitYearForWeekOfYear | NSCalendarUnitWeekOfYear |
                                                   NSCalendarUnitWeekOfMonth | NSCalendarUnitDay
                                          fromDate:date];
        check_result("decompose 2021-02-10 week fields",
                     [c yearForWeekOfYear] == 2021 && [c weekOfYear] == 7 && [c weekOfMonth] == 2 && [c day] == 10);
    }
    return failures != 0;
}
