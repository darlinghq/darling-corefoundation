#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
static void expect(BOOL ok, const char *label) { printf("%s %s\n", ok ? "PASS" : "FAIL", label); failures += !ok; }

static NSString *contentType(NSString *path) {
    id type = nil;
    if (![[NSURL fileURLWithPath: path] getResourceValue: &type forKey: NSURLContentTypeKey error: NULL])
        return nil;
    return [type identifier];
}

int main(void) { @autoreleasepool {
    char temp[] = "/tmp/darling-url-content-type-XXXXXX";
    char *root = mkdtemp(temp);
    if (!root) return 2;
    NSString *base = [NSString stringWithUTF8String: root];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in @[@"a.txt", @"b.png", @"c.qqqzzz", @"noext"])
        [fm createFileAtPath: [base stringByAppendingPathComponent: name] contents: [NSData data] attributes: nil];
    [fm createFileAtPath: [base stringByAppendingPathComponent: @"tool"] contents: [NSData data] attributes: @{NSFilePosixPermissions: @0755}];
    for (NSString *name in @[@"dir", @"Thing.app", @"dir.txt"])
        mkdir([[base stringByAppendingPathComponent: name] fileSystemRepresentation], 0700);
    symlink("a.txt", [[base stringByAppendingPathComponent: @"link"] fileSystemRepresentation]);

    NSDictionary *expected = @{
        @"a.txt": @"public.plain-text", @"b.png": @"public.png", @"noext": @"public.data", @"tool": @"public.unix-executable",
        @"dir": @"public.folder", @"Thing.app": @"com.apple.application-bundle", @"dir.txt": @"public.folder", @"link": @"public.symlink",
    };
    for (NSString *name in expected)
        expect([contentType([base stringByAppendingPathComponent: name]) isEqual: expected[name]], [name UTF8String]);
    expect([contentType([base stringByAppendingPathComponent: @"c.qqqzzz"]) hasPrefix: @"dyn."], "unknown extension is dynamic");

    id value = @"unset";
    NSError *error = nil;
    BOOL ok = [[NSURL fileURLWithPath: [base stringByAppendingPathComponent: @"missing"]] getResourceValue: &value forKey: NSURLContentTypeKey error: &error];
    expect(!ok && value == nil && error != nil, "missing file reports an error");

    NSDictionary *values = [[NSURL fileURLWithPath: [base stringByAppendingPathComponent: @"a.txt"]]
        resourceValuesForKeys: @[NSURLContentTypeKey, NSURLIsDirectoryKey] error: &error];
    expect([[values[NSURLContentTypeKey] identifier] isEqual: @"public.plain-text"] && [values[NSURLIsDirectoryKey] isEqual: @NO],
        "resourceValuesForKeys");

    [fm removeItemAtPath: base error: NULL];
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures ? 1 : 0;
} }
