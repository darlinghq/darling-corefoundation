// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: promised item reachability and resource values, and the errors a
// reachability check reports (Cocoa file reading errors).
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

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    char tmpl[] = "/tmp/nsurl-promised.XXXXXX";
    char *dir = mkdtemp(tmpl);
    NSString *base = [NSString stringWithUTF8String: dir];
    NSString *file = [base stringByAppendingPathComponent: @"plain.txt"];
    NSString *missing = [base stringByAppendingPathComponent: @"missing"];
    [@"x" writeToFile: file atomically: NO encoding: NSUTF8StringEncoding error: NULL];
    NSURL *url = [NSURL fileURLWithPath: file];
    NSURL *gone = [NSURL fileURLWithPath: missing];

    NSError *error = nil;
    expect([url checkPromisedItemIsReachableAndReturnError: &error] && error == nil, @"an existing item is reachable");
    error = nil;
    expect(![gone checkPromisedItemIsReachableAndReturnError: &error], @"a missing item is not reachable");
    expect(error != nil && [[error domain] isEqualToString: NSCocoaErrorDomain] && [error code] == NSFileReadNoSuchFileError, @"the error is NSFileReadNoSuchFileError");
    expect([url checkPromisedItemIsReachableAndReturnError: NULL], @"a NULL error pointer is accepted");

    error = nil;
    expect(![gone checkResourceIsReachableAndReturnError: &error] && [error code] == NSFileReadNoSuchFileError, @"checkResourceIsReachable reports the same error");

    NSArray *keys = [NSArray arrayWithObjects: NSURLNameKey, NSURLIsDirectoryKey, nil];
    error = nil;
    NSDictionary *values = [url promisedItemResourceValuesForKeys: keys error: &error];
    expect(values != nil && error == nil, @"resource values of an existing item");
    expect([[values objectForKey: NSURLIsDirectoryKey] isEqual: [NSNumber numberWithBool: NO]], @"IsDirectory is NO for a file");
    expect([values objectForKey: NSURLNameKey] != nil, @"Name is present");

    error = nil;
    values = [gone promisedItemResourceValuesForKeys: keys error: &error];
    expect(values == nil && [error code] == NSFileReadNoSuchFileError, @"a missing item gives nil and NSFileReadNoSuchFileError");

    unlink([file fileSystemRepresentation]);
    rmdir(dir);
    [pool drain];
    return failures ? 1 : 0;
}
