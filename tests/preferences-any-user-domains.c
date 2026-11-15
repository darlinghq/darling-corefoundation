// Copyright (C) 2026 Lubos Dolezel
// The any-user preference domains live in /Library/Preferences whichever host is named.
// See preferences-any-user-domains.md.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int failures;

static void check(int ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static int sameKeys(CFArrayRef a, CFArrayRef b) {
    if (!a || !b)
        return a == b;
    return CFEqual(a, b);
}

int main(void) {
    // Read-only: the system-wide global domain is one domain for both host selectors
    CFArrayRef anyHost = CFPreferencesCopyKeyList(kCFPreferencesAnyApplication, kCFPreferencesAnyUser, kCFPreferencesAnyHost);
    CFArrayRef curHost = CFPreferencesCopyKeyList(kCFPreferencesAnyApplication, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
    check(sameKeys(anyHost, curHost), "global domain key list is the same for AnyHost and CurrentHost");

    // Write: a value set through one host selector is read through the other and is stored in
    // /Library/Preferences/<domain>.plist. Needs write access to the directory.
    const char *path = "/Library/Preferences/org.darlinghq.test.anyuserdomain.plist";
    CFStringRef domain = CFSTR("org.darlinghq.test.anyuserdomain");
    CFStringRef key = CFSTR("Marker");
    unlink(path);
    CFPreferencesSetValue(key, CFSTR("one"), domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost);
    if (!CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost) || access(path, F_OK) != 0) {
        printf("SKIP: /Library/Preferences is not writable\n");
    } else {
        CFPropertyListRef v = CFPreferencesCopyValue(key, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
        check(v && CFEqual(v, CFSTR("one")), "value set for AnyHost is read for CurrentHost");
        if (v)
            CFRelease(v);

        CFPreferencesSetValue(key, CFSTR("two"), domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
        v = CFPreferencesCopyValue(key, domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost);
        check(v && CFEqual(v, CFSTR("two")), "value set for CurrentHost is read for AnyHost");
        if (v)
            CFRelease(v);

        CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
        check(access(path, F_OK) == 0, "stored in /Library/Preferences/<domain>.plist");
        check(access("/Library/Preferences/Network/org.darlinghq.test.anyuserdomain.plist", F_OK) != 0, "nothing is stored in /Library/Preferences/Network");
        unlink(path);
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
