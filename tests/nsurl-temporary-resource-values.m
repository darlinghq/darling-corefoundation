// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: temporary resource values of an NSURL (-setTemporaryResourceValue:forKey:,
// -removeCachedResourceValueForKey:, -removeAllCachedResourceValues).
// Pins the QUIRK in CoreFoundation's NSURL.m: values are kept only for file URLs.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
static void expect(BOOL condition, NSString *label)
{
    printf("%s %s\n", condition ? "PASS" : "FAIL", [label UTF8String]);
    failures += !condition;
}

static id value(NSURL *url, NSString *key)
{
    id v = nil;
    [url getResourceValue: &v forKey: key error: NULL];
    return v;
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    char tmpl[] = "/tmp/nsurl-temp-values.XXXXXX";
    char *dir = mkdtemp(tmpl);
    NSString *path = [[NSString stringWithUTF8String: dir] stringByAppendingPathComponent: @"file.txt"];
    [@"x" writeToFile: path atomically: NO encoding: NSUTF8StringEncoding error: NULL];

    NSURL *url = [NSURL fileURLWithPath: path];
    expect(value(url, @"TestCustomKey") == nil, @"unset custom key reads as nil");
    id v = nil;
    NSError *error = nil;
    expect([url getResourceValue: &v forKey: @"TestCustomKey" error: &error] && error == nil, @"unset custom key reads successfully, without an error");

    [url setTemporaryResourceValue: @"custom" forKey: @"TestCustomKey"];
    expect([value(url, @"TestCustomKey") isEqual: @"custom"], @"temporary value is returned for a custom key");
    expect([[url resourceValuesForKeys: [NSArray arrayWithObject: @"TestCustomKey"] error: NULL] objectForKey: @"TestCustomKey"] != nil, @"temporary value is part of resourceValuesForKeys:");

    [url setTemporaryResourceValue: [NSNumber numberWithInt: 3] forKey: @"TestCustomKey"];
    expect([value(url, @"TestCustomKey") isEqual: [NSNumber numberWithInt: 3]], @"setting again replaces the value");

    NSURL *other = [NSURL fileURLWithPath: path];
    expect(value(other, @"TestCustomKey") == nil, @"another object for the same path does not see the value");

    // A key the system provides keeps its computed value
    NSURL *fresh = [NSURL fileURLWithPath: path];
    [fresh setTemporaryResourceValue: @"Renamed" forKey: NSURLNameKey];
    expect([value(fresh, NSURLNameKey) isEqual: @"file"] || [value(fresh, NSURLNameKey) isEqual: @"file.txt"], @"a temporary value does not replace a computed one");

    [url removeCachedResourceValueForKey: @"TestCustomKey"];
    expect(value(url, @"TestCustomKey") == nil, @"removeCachedResourceValueForKey: drops the temporary value");

    [url setTemporaryResourceValue: @"a" forKey: @"TestCustomKey"];
    [url setTemporaryResourceValue: @"b" forKey: @"TestCustomKey2"];
    [url removeAllCachedResourceValues];
    expect(value(url, @"TestCustomKey") == nil && value(url, @"TestCustomKey2") == nil, @"removeAllCachedResourceValues drops all temporary values");

    // QUIRK test: values set on a URL that is not a file URL are not kept
    NSURL *remote = [NSURL URLWithString: @"http://example.org/q"];
    [remote setTemporaryResourceValue: @"v" forKey: @"TestCustomKey"];
    expect(value(remote, @"TestCustomKey") == nil, @"quirk: a non-file URL keeps no temporary value");

    unlink([path fileSystemRepresentation]);
    rmdir(dir);
    [pool drain];
    return failures ? 1 : 0;
}
