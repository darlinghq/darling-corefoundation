// Copyright (C) 2026 Lubos Dolezel
//
// CFStringTransform: the range argument is optional (NULL transforms the whole string);
// when given it selects what is transformed and is updated with the result.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static int failures;

static void check(const char *label, int ok)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", label);
	failures += !ok;
}

static CFMutableStringRef make(const char *utf8)
{
	CFStringRef s = CFStringCreateWithCString(NULL, utf8, kCFStringEncodingUTF8);
	CFMutableStringRef m = CFStringCreateMutableCopy(NULL, 0, s);
	CFRelease(s);
	return m;
}

int main(void)
{
	// "Angstroem" with a ring above the A and a diaeresis on the o (precomposed)
	const char *source = "\xc3\x85ngstr\xc3\xb6m";
	CFMutableStringRef s = make(source);

	check("NULL range strips diacritics",
	      CFStringTransform(s, NULL, kCFStringTransformStripDiacritics, false)
	      && CFStringCompare(s, CFSTR("Angstrom"), 0) == kCFCompareEqualTo);
	CFRelease(s);

	s = make(source);
	CFRange r = CFRangeMake(6, 1);
	CFMutableStringRef expected = make("\xc3\x85ngstrom");
	check("range: only the characters in the range change",
	      CFStringTransform(s, &r, kCFStringTransformStripDiacritics, false)
	      && CFStringCompare(s, expected, 0) == kCFCompareEqualTo && r.location == 6 && r.length == 1);
	CFRelease(expected);

	s = make(source);
	check("unicode name: only non-ASCII characters are named",
	      CFStringTransform(s, NULL, kCFStringTransformToUnicodeName, false)
	      && CFStringCompare(s, CFSTR("\\N{LATIN CAPITAL LETTER A WITH RING ABOVE}ngstr\\N{LATIN SMALL LETTER O WITH DIAERESIS}m"), 0) == kCFCompareEqualTo);
	CFRelease(s);

	s = make(source);
	CFRange bad = CFRangeMake(2, 50);
	check("range past the end fails", !CFStringTransform(s, &bad, kCFStringTransformStripDiacritics, false));
	check("unknown transform fails", !CFStringTransform(s, NULL, CFSTR("No-Such-Transform"), false));
	CFRelease(s);

	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
