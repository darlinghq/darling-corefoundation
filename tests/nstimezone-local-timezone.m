// Copyright (C) 2026 Lubos Dolezel
//
// +[NSTimeZone localTimeZone] must work whether or not TZ is set in the
// environment. Run once without arguments (TZ is unset by the test before the
// first use) and once with the argument "tz" and TZ=Europe/Berlin already in the
// environment of the process (env TZ=Europe/Berlin test tz).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(int argc, char **argv)
{
    int withTZ = argc > 1 && strcmp(argv[1], "tz") == 0;
    if (withTZ) {
        if (getenv("TZ") == NULL || strcmp(getenv("TZ"), "Europe/Berlin") != 0) {
            printf("FAIL: run with TZ=Europe/Berlin in the environment\n");
            return 2;
        }
    } else
        unsetenv("TZ");

    @autoreleasepool
    {
        NSTimeZone *local = [NSTimeZone localTimeZone];
        CHECK(local != nil);
        CHECK([[local name] length] > 0);
        CHECK(local == [NSTimeZone localTimeZone]);
        CHECK([local isEqual:[NSTimeZone systemTimeZone]]);
        if (withTZ)
            CHECK([[local name] isEqualToString:@"Europe/Berlin"]);

        // Unlike the default zone, the local zone ignores +setDefaultTimeZone:.
        [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:3600]];
        CHECK([NSTimeZone localTimeZone] == local);
        CHECK([[NSTimeZone defaultTimeZone] secondsFromGMT] == 3600);
    }
    if (failures != 0) { printf("%d failures\n", failures); return 1; }
    printf("PASS: NSTimeZone localTimeZone (%s)\n", withTZ ? "TZ set" : "TZ unset");
    return 0;
}
