#import <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void check(const char *label, CFISO8601DateFormatOptions options, CFTimeZoneRef zone, CFAbsoluteTime time, const char *expected)
{
    CFDateFormatterRef formatter = CFDateFormatterCreateISO8601Formatter(kCFAllocatorDefault, options);
    CFDateFormatterSetProperty(formatter, kCFDateFormatterTimeZone, zone);
    CFStringRef string = CFDateFormatterCreateStringWithAbsoluteTime(kCFAllocatorDefault, formatter, time);
    char buffer[64] = "";
    CFStringGetCString(string, buffer, sizeof(buffer), kCFStringEncodingUTF8);
    CFAbsoluteTime parsed = 0;
    Boolean parses = CFDateFormatterGetAbsoluteTimeFromString(formatter, string, NULL, &parsed);
    int ok = strcmp(buffer, expected) == 0;
    printf("%s %s: %s\n", ok ? "PASS" : "FAIL", label, buffer);
    failures += !ok;
    // Only formats with a calendar date and a time identify the instant.
    if ((options & kCFISO8601DateFormatWithTime) && (options & kCFISO8601DateFormatWithMonth)) {
        ok = parses && parsed == time;
        printf("%s %s parses back\n", ok ? "PASS" : "FAIL", label);
        failures += !ok;
    }
    CFRelease(string);
    CFRelease(formatter);
}

int main(void)
{
    // 2021-07-15T12:00:00Z: a Thursday in ISO week 28, day 196 of the year.
    CFAbsoluteTime july = 1626350400 - kCFAbsoluteTimeIntervalSince1970;
    // 2021-01-01T00:00:00Z: a Friday in ISO week 53 of 2020.
    CFAbsoluteTime newYear = 1609459200 - kCFAbsoluteTimeIntervalSince1970;
    CFTimeZoneRef gmt = CFTimeZoneCreateWithTimeIntervalFromGMT(kCFAllocatorDefault, 0);
    CFTimeZoneRef plusTwo = CFTimeZoneCreateWithTimeIntervalFromGMT(kCFAllocatorDefault, 7200);

    check("internet date time GMT", kCFISO8601DateFormatWithInternetDateTime, gmt, july, "2021-07-15T12:00:00Z");
    check("internet date time +02:00", kCFISO8601DateFormatWithInternetDateTime, plusTwo, july, "2021-07-15T14:00:00+02:00");
    check("fractional seconds", kCFISO8601DateFormatWithInternetDateTime | kCFISO8601DateFormatWithFractionalSeconds, gmt, july + 0.25, "2021-07-15T12:00:00.250Z");
    check("basic format", kCFISO8601DateFormatWithYear | kCFISO8601DateFormatWithMonth | kCFISO8601DateFormatWithDay | kCFISO8601DateFormatWithTime | kCFISO8601DateFormatWithTimeZone, plusTwo, july, "20210715T140000+0200");
    check("week date", kCFISO8601DateFormatWithYear | kCFISO8601DateFormatWithWeekOfYear | kCFISO8601DateFormatWithDay | kCFISO8601DateFormatWithDashSeparatorInDate, gmt, july, "2021-W28-04");
    check("week-year boundary", kCFISO8601DateFormatWithYear | kCFISO8601DateFormatWithWeekOfYear | kCFISO8601DateFormatWithDay | kCFISO8601DateFormatWithDashSeparatorInDate, gmt, newYear, "2020-W53-05");
    check("ordinal date", kCFISO8601DateFormatWithYear | kCFISO8601DateFormatWithDay | kCFISO8601DateFormatWithDashSeparatorInDate, gmt, july, "2021-196");
    check("year only", kCFISO8601DateFormatWithYear, gmt, july, "2021");
    check("full time", kCFISO8601DateFormatWithFullTime, gmt, july, "12:00:00Z");

    CFRelease(gmt);
    CFRelease(plusTwo);
    printf("%d failures\n", failures);
    return failures != 0;
}
