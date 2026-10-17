// Run linked against the candidate Foundation/CoreFoundation runtime.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

// Not the generic NSFileWriteUnknownError (512), and ENOENT is the error or sits underneath it: this
// runtime reports NSPOSIXErrorDomain/ENOENT directly, Apple's reports NSCocoaErrorDomain 4 with the
// POSIX error as NSUnderlyingErrorKey.
static BOOL isMissingFileError(NSError *error) {
    if (error == nil || [error code] == 512) return NO;
    if ([[error domain] isEqual:NSPOSIXErrorDomain] && [error code] == ENOENT) return YES;
    NSError *underlying = [[error userInfo] objectForKey:NSUnderlyingErrorKey];
    return [[underlying domain] isEqual:NSPOSIXErrorDomain] && [underlying code] == ENOENT;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *dir = [NSString stringWithFormat:@"/tmp/collections-write-to-url-%d", (int)getpid()];
    assert([[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]);

    NSArray *array = @[@"one", @2, @[@"nested"]];
    NSDictionary *dictionary = @{@"key": @"value", @"list": array};

    // success: the file round-trips and no error is set
    NSURL *arrayURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"array.plist"]];
    NSURL *dictionaryURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"dictionary.plist"]];
    NSError *error = nil;
    assert([array writeToURL:arrayURL error:&error]);
    assert(error == nil);
    assert([[NSArray arrayWithContentsOfURL:arrayURL] isEqual:array]);
    assert([dictionary writeToURL:dictionaryURL error:&error]);
    assert(error == nil);
    assert([[NSDictionary dictionaryWithContentsOfURL:dictionaryURL] isEqual:dictionary]);

    // an unwritable location reports the real cause, not a generic unknown-write error
    NSURL *missing = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"no-such-dir/out.plist"]];
    error = nil;
    assert(![array writeToURL:missing error:&error]);
    assert(error != nil);
    assert(isMissingFileError(error));
    error = nil;
    assert(![dictionary writeToURL:missing error:&error]);
    assert(isMissingFileError(error));

    // content that is not a property list fails without touching the file system
    NSURL *invalidURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"invalid.plist"]];
    error = nil;
    assert(![@[[NSObject new]] writeToURL:invalidURL error:&error]);
    assert([[error domain] isEqual:NSCocoaErrorDomain] && [error code] == 3852);
    assert(![[NSFileManager defaultManager] fileExistsAtPath:[invalidURL path]]);

    // a NULL error pointer is allowed
    assert(![array writeToURL:missing error:NULL]);
    assert([array writeToURL:arrayURL error:NULL]);

    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    [pool drain];
    puts("PASS: writeToURL:error: for NSArray and NSDictionary reports the real error");
    return 0;
}
