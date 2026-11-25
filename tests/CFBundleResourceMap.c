// Copyright (C) 2026 Lubos Dolezel
//
// The deprecated Resource Manager bridge of CFBundle: a bundle without resource files has no resource map to open.
// CFBundleOpenBundleResourceMap gives -1, CFBundleOpenBundleResourceFiles gives -193 (resFNotFound) with both
// reference numbers -1, and closing a map that was never opened is harmless. Values observed on macOS 26.7.3 and
// Mac OS X 10.14.4 (probe: mac-probes/gog-blockers/cf-resourcemap-volumes.c); the program builds and runs there too.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

int main(void)
{
    CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.CoreFoundation"));
    if (bundle == NULL) {
        CFURLRef url = CFURLCreateWithFileSystemPath(NULL, CFSTR("/System/Library/Frameworks/CoreFoundation.framework"),
                                                     kCFURLPOSIXPathStyle, true);
        bundle = CFBundleCreate(NULL, url);
        CFRelease(url);
    }
    expect(bundle != NULL, "a bundle to ask");
    if (bundle == NULL)
        return 1;

    CFBundleRefNum map = CFBundleOpenBundleResourceMap(bundle);
    expect(map == -1, "a bundle without resource files has no resource map: -1");
    CFBundleRefNum again = CFBundleOpenBundleResourceMap(bundle);
    expect(again == -1, "asking again gives -1 again");
    CFBundleCloseBundleResourceMap(bundle, map);
    CFBundleCloseBundleResourceMap(bundle, 12345);
    expect(1, "closing a map that was never opened does nothing");

    CFBundleRefNum refNum = 7, localizedRefNum = 7;
    SInt32 error = CFBundleOpenBundleResourceFiles(bundle, &refNum, &localizedRefNum);
    expect(error == -193, "the resource files of such a bundle are not found: -193");
    expect(refNum == -1 && localizedRefNum == -1, "both reference numbers are -1");
    error = CFBundleOpenBundleResourceFiles(bundle, NULL, NULL);
    expect(error == -193, "the reference numbers are optional");

    CFBundleRef main = CFBundleGetMainBundle();
    if (main != NULL)
        expect(CFBundleOpenBundleResourceMap(main) == -1, "the main bundle of a plain program has no map either");

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
