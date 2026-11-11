// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: CFLogTest, _CFWebServicesCopyProviderInfo and
// CFStringTokenizerCopyBestStringLanguage exist and behave as documented
// stubs (no provider, language not determined).
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

extern void CFLogTest(int32_t level, CFStringRef message);
extern CFDictionaryRef _CFWebServicesCopyProviderInfo(CFStringRef type, void *reserved);
extern const CFStringRef kCFWebServicesTypeWebSearch;

static int failures;
static void check(const char *label, int ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

int main(void)
{
    CFLogTest(0, CFSTR("cf-spi-stubs test message"));
    CFLogTest(0, NULL);
    check("CFLogTest returns", 1);
    check("no web search provider", _CFWebServicesCopyProviderInfo(kCFWebServicesTypeWebSearch, NULL) == NULL);
    CFStringRef s = CFSTR("The quick brown fox");
    CFStringRef lang = CFStringTokenizerCopyBestStringLanguage(s, CFRangeMake(0, CFStringGetLength(s)));
    check("language not determined returns NULL", lang == NULL);
    if (lang) CFRelease(lang);
    printf("failures=%d\n", failures);
    return failures != 0;
}
