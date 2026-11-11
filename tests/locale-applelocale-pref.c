// Copyright (C) 2026 Lubos Dolezel
// Build against the candidate CoreFoundation and run under Darling; see locale-applelocale-pref.md.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int pass, total;

static void check(const char *label, int ok) {
    total++;
    pass += ok;
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
}

static int identIs(CFLocaleRef loc, const char *want) {
    char buf[64] = {0};
    CFStringRef id = CFLocaleGetIdentifier(loc);
    CFStringGetCString(id, buf, sizeof buf, kCFStringEncodingUTF8);
    return strcmp(buf, want) == 0;
}

int main(void) {
    // A locale made from an identifier has no preferences; querying the
    // measurement system must not dereference them.
    CFLocaleRef fixed = CFLocaleCreate(NULL, CFSTR("de_DE"));
    CFTypeRef metric = CFLocaleGetValue(fixed, kCFLocaleUsesMetricSystem);
    check("usesMetricSystem on a locale without preferences", metric == kCFBooleanTrue);
    CFRelease(fixed);

    // AppleLocale in the application's preferences selects the current locale.
    CFPreferencesSetAppValue(CFSTR("AppleLocale"), CFSTR("fr_FR"), kCFPreferencesCurrentApplication);
    CFLocaleRef cur = CFLocaleCopyCurrent();
    check("current locale follows AppleLocale (fr_FR)", identIs(cur, "fr_FR"));
    CFRelease(cur);

    CFPreferencesSetAppValue(CFSTR("AppleLocale"), CFSTR("ja_JP"), kCFPreferencesCurrentApplication);
    cur = CFLocaleCopyCurrent();
    check("current locale follows a changed AppleLocale (ja_JP)", identIs(cur, "ja_JP"));
    CFRelease(cur);

    // The host environment is not consulted.
    CFPreferencesSetAppValue(CFSTR("AppleLocale"), NULL, kCFPreferencesCurrentApplication);
    setenv("LC_ALL", "de_DE.UTF-8", 1);
    cur = CFLocaleCopyCurrent();
    check("LC_ALL is ignored without AppleLocale", !identIs(cur, "de_DE"));
    CFRelease(cur);

    // Looking at the current locale's preferences through the Objective-C
    // bridge (a bridged CFLocale answers -_prefs) must not recurse.
    cur = CFLocaleCopyCurrent();
    CFTypeRef unit = CFLocaleGetValue(cur, kCFLocaleUsesMetricSystem);
    check("usesMetricSystem on the current locale returns a boolean",
          unit == kCFBooleanTrue || unit == kCFBooleanFalse);
    CFRelease(cur);

    printf("%d/%d passed\n", pass, total);
    return pass == total ? 0 : 1;
}
