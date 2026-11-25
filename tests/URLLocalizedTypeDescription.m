// CFLAGS: -framework Foundation -framework CoreServices -fobjc-arc
// NSURLLocalizedTypeDescriptionKey: the item's kind, as LaunchServices names it (the same string
// LSCopyKindStringForURL gives), for a folder, an application bundle, a file without an extension and
// a missing path (an error, no value). Passes unchanged on macOS 10.14.4 and 26.7.3.
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static NSString *kindFromLaunchServices(NSURL *url)
{
    CFStringRef kind = NULL;
    if (LSCopyKindStringForURL((__bridge CFURLRef) url, &kind) != noErr || kind == NULL)
        return nil;
    return CFBridgingRelease(kind);
}

static void checkKind(const char *label, NSURL *url, NSString *expected)
{
    NSString *value = nil;
    NSError *error = nil;
    BOOL ok = [url getResourceValue: &value forKey: NSURLLocalizedTypeDescriptionKey error: &error];
    NSString *ls = kindFromLaunchServices(url);
    BOOL matches = ok && value != nil && [value isEqual: ls] && (expected == nil || [value isEqual: expected]);
    if (!matches)
        printf("  %s: got %s, LaunchServices %s\n", label, [[value description] UTF8String], [[ls description] UTF8String]);
    check_result(label, matches);
}

int main(void)
{
    @autoreleasepool {
        const char *tmpdir = getenv("TMPDIR");
        NSString *base = [NSString stringWithFormat: @"%s/urlkindXXXXXX", tmpdir != NULL ? tmpdir : "/tmp"];
        char buffer[1024];
        strlcpy(buffer, [base fileSystemRepresentation], sizeof(buffer));
        if (mkdtemp(buffer) == NULL) {
            perror("mkdtemp");
            return 2;
        }
        NSString *dir = [NSString stringWithUTF8String: buffer];
        NSString *folder = [dir stringByAppendingPathComponent: @"folder"];
        NSString *plain = [dir stringByAppendingPathComponent: @"plain"];
        [[NSFileManager defaultManager] createDirectoryAtPath: folder withIntermediateDirectories: NO attributes: nil error: NULL];
        [[NSFileManager defaultManager] createFileAtPath: plain contents: [NSData data] attributes: nil];

        checkKind("a folder is a Folder", [NSURL fileURLWithPath: folder], @"Folder");
        checkKind("an application bundle is an Application",
                  [NSURL fileURLWithPath: @"/System/Library/CoreServices/Finder.app"], @"Application");
        checkKind("a file without an extension has LaunchServices' kind", [NSURL fileURLWithPath: plain], nil);

        NSString *value = @"unchanged";
        NSError *error = nil;
        BOOL ok = [[NSURL fileURLWithPath: [dir stringByAppendingPathComponent: @"missing"]]
            getResourceValue: &value forKey: NSURLLocalizedTypeDescriptionKey error: &error];
        check_result("a missing path is an error, with no value", !ok && value == nil && error != nil);

        [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures != 0;
}
