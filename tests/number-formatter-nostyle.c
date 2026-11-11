// Copyright (C) 2026 Lubos Dolezel
//
// Guest test for the NoStyle number formatter: the sign is kept, no fraction
// digits are shown (round half to even), no grouping. Expected values were
// observed on macOS with NSNumberFormatterNoStyle (vd-upstream/mac-probes/
// v183-nostyle.m). Covers the quirk-marked pattern in CFNumberFormatter.c.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void check(double value, const char *expected)
{
    CFLocaleRef locale = CFLocaleCreate(kCFAllocatorDefault, CFSTR("en_US_POSIX"));
    CFNumberFormatterRef f = CFNumberFormatterCreate(kCFAllocatorDefault, locale, kCFNumberFormatterNoStyle);
    CFStringRef s = CFNumberFormatterCreateStringWithValue(kCFAllocatorDefault, f, kCFNumberDoubleType, &value);
    char buf[64] = "";
    if (s)
        CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
    int ok = strcmp(buf, expected) == 0;
    printf("%s %g -> \"%s\" (want \"%s\")\n", ok ? "PASS" : "FAIL", value, buf, expected);
    failures += !ok;
    if (s) CFRelease(s);
    CFRelease(f);
    CFRelease(locale);
}

int main(void)
{
    check(-2.25, "-2");
    check(2.25, "2");
    check(0.5, "0");
    check(2.5, "2");
    check(3.5, "4");
    check(1234567.8912, "1234568");
    check(-0.4, "-0");
    printf("failures=%d\n", failures);
    return failures != 0;
}
