// Copyright (C) 2026 Lubos Dolezel
//
// CFStringTransform: the range argument is optional (NULL transforms the whole string),
// and when given it selects what is transformed and is updated with the result.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static int failures;

static void check(const char *label, int ok)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", label);
	failures += !ok;
}

int main(void)
{
	CFStringRef whole = CFStringCreateWithCString(NULL, "\xc3\x85ngstr\xc3\xb6m", kCFStringEncodingUTF8);
	CFMutableStringRef s = CFStringCreateMutableCopy(NULL, 0, whole);

	check("NULL range strips diacritics",
	      CFStringTransform(s, NULL, kCFStringTransformStripDiacritics, false)
	      && CFStringCompare(s, CFSTR("Angstrom"), 0) == kCFCompareEqualTo);

	CFRelease(s);
	s = CFStringCreateMutableCopy(NULL, 0, CFSTR("xAx"));
	CFRange r = CFRangeMake(1, 1);
	check("range: lowercases only the range",
	      CFStringTransform(s, &r, CFSTR("Any-Lower"), false)
	      && CFStringCompare(s, CFSTR("xax"), 0) == kCFCompareEqualTo && r.location == 1 && r.length == 1);

	CFRange bad = CFRangeMake(2, 5);
	check("range past the end fails", !CFStringTransform(s, &bad, CFSTR("Any-Lower"), false));
	check("unknown transform fails", !CFStringTransform(s, NULL, CFSTR("No-Such-Transform"), false));

	CFRelease(s);
	CFRelease(whole);
	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
