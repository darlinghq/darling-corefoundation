// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: NSURL file dates are reported on the CF reference-date scale
// (not as Unix timestamps) and NSURLFileSizeKey returns the byte size.
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <math.h>
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
        char temp[] = "/tmp/darling-url-dates-XXXXXX";
        char *root = mkdtemp(temp);
        if (!root)
            return 2;
        NSString *file = [[NSString stringWithUTF8String:root] stringByAppendingPathComponent:@"f"];
        int fd = open([file fileSystemRepresentation], O_CREAT | O_EXCL | O_WRONLY, 0600);
        if (fd < 0)
            return 2;
        write(fd, "hello world", 11);
        close(fd);

        NSURL *url = [NSURL fileURLWithPath:file];
        NSError *error = nil;
        NSDictionary *values = [url resourceValuesForKeys:@[NSURLContentModificationDateKey,
                                                            NSURLCreationDateKey,
                                                            NSURLContentAccessDateKey,
                                                            NSURLFileSizeKey] error:&error];
        check("resource values returned", values != nil && error == nil);

        NSDate *now = [NSDate date];
        for (NSString *key in @[NSURLContentModificationDateKey, NSURLCreationDateKey, NSURLContentAccessDateKey]) {
            NSDate *d = values[key];
            // A just-created file must be within a minute of now; a Unix
            // timestamp read as CF absolute time would be ~31 years early.
            check([key UTF8String], [d isKindOfClass:[NSDate class]] && fabs([d timeIntervalSinceDate:now]) < 60.0);
        }
        check("NSURLFileSizeKey", [values[NSURLFileSizeKey] longLongValue] == 11);

        unlink([file fileSystemRepresentation]);
        rmdir(root);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
