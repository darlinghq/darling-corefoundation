// Copyright (C) 2026 Lubos Dolezel
//
// Guest test (quirk): _CFPrefsSetReadOnly. Observed on macOS 26.7.3 (x86_64)
// with the same calls, checked from a second process: while read-only,
// setting and removing values changes what the process reads back and
// synchronizing returns true, but nothing reaches disk; after read-only is
// turned off, a newly set value is saved and the read-only changes still
// are not.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void _CFPrefsSetReadOnly(Boolean);

#define APP CFSTR("org.darlinghq.test.prefs-read-only")

static int failures;

static void report(const char *name, int ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

static int hasValue(CFStringRef key, CFStringRef expected)
{
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, APP);
    int result = expected == NULL ? value == NULL : value != NULL && CFEqual(value, expected);
    if (value)
        CFRelease(value);
    return result;
}

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "--check-disk") == 0) {
        // A fresh process sees only what reached disk.
        int ok = hasValue(CFSTR("before"), CFSTR("1")) && hasValue(CFSTR("during"), NULL) && hasValue(CFSTR("later"), CFSTR("3"));
        CFPreferencesSetAppValue(CFSTR("before"), NULL, APP);
        CFPreferencesSetAppValue(CFSTR("later"), NULL, APP);
        CFPreferencesAppSynchronize(APP);
        return ok ? 0 : 1;
    }

    CFPreferencesSetAppValue(CFSTR("before"), CFSTR("1"), APP);
    CFPreferencesAppSynchronize(APP);

    _CFPrefsSetReadOnly(true);
    CFPreferencesSetAppValue(CFSTR("during"), CFSTR("2"), APP);
    report("synchronize succeeds while read-only", CFPreferencesAppSynchronize(APP));
    report("value set while read-only reads back", hasValue(CFSTR("during"), CFSTR("2")));
    CFPreferencesSetAppValue(CFSTR("before"), NULL, APP);
    CFPreferencesAppSynchronize(APP);
    report("removal while read-only reads back", hasValue(CFSTR("before"), NULL));

    _CFPrefsSetReadOnly(false);
    CFPreferencesSetAppValue(CFSTR("later"), CFSTR("3"), APP);
    report("synchronize after turning it off", CFPreferencesAppSynchronize(APP));

    char command[1100];
    snprintf(command, sizeof command, "'%s' --check-disk", argv[0]);
    report("only the later value and the earlier one reach disk", system(command) == 0);
    return failures != 0;
}
