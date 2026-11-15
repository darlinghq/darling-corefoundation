// Copyright (C) 2026 Lubos Dolezel
// The system time zone is the zone /etc/localtime leads to, however many links the path goes through.
// See timezone-system-link.md.
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    // The environment overrides /etc/localtime, so take it out of the picture
    unsetenv("TZ");
    unsetenv("TZFILE");

    // Follow /etc/localtime link by link to the first target that has a zoneinfo directory component;
    // the zone is the part below the last such component
    char current[PATH_MAX] = "/etc/localtime", target[PATH_MAX];
    const char *marker = NULL;
    for (int hops = 0; hops < 8 && marker == NULL; hops++) {
        ssize_t length = readlink(current, target, sizeof target - 1);
        if (length <= 0)
            break;
        target[length] = '\0';
        const char *at = target;
        while ((at = strstr(at, "/zoneinfo/")) != NULL) {
            marker = at + strlen("/zoneinfo/");
            at = marker;
        }
        if (marker == NULL) {
            if (target[0] != '/')
                break; // relative links are not followed by this test
            strcpy(current, target);
        }
    }
    if (marker == NULL || *marker == '\0') {
        printf("SKIP /etc/localtime does not lead to a zoneinfo file\n");
        return 0;
    }

    CFTimeZoneRef system = CFTimeZoneCopySystem();
    char name[128] = {0};
    CFStringGetCString(CFTimeZoneGetName(system), name, sizeof name, kCFStringEncodingUTF8);
    int ok = strcmp(name, marker) == 0;
    printf("%s system time zone is \"%s\", /etc/localtime leads to \"%s\"\n", ok ? "PASS" : "FAIL", name, marker);
    CFRelease(system);
    return ok ? 0 : 1;
}
