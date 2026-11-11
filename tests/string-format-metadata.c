// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: per-specifier metadata from string formatting reports the
// specifier range in the format, the replacement range in the output, the
// argument index, and the object for %@ specifiers.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void check(const char *label, int ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static CFIndex number(CFDictionaryRef d, CFStringRef key)
{
    CFNumberRef n = CFDictionaryGetValue(d, key);
    CFIndex v = -1;
    if (n)
        CFNumberGetValue(n, kCFNumberCFIndexType, &v);
    return v;
}

static CFStringRef make(CFArrayRef *meta, CFStringRef format, ...)
{
    va_list ap;
    va_start(ap, format);
    CFStringRef s = _CFStringCreateWithFormatAndArgumentsReturningMetadata(kCFAllocatorDefault, NULL, NULL, NULL, NULL, format, meta, ap);
    va_end(ap);
    return s;
}

int main(void)
{
    CFArrayRef meta = NULL;
    CFStringRef out = make(&meta, CFSTR("a %@ b %d"), CFSTR("xyz"), 42);
    check("output", out && CFEqual(out, CFSTR("a xyz b 42")));
    check("two entries", meta && CFArrayGetCount(meta) == 2);
    if (meta && CFArrayGetCount(meta) == 2) {
        CFDictionaryRef e0 = CFArrayGetValueAtIndex(meta, 0), e1 = CFArrayGetValueAtIndex(meta, 1);
        check("first spec range", number(e0, _kCFStringFormatMetadataSpecifierRangeLocationInFormatStringKey) == 2 &&
                                      number(e0, _kCFStringFormatMetadataSpecifierRangeLengthInFormatStringKey) == 2);
        check("first replacement range", number(e0, _kCFStringFormatMetadataReplacementRangeLocationKey) == 2 &&
                                             number(e0, _kCFStringFormatMetadataReplacementRangeLengthKey) == 3);
        check("first object", CFEqual(CFDictionaryGetValue(e0, _kCFStringFormatMetadataArgumentObjectKey), CFSTR("xyz")));
        check("second replacement range", number(e1, _kCFStringFormatMetadataReplacementRangeLocationKey) == 8 &&
                                              number(e1, _kCFStringFormatMetadataReplacementRangeLengthKey) == 2);
        check("second has no object", CFDictionaryGetValue(e1, _kCFStringFormatMetadataArgumentObjectKey) == NULL);
    }
    if (meta) CFRelease(meta);
    if (out) CFRelease(out);

    // A NULL outMetadata behaves like plain formatting.
    CFStringRef plain = make(NULL, CFSTR("%d"), 7);
    check("NULL metadata", plain && CFEqual(plain, CFSTR("7")));
    if (plain) CFRelease(plain);
    printf("failures=%d\n", failures);
    return failures != 0;
}
