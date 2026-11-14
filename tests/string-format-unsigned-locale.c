// Copyright (C) 2026 Lubos Dolezel
//
// Unsigned conversions in CFStringCreateWithFormat with a locale as format
// options. Expected strings follow printf semantics with en_US digit grouping;
// the narrow-width cases are a QUIRK (see CFString.c) observed on macOS 26.7.3.
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void check(const char *label, CFStringRef s, const char *want)
{
    char buf[128] = {0};
    CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
    if (strcmp(buf, want) != 0) {
        printf("FAIL %s: got \"%s\" want \"%s\"\n", label, buf, want);
        failures++;
    }
    CFRelease(s);
}

static void test_unsigned_64bit(CFDictionaryRef loc)
{
    check("llu UINT64_MAX", CFStringCreateWithFormat(NULL, loc, CFSTR("%llu"), UINT64_MAX), "18,446,744,073,709,551,615");
    check("llu 2^63", CFStringCreateWithFormat(NULL, loc, CFSTR("%llu"), 1ULL << 63), "9,223,372,036,854,775,808");
    check("lu UINT64_MAX", CFStringCreateWithFormat(NULL, loc, CFSTR("%lu"), (unsigned long)UINT64_MAX), "18,446,744,073,709,551,615");
    check("llu 0", CFStringCreateWithFormat(NULL, loc, CFSTR("%llu"), 0ULL), "0");
    check("llu 1234567", CFStringCreateWithFormat(NULL, loc, CFSTR("%llu"), 1234567ULL), "1,234,567");
    check("lld INT64_MIN", CFStringCreateWithFormat(NULL, loc, CFSTR("%lld"), INT64_MIN), "-9,223,372,036,854,775,808");
    check("d 65000", CFStringCreateWithFormat(NULL, loc, CFSTR("%d"), 65000), "65,000");
    check("u 65000", CFStringCreateWithFormat(NULL, loc, CFSTR("%u"), 65000u), "65,000");
    check("10llu 5", CFStringCreateWithFormat(NULL, loc, CFSTR("%10llu"), 5ULL), "         5");
}

// QUIRK coverage: an unsigned conversion narrower than 64 bits is sign-extended
// before it is formatted when a locale is given.
static void test_quirk_narrow_unsigned_sign_extended(CFDictionaryRef loc)
{
    check("quirk hhu 200", CFStringCreateWithFormat(NULL, loc, CFSTR("%hhu"), (unsigned char)200), "18,446,744,073,709,551,560");
    check("quirk hu 65000", CFStringCreateWithFormat(NULL, loc, CFSTR("%hu"), (unsigned short)65000), "18,446,744,073,709,551,080");
    check("quirk u UINT32_MAX", CFStringCreateWithFormat(NULL, loc, CFSTR("%u"), (unsigned)UINT32_MAX), "18,446,744,073,709,551,615");
    check("hhu 100", CFStringCreateWithFormat(NULL, loc, CFSTR("%hhu"), (unsigned char)100), "100");
}

static void test_without_locale(void)
{
    check("nolocale llu", CFStringCreateWithFormat(NULL, NULL, CFSTR("%llu"), UINT64_MAX), "18446744073709551615");
    check("nolocale hhu", CFStringCreateWithFormat(NULL, NULL, CFSTR("%hhu"), (unsigned char)200), "200");
    check("nolocale hu", CFStringCreateWithFormat(NULL, NULL, CFSTR("%hu"), (unsigned short)65000), "65000");
}

int main(void)
{
    CFLocaleRef locale = CFLocaleCreate(NULL, CFSTR("en_US"));
    test_unsigned_64bit((CFDictionaryRef)locale);
    test_quirk_narrow_unsigned_sign_extended((CFDictionaryRef)locale);
    test_without_locale();
    CFRelease(locale);
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS: CFString unsigned formatting with a locale\n");
    return 0;
}
