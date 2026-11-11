// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: bookmark data round-trips a file URL, reachability follows the
// file's existence, and the security-scoped calls succeed.
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
static void check(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool {
        char temp[] = "/tmp/darling-bookmark-XXXXXX";
        char *root = mkdtemp(temp);
        if (!root)
            return 2;
        NSString *file = [[NSString stringWithUTF8String:root] stringByAppendingPathComponent:@"f"];
        close(open([file fileSystemRepresentation], O_CREAT | O_WRONLY, 0600));
        NSURL *url = [NSURL fileURLWithPath:file];

        NSError *error = nil;
        NSData *data = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
        check("bookmark data created", data != nil);
        BOOL stale = YES;
        NSURL *resolved = [NSURL URLByResolvingBookmarkData:data options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
        check("bookmark resolves to the same path", [[resolved path] isEqualToString:file]);
        check("bookmark not stale", !stale);
        check("existing file reachable", [url checkResourceIsReachableAndReturnError:NULL]);
        check("scoped start", [url startAccessingSecurityScopedResource]);
        [url stopAccessingSecurityScopedResource];

        unlink([file fileSystemRepresentation]);
        check("removed file not reachable", ![url checkResourceIsReachableAndReturnError:NULL]);
        rmdir(root);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
