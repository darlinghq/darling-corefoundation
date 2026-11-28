// NSTimeZone abbreviationForDate: must return the abbreviation in effect on that date.
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

static void check_result(const char *label, int ok)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", label);
	failures += !ok;
}

static int is_abbreviation(NSTimeZone *timeZone, NSTimeInterval since1970, NSString *expected)
{
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:since1970];
	NSString *abbreviation = [timeZone abbreviationForDate:date];
	return [abbreviation isEqualToString:expected];
}

int main(void)
{
	@autoreleasepool {
		NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
		check_result("timezone: America/New_York available", timeZone != nil);
		if (timeZone) {
			// 2024-01-15 12:00 UTC and 2024-07-15 12:00 UTC
			check_result("timezone: winter abbreviation is EST", is_abbreviation(timeZone, 1705320000.0, @"EST"));
			check_result("timezone: summer abbreviation is EDT", is_abbreviation(timeZone, 1721025600.0, @"EDT"));
			check_result("timezone: abbreviation uses the date", [[timeZone abbreviation] isEqualToString:[timeZone abbreviationForDate:[NSDate date]]]);
		}
	}
	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
