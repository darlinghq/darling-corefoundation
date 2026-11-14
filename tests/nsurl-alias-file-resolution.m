// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: +[NSURL URLByResolvingAliasFileAtURL:options:error:] on items that
// are not alias files. Pins the QUIRK in CoreFoundation's NSURL.m.
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
    char tmpl[] = "/tmp/nsurl-alias.XXXXXX";
    char *dir = mkdtemp(tmpl);
    NSString *base = [NSString stringWithUTF8String: dir];
    NSString *file = [base stringByAppendingPathComponent: @"plain.txt"];
    NSString *link = [base stringByAppendingPathComponent: @"link"];
    NSString *absLink = [base stringByAppendingPathComponent: @"abslink"];
    NSString *missing = [base stringByAppendingPathComponent: @"missing"];
    [@"x" writeToFile: file atomically: NO encoding: NSUTF8StringEncoding error: NULL];
    symlink("plain.txt", [link fileSystemRepresentation]);
    symlink([file fileSystemRepresentation], [absLink fileSystemRepresentation]);

    NSError *error = [NSError errorWithDomain: @"unset" code: 1 userInfo: nil];
    NSURL *result = [NSURL URLByResolvingAliasFileAtURL: [NSURL fileURLWithPath: file] options: 0 error: &error];
    expect(result != nil && error == nil, @"a regular file resolves to itself without an error");
    expect([[result path] isEqualToString: file], @"the regular file's URL is returned");

    result = [NSURL URLByResolvingAliasFileAtURL: [NSURL fileURLWithPath: base] options: 0 error: &error];
    expect(result != nil && [[result path] isEqualToString: base], @"a directory resolves to itself");

    result = [NSURL URLByResolvingAliasFileAtURL: [NSURL fileURLWithPath: missing] options: 0 error: &error];
    expect(result != nil && [[result path] isEqualToString: missing] && error == nil, @"a missing item resolves to itself");

    result = [NSURL URLByResolvingAliasFileAtURL: [NSURL URLWithString: @"http://example.org/"] options: 0 error: &error];
    expect([[result absoluteString] isEqualToString: @"http://example.org/"], @"a non-file URL resolves to itself");

    // QUIRK tests: a symbolic link resolves to its target
    result = [NSURL URLByResolvingAliasFileAtURL: [NSURL fileURLWithPath: link] options: 0 error: &error];
    expect([[result path] isEqualToString: file], @"quirk: a symbolic link with a relative target resolves to the target");
    result = [NSURL URLByResolvingAliasFileAtURL: [NSURL fileURLWithPath: absLink] options: NSURLBookmarkResolutionWithoutUI error: &error];
    expect([[result path] isEqualToString: file], @"quirk: a symbolic link with an absolute target resolves to the target");

    result = [NSURL URLByResolvingAliasFileAtURL: [NSURL fileURLWithPath: file] options: 0 error: NULL];
    expect(result != nil, @"a NULL error pointer is accepted");

    unlink([link fileSystemRepresentation]);
    unlink([absLink fileSystemRepresentation]);
    unlink([file fileSystemRepresentation]);
    rmdir(dir);
    [pool drain];
    return failures ? 1 : 0;
}
