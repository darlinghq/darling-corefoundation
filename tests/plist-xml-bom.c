// Copyright (C) 2026 Lubos Dolezel
// Build against the candidate CoreFoundation and run under Darling; see plist-xml-bom.md.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void) {
    static const char bom[] = "\xEF\xBB\xBF";
    static const char xml[] =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<plist version=\"1.0\"><dict><key>k</key><string>v</string></dict></plist>";
    size_t len = 3 + strlen(xml);
    long page = sysconf(_SC_PAGESIZE);

    // Put the data directly in front of an inaccessible page so that reading
    // past its end faults.
    char *map = mmap(NULL, 2 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (map == MAP_FAILED || mprotect(map + page, page, PROT_NONE) != 0) {
        printf("FAIL mmap\n");
        return 1;
    }
    char *p = map + page - len;
    memcpy(p, bom, 3);
    memcpy(p + 3, xml, strlen(xml));

    CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, (const UInt8 *)p, len, kCFAllocatorNull);
    CFErrorRef err = NULL;
    CFPropertyListRef pl = CFPropertyListCreateWithData(NULL, data, kCFPropertyListImmutable, NULL, &err);

    int ok = pl && CFGetTypeID(pl) == CFDictionaryGetTypeID();
    if (ok) {
        CFTypeRef v = CFDictionaryGetValue(pl, CFSTR("k"));
        ok = v && CFGetTypeID(v) == CFStringGetTypeID() && CFEqual(v, CFSTR("v"));
    }
    printf("%s BOM-prefixed XML plist at the end of a mapping\n", ok ? "PASS" : "FAIL");
    printf("%d/1 passed\n", ok);
    return ok ? 0 : 1;
}
