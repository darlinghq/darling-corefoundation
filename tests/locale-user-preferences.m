// Copyright (C) 2026 Lubos Dolezel
//
// The current locale follows the user's preferences, as on macOS: AppleICUForce24HourTime (the 24-hour clock),
// AppleFirstWeekday (a dictionary from calendar identifier to the first weekday), AppleMetricUnits and
// AppleMeasurementUnits, on top of AppleLocale. A change takes effect for the next use of the current locale. A
// locale made from an identifier is not affected. The keys are those the Language & Region pane of System
// Preferences writes (see the DateFormatter and locale documentation of NSLocale.current).
// Build: clang -framework Foundation locale-user-preferences.m
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void set_pref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef) key, (__bridge CFPropertyListRef) value, kCFPreferencesCurrentApplication);
}

static NSString *hour_format(NSLocale *locale) {
    return [NSDateFormatter dateFormatFromTemplate: @"j" options: 0 locale: locale];
}

int main(void) {
    @autoreleasepool {
        set_pref(@"AppleLocale", @"en_US");
        set_pref(@"AppleICUForce24HourTime", nil);
        set_pref(@"AppleFirstWeekday", nil);
        set_pref(@"AppleMetricUnits", nil);
        set_pref(@"AppleMeasurementUnits", nil);

        CHECK([[hour_format([NSLocale currentLocale]) description] containsString: @"a"]);
        CHECK([[NSCalendar currentCalendar] firstWeekday] == 1);
        CHECK(![[[NSLocale currentLocale] objectForKey: NSLocaleUsesMetricSystem] boolValue]);

        // the 24-hour clock, set after the current locale was first used
        set_pref(@"AppleICUForce24HourTime", @YES);
        NSString *format = hour_format([NSLocale currentLocale]);
        CHECK(![format containsString: @"a"] && [format containsString: @"H"]);
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setLocale: [NSLocale currentLocale]];
        [formatter setTimeStyle: NSDateFormatterShortStyle];
        [formatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
        CHECK([[formatter stringFromDate: [NSDate dateWithTimeIntervalSince1970: 1700000000]] isEqualToString: @"22:13"]);
        // a locale made from an identifier does not follow the user's preferences
        CHECK([hour_format([NSLocale localeWithLocaleIdentifier: @"en_US"]) containsString: @"a"]);
        set_pref(@"AppleICUForce24HourTime", nil);
        CHECK([hour_format([NSLocale currentLocale]) containsString: @"a"]);

        // the first day of the week
        set_pref(@"AppleFirstWeekday", @{@"gregorian": @7});
        CHECK([[NSCalendar currentCalendar] firstWeekday] == 7);
        set_pref(@"AppleFirstWeekday", nil);
        CHECK([[NSCalendar currentCalendar] firstWeekday] == 1);

        // units
        set_pref(@"AppleLocale", @"de_DE");
        CHECK([[[NSLocale currentLocale] objectForKey: NSLocaleUsesMetricSystem] boolValue]);
        set_pref(@"AppleMetricUnits", @NO);
        set_pref(@"AppleMeasurementUnits", @"Inches");
        CHECK(![[[NSLocale currentLocale] objectForKey: NSLocaleUsesMetricSystem] boolValue]);
        CHECK([[[NSLocale currentLocale] localeIdentifier] isEqualToString: @"de_DE"]);
        set_pref(@"AppleMetricUnits", nil);
        set_pref(@"AppleMeasurementUnits", nil);
        set_pref(@"AppleLocale", nil);
    }
    puts(failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
