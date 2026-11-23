// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: the value that -[NSURL getResourceValue:forKey:error:] hands out stays valid after the
// URL object is released (the out value is autoreleased, as for any Foundation out parameter), and
// CFURLCopyResourcePropertyForKey follows the Copy rule (the caller owns the value and releases it).
// A temporary value is used because only the URL's resource cache references it, so a value that is
// handed out without its own reference dies with the URL.
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
    CFIndex firstCount = cfValue ? CFGetRetainCount(cfValue) : 0;
    expect(firstCount >= 2, @"the value is owned by the caller and by the URL's cache");
    if (cfValue)
        CFRelease(cfValue);

    CFTypeRef second = NULL;
    ok = CFURLCopyResourcePropertyForKey((CFURLRef)url, kCFURLContentModificationDateKey, &second, NULL);
    expect(ok && second != NULL && CFGetTypeID(second) == CFDateGetTypeID(), @"a second read after the caller's release still returns a live date");
    if (second)
        CFRelease(second);
    ok = CFURLCopyResourcePropertyForKey((CFURLRef)url, kCFURLContentModificationDateKey, NULL, NULL);
    expect(ok, @"a NULL out pointer is accepted");

    // With a NULL out pointer nobody receives the value, so no reference may be left behind:
    // the tracked value dies with the URL.
    int before = trackerDeallocs;
    Tracker *unread = [[Tracker alloc] init];
    [url setTemporaryResourceValue: unread forKey: key];
    [unread release];
    ok = CFURLCopyResourcePropertyForKey((CFURLRef)url, (CFStringRef)key, NULL, NULL);
    expect(ok, @"a tracked value is read with a NULL out pointer");
    [url release];
    expect(trackerDeallocs == before + 1, @"a read with a NULL out pointer does not leak a reference");

    unlink([path fileSystemRepresentation]);
    rmdir(dir);
    [pool drain];
    printf("%d failures\n", failures);
    return failures != 0;
}
