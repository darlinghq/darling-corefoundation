// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: the value that -[NSURL getResourceValue:forKey:error:] hands out stays valid after the
// URL object is released (the out value is autoreleased, as for any Foundation out parameter), and
// CFURLCopyResourcePropertyForKey follows the Copy rule (the caller owns the value and releases it).
// A temporary value is used because only the URL's resource cache references it, so a value that is
// handed out without its own reference dies with the URL.
// Checked on macOS 10.14.4 and 26.7.3 (both pass): the value is alive after the URL is released, and a caller's release
// leaves the cached value alone. A NULL out pointer for CFURLCopyResourcePropertyForKey is not allowed on macOS (it
// crashes there), so the test does not pass one; the retain count of a date is not pinned either (it is 1 for the
// caller's reference on macOS 10.14.4).
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
static int trackerDeallocs;
static void expect(BOOL condition, NSString *label)
{
    printf("%s %s\n", condition ? "PASS" : "FAIL", [label UTF8String]);
    failures += !condition;
}

@interface Tracker : NSObject
@end
@implementation Tracker
- (void)dealloc
{
    trackerDeallocs++;
    [super dealloc];
}
@end

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    char tmpl[] = "/tmp/nsurl-value-owner.XXXXXX";
    char *dir = mkdtemp(tmpl);
    NSString *path = [[NSString stringWithUTF8String: dir] stringByAppendingPathComponent: @"file.txt"];
    [@"x" writeToFile: path atomically: NO encoding: NSUTF8StringEncoding error: NULL];
    NSString *key = @"OwnershipTestKey";

    // Objective-C: the value outlives the URL until the autorelease pool is drained.
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    NSURL *url = [[NSURL alloc] initFileURLWithPath: path];
    Tracker *tracker = [[Tracker alloc] init];
    [url setTemporaryResourceValue: tracker forKey: key];
    [tracker release];
    id value = nil;
    BOOL ok = [url getResourceValue: &value forKey: key error: NULL];
    expect(ok && value != nil, @"getResourceValue: returns the temporary value");
    [url release];
    expect(trackerDeallocs == 0, @"the value is still alive after the URL is released");
    [inner drain];
    expect(trackerDeallocs == 1, @"the value is released when the autorelease pool is drained");

    // The date of the file is a value the URL creates itself, and it must survive the URL too.
    id date = nil;
    inner = [[NSAutoreleasePool alloc] init];
    url = [[NSURL alloc] initFileURLWithPath: path];
    ok = [url getResourceValue: &date forKey: NSURLContentModificationDateKey error: NULL];
    [url release];
    expect(ok && [date isKindOfClass: [NSDate class]] && [(NSDate *)date timeIntervalSince1970] > 0, @"a computed date outlives the URL");
    [inner drain];

    // Core Foundation: the caller owns the value, so one release leaves the URL's cached copy alone.
    url = [[NSURL alloc] initFileURLWithPath: path];
    CFTypeRef cfValue = NULL;
    ok = CFURLCopyResourcePropertyForKey((CFURLRef)url, kCFURLContentModificationDateKey, &cfValue, NULL);
    expect(ok && cfValue != NULL, @"CFURLCopyResourcePropertyForKey returns a date");
    if (cfValue)
        CFRelease(cfValue);

    CFTypeRef second = NULL;
    ok = CFURLCopyResourcePropertyForKey((CFURLRef)url, kCFURLContentModificationDateKey, &second, NULL);
    expect(ok && second != NULL && CFGetTypeID(second) == CFDateGetTypeID(), @"a second read after the caller's release still returns a live date");
    if (second)
        CFRelease(second);

    // The caller's release of a tracked value leaves the URL's reference: it dies with the URL, not before.
    int before = trackerDeallocs;
    Tracker *held = [[Tracker alloc] init];
    [url setTemporaryResourceValue: held forKey: key];
    [held release];
    CFTypeRef trackedValue = NULL;
    ok = CFURLCopyResourcePropertyForKey((CFURLRef)url, (CFStringRef)key, &trackedValue, NULL);
    expect(ok && trackedValue != NULL, @"a tracked value is read");
    if (trackedValue)
        CFRelease(trackedValue);
    expect(trackerDeallocs == before, @"the caller's release does not free the value the URL holds");
    [url release];
    expect(trackerDeallocs == before + 1, @"the value dies with the URL, with no reference left behind");

    unlink([path fileSystemRepresentation]);
    rmdir(dir);
    [pool drain];
    printf("%d failures\n", failures);
    return failures != 0;
}
