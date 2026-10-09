#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;

static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static void check_identifier(NSURL *url, const char *label, NSString *expected)
{
    id value = nil;
    NSError *error = nil;
    BOOL ok = [url getResourceValue:&value forKey:NSURLTypeIdentifierKey error:&error];
    check_result(label, ok && [value isEqual:expected]);
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool
    {
        char template[] = "/tmp/urltypeid-XXXXXX";
        if (mkdtemp(template) == NULL)
        {
            perror("mkdtemp");
            return 2;
        }
        NSString *root = [NSString stringWithUTF8String:template];
        NSFileManager *manager = [NSFileManager defaultManager];
        NSString *file = [root stringByAppendingPathComponent:@"a-file.txt"];
        [@"text" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:nil];

        puts("reading the directory type identifier");
        check_identifier([NSURL fileURLWithPath:root isDirectory:YES], "directory without extension", @"public.folder");
        check_identifier([NSURL fileURLWithPath:file], "regular file with extension", @"public.plain-text");

        NSString *bare = [root stringByAppendingPathComponent:@"bare"];
        [@"x" writeToFile:bare atomically:NO encoding:NSUTF8StringEncoding error:nil];
        check_identifier([NSURL fileURLWithPath:bare], "extensionless regular file", @"public.data");

        id contentType = nil;
        [[NSURL fileURLWithPath:file] getResourceValue:&contentType forKey:NSURLContentTypeKey error:nil];
        id identifier = nil;
        [[NSURL fileURLWithPath:file] getResourceValue:&identifier forKey:NSURLTypeIdentifierKey error:nil];
        check_result("matches content type identifier", contentType != nil && [identifier isEqual:[contentType identifier]]);

        NSError *error = nil;
        id missing = nil;
        BOOL ok = [[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"absent"]] getResourceValue:&missing forKey:NSURLTypeIdentifierKey error:&error];
        check_result("missing file reports an error", !ok && missing == nil && error != nil);

        [manager removeItemAtPath:root error:nil];
    }
    return failures != 0;
}
