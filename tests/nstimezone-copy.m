// Copyright (C) 2026 Lubos Dolezel
//
// Copying an NSTimeZone: time zones are immutable, so -copy returns the
// receiver (the same on macOS 27, for named and for fixed-offset zones).
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
    @autoreleasepool
    {
        NSTimeZone *berlin = [NSTimeZone timeZoneWithName:@"Europe/Berlin"];
        NSTimeZone *copy = nil;
        @try { copy = [berlin copy]; } @catch (NSException *e) { printf("FAIL: -copy raised %s\n", [[e name] UTF8String]); failures++; }
        CHECK(copy != nil);
        CHECK([copy isEqual:berlin]);
        CHECK([[copy name] isEqualToString:@"Europe/Berlin"]);
        CHECK([copy secondsFromGMTForDate:[NSDate dateWithTimeIntervalSince1970:1626350400]] == 7200);
        CHECK(copy == berlin);
        [copy release];

        NSTimeZone *fixed = [NSTimeZone timeZoneForSecondsFromGMT:3600];
        NSTimeZone *fixedCopy = nil;
        @try { fixedCopy = [fixed copy]; } @catch (NSException *e) { printf("FAIL: -copy of a fixed zone raised\n"); failures++; }
        CHECK(fixedCopy == fixed && [fixedCopy secondsFromGMT] == 3600);
        [fixedCopy release];

        // The copy of a copy and use as a dictionary key (which copies its keys).
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        @try { [dictionary setObject:@"v" forKey:berlin]; } @catch (NSException *e) { printf("FAIL: a time zone as a dictionary key raised\n"); failures++; }
        CHECK([[dictionary objectForKey:berlin] isEqual:@"v"]);
    }
    if (failures != 0) { printf("%d failures\n", failures); return 1; }
    printf("PASS: NSTimeZone copy\n");
    return 0;
}
