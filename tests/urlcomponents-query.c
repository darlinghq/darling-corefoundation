/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Exercises the CFURLComponents backend directly: ordered, percent-decoded
 * query items with absent and empty values, and setting an empty or NULL query.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFURLComponents.h>
#include <stdio.h>

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); ++failures; } } while (0)

int main(void) {
    CFURLComponentsRef components = _CFURLComponentsCreateWithString(kCFAllocatorDefault,
        CFSTR("https://example.invalid/path?name=a%20b&flag&empty=&name=second"));
    CHECK(components != NULL);
    if (!components) return 1;

    CFArrayRef items = _CFURLComponentsCopyQueryItems(components);
    CHECK(items && CFArrayGetCount(items) == 4);
    if (items && CFArrayGetCount(items) == 4) {
        const CFStringRef names[] = { CFSTR("name"), CFSTR("flag"), CFSTR("empty"), CFSTR("name") };
        const CFStringRef values[] = { CFSTR("a b"), NULL, CFSTR(""), CFSTR("second") };
        for (CFIndex i = 0; i < 4; ++i) {
            CFDictionaryRef pair = CFArrayGetValueAtIndex(items, i);
            CFStringRef name = CFDictionaryGetValue(pair, _kCFURLComponentsNameKey);
            CFStringRef value = CFDictionaryGetValue(pair, _kCFURLComponentsValueKey);
            CHECK(name && CFEqual(name, names[i]));
            if (values[i]) CHECK(value && CFEqual(value, values[i]));
            else CHECK(value == NULL);
        }
    }
    if (items) CFRelease(items);

    CHECK(_CFURLComponentsGetTypeID() == CFGetTypeID(components));

    _CFURLComponentsSetPercentEncodedQuery(components, CFSTR(""));
    items = _CFURLComponentsCopyQueryItems(components);
    CHECK(items && CFArrayGetCount(items) == 0);
    if (items) CFRelease(items);

    _CFURLComponentsSetPercentEncodedQuery(components, NULL);
    items = _CFURLComponentsCopyQueryItems(components);
    CHECK(items == NULL);

    CFRelease(components);
    CHECK(_CFURLComponentsCreateWithString(kCFAllocatorDefault, CFSTR("http://bad host/")) == NULL);

    printf("%s\n", failures ? "FAILED" : "PASS");
    return failures != 0;
}
