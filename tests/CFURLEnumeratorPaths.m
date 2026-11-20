// Copyright (C) 2026 Lubos Dolezel
//
// CFURLEnumerator and -[NSFileManager enumeratorAtURL:...] on directories whose URL
// is percent-escaped (a space in the name) or relative to a base URL, as
// -[NSBundle resourceURL] is, and the skip-invisibles option.
// Expected listings are what macOS 26.7.3 and Mac OS X 10.14.4 return
// (vd-upstream/mac-probes/search-paths-enumerator on both).
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFURLEnumerator.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static void touch(NSString *path)
{
    [[NSData data] writeToFile:path atomically:NO];
}

// Paths below root of everything the enumerator returns, sorted.
static NSString *cfListing(CFURLRef url, CFURLEnumeratorOptions options, NSString *root)
{
    CFURLEnumeratorRef e = CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault, url, options, NULL);
    if (e == NULL)
        return @"<no enumerator>";
    NSMutableArray *items = [NSMutableArray array];
    CFURLRef item = NULL;
    CFErrorRef error = NULL;
    CFURLEnumeratorResult r;
    // The URL and error follow the Get rule: they are not released here.
    while ((r = CFURLEnumeratorGetNextURL(e, &item, &error)) != kCFURLEnumeratorEnd) {
        if (r == kCFURLEnumeratorSuccess) {
            NSString *p = [[(__bridge NSURL *)item URLByStandardizingPath] path];
            [items addObject:[p hasPrefix:root] ? [p substringFromIndex:[root length]] : p];
        } else {
            [items addObject:@"<error>"];
            break;
        }
    }
    CFRelease(e);
    [items sortUsingSelector:@selector(compare:)];
    return [items componentsJoinedByString:@" "];
}

static NSString *nsListing(NSURL *url, NSDirectoryEnumerationOptions options, NSString *root)
{
    NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtURL:url includingPropertiesForKeys:nil options:options errorHandler:nil];
    NSMutableArray *items = [NSMutableArray array];
    for (NSURL *item in e) {
        NSString *p = [[item URLByStandardizingPath] path];
        [items addObject:[p hasPrefix:root] ? [p substringFromIndex:[root length]] : p];
    }
    [items sortUsingSelector:@selector(compare:)];
    return [items componentsJoinedByString:@" "];
}

int main(void)
{
    @autoreleasepool {
        char tmpl[] = "/tmp/cfurl-enum-paths-XXXXXX";
        if (mkdtemp(tmpl) == NULL)
            return 2;
        NSString *root = [[[NSString stringWithUTF8String:tmpl] stringByResolvingSymlinksInPath] stringByAppendingString:@"/"];
        NSString *dir = [root stringByAppendingString:@"a b"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@".hiddendir"] withIntermediateDirectories:YES attributes:nil error:NULL];
        touch([dir stringByAppendingPathComponent:@"x.txt"]);
        touch([dir stringByAppendingPathComponent:@".hidden"]);
        touch([dir stringByAppendingPathComponent:@"sub/in.txt"]);
        touch([dir stringByAppendingPathComponent:@".hiddendir/h.txt"]);

        NSString *everything = @"a b/.hidden a b/.hiddendir a b/.hiddendir/h.txt a b/sub a b/sub/in.txt a b/x.txt";
        NSString *visible = @"a b/sub a b/sub/in.txt a b/x.txt";
        NSString *flat = @"a b/.hidden a b/.hiddendir a b/sub a b/x.txt";

        NSURL *abs = [NSURL fileURLWithPath:dir isDirectory:YES];
        // relative to a base URL, the way -[NSBundle resourceURL] is
        NSURL *rel = [NSURL URLWithString:@"a%20b/" relativeToURL:[NSURL fileURLWithPath:root isDirectory:YES]];

        check_result("CF: escaped absolute URL, recursive",
              [cfListing((__bridge CFURLRef)abs, kCFURLEnumeratorDescendRecursively, root) isEqual:everything]);
        check_result("CF: escaped absolute URL, flat",
              [cfListing((__bridge CFURLRef)abs, kCFURLEnumeratorDefaultBehavior, root) isEqual:flat]);
        check_result("CF: relative URL, recursive",
              [cfListing((__bridge CFURLRef)rel, kCFURLEnumeratorDescendRecursively, root) isEqual:everything]);
        check_result("CF: skip invisibles",
              [cfListing((__bridge CFURLRef)abs, kCFURLEnumeratorDescendRecursively | kCFURLEnumeratorSkipInvisibles, root) isEqual:visible]);

        check_result("NSFileManager: escaped absolute URL", [nsListing(abs, 0, root) isEqual:everything]);
        check_result("NSFileManager: relative URL", [nsListing(rel, 0, root) isEqual:everything]);
        check_result("NSFileManager: path appended to a relative URL",
              [nsListing([rel URLByAppendingPathComponent:@"sub"], 0, root) isEqual:@"a b/sub/in.txt"]);
        check_result("NSFileManager: skips hidden files", [nsListing(abs, NSDirectoryEnumerationSkipsHiddenFiles, root) isEqual:visible]);
        check_result("NSFileManager: skips subdirectory descendants",
              [nsListing(abs, NSDirectoryEnumerationSkipsSubdirectoryDescendants, root) isEqual:flat]);

        [fm removeItemAtPath:[NSString stringWithUTF8String:tmpl] error:NULL];
    }
    return failures != 0;
}
