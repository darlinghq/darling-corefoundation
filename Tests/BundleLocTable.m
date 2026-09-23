#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

CF_EXPORT CFStringRef CFBundleCopyLocalizedStringForLocalization(CFBundleRef, CFStringRef, CFStringRef, CFStringRef, CFStringRef);

static int failures;

static void expect(const char *label, NSString *actual, NSString *expected) {
    BOOL ok = [actual isKindOfClass:[NSString class]] && [actual isEqualToString:expected];
    printf("%s %s: got \"%s\"\n", ok ? "PASS" : "FAIL", label, [[actual description] UTF8String]);
    failures += !ok;
}

static void writePlist(id plist, NSString *path, NSPropertyListFormat format) {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:format options:0 error:&error];
    if (![data writeToFile:path options:0 error:&error]) {
        printf("cannot write %s: %s\n", [path UTF8String], [[error description] UTF8String]);
        exit(2);
    }
}

int main(void) {
    @autoreleasepool {
        char temp[] = "/tmp/darling-loctable-XXXXXX";
        if (!mkdtemp(temp)) return 2;
        NSString *root = [NSString stringWithUTF8String:temp];
        NSString *bundlePath = [root stringByAppendingPathComponent:@"LocTable.bundle"];
        NSString *resources = [bundlePath stringByAppendingPathComponent:@"Contents/Resources"];
        // mkdir(2) rather than NSFileManager: VibeDarling/darling#860 breaks intermediate directory creation.
        for (NSString *dir in @[@"LocTable.bundle", @"LocTable.bundle/Contents", @"LocTable.bundle/Contents/Resources",
                                @"LocTable.bundle/Contents/Resources/en.lproj", @"LocTable.bundle/Contents/Resources/de.lproj"])
            if (mkdir([[root stringByAppendingPathComponent:dir] fileSystemRepresentation], 0700) != 0) return 2;

        writePlist(@{@"CFBundleIdentifier": @"org.darlinghq.loctable-test", @"CFBundleDevelopmentRegion": @"en"},
                   [bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"], NSPropertyListXMLFormat_v1_0);
        writePlist(@{@"LocProvenance": @{},
                     @"en": @{@"GREETING": @"Hello", @"PLURAL": @{@"NSStringLocalizedFormatKey": @"%#@n@"}},
                     @"de": @{@"GREETING": @"Hallo"}},
                   [resources stringByAppendingPathComponent:@"Localizable.loctable"], NSPropertyListBinaryFormat_v1_0);
        writePlist(@{@"en": @{@"SOURCE": @"loctable"}},
                   [resources stringByAppendingPathComponent:@"Other.loctable"], NSPropertyListBinaryFormat_v1_0);
        [@"\"SOURCE\" = \"strings\";\n" writeToFile:[resources stringByAppendingPathComponent:@"en.lproj/Other.strings"]
                                           atomically:NO encoding:NSUTF8StringEncoding error:NULL];

        CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:bundlePath];
        CFBundleRef bundle = CFBundleCreate(NULL, url);
        if (!bundle) return 2;

        expect("preferred localization", [(NSString *)CFBundleCopyLocalizedString(bundle, CFSTR("GREETING"), NULL, NULL) autorelease], @"Hello");
        expect("explicit localization", [(NSString *)CFBundleCopyLocalizedStringForLocalization(bundle, CFSTR("GREETING"), NULL, NULL, CFSTR("de")) autorelease], @"Hallo");
        expect("missing key returns value", [(NSString *)CFBundleCopyLocalizedString(bundle, CFSTR("MISSING"), CFSTR("fallback"), NULL) autorelease], @"fallback");
        expect("non-string entry returns key", [(NSString *)CFBundleCopyLocalizedString(bundle, CFSTR("PLURAL"), NULL, NULL) autorelease], @"PLURAL");
        expect(".strings table takes precedence", [(NSString *)CFBundleCopyLocalizedString(bundle, CFSTR("SOURCE"), NULL, CFSTR("Other")) autorelease], @"strings");
        expect("NSBundle lookup", [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:@"GREETING" value:nil table:nil], @"Hello");

        CFRelease(bundle);
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
