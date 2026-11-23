// Copyright (C) 2026 Lubos Dolezel
// url-bookmark-directory: bookmark data of a file resolves to a file URL without a trailing slash, and that of a
// directory to a directory URL (hasDirectoryPath), through NSURL and through CFURL. Prints "FAIL: ..." for each check
// that does not hold and exits 1 if any did. Link with -framework Foundation. Also passes on macOS 26.7.3.
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    if (!ok)
    {
        printf("FAIL: %s\n", [what UTF8String]);
        failures++;
    }
}

static void roundTrip(NSString *path, BOOL directory)
{
    NSURL *url = [NSURL fileURLWithPath:path isDirectory:directory];
    NSData *bookmark = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
    BOOL stale = NO;
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:NULL];
    expect([resolved.path isEqual:path] && resolved.hasDirectoryPath == directory,
        [NSString stringWithFormat:@"%@ resolves to %@", path, resolved]);

    Boolean cfStale = false;
    CFURLRef cf = CFURLCreateByResolvingBookmarkData(NULL, (CFDataRef)bookmark, 0, NULL, NULL, &cfStale, NULL);
    expect(cf != NULL && CFURLHasDirectoryPath(cf) == directory, [NSString stringWithFormat:@"CFURL: %@ resolves to %@", path, cf]);
    if (cf)
        CFRelease(cf);
}

int main(void)
{
    @autoreleasepool
    {
        char template[] = "/tmp/url-bookmark-directory.XXXXXX";
        char real[PATH_MAX];
        if (mkdtemp(template) == NULL || realpath(template, real) == NULL)
            return 2;
        NSString *dir = [NSString stringWithUTF8String:real];
        NSString *file = [dir stringByAppendingPathComponent:@"a.txt"];
        NSString *sub = [dir stringByAppendingPathComponent:@"sub"];
        [@"a" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:sub withIntermediateDirectories:NO attributes:nil error:NULL];

        roundTrip(file, NO);
        roundTrip(sub, YES);

        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
