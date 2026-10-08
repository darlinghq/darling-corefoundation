// Build against the candidate CoreFoundation and run under Darling; see string-format-incomplete-star.md.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

static int check(const char *label, CFStringRef s, const char *want) {
    char buf[64] = {0};
    CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
    int ok = strcmp(buf, want) == 0;
    printf("%s %s: got \"%s\" want \"%s\"\n", ok ? "PASS" : "FAIL", label, buf, want);
    CFRelease(s);
    return ok;
}

int main(void) {
    int pass = 0, total = 3;
    pass += check("trailing %*", CFStringCreateWithFormat(NULL, NULL, CFSTR("abc%*")), "abc");
    pass += check("trailing %.*", CFStringCreateWithFormat(NULL, NULL, CFSTR("abc%.*")), "abc");
    pass += check("complete %*d", CFStringCreateWithFormat(NULL, NULL, CFSTR("%*d"), 4, 7), "   7");
    printf("%d/%d passed\n", pass, total);
    return pass == total ? 0 : 1;
}
