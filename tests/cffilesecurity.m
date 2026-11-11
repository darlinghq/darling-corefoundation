// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: CFFileSecurity stores owner/group/mode, and NSURLFileSecurityKey
// reads the file's POSIX state and applies mode (including setuid) on write.
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
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
        CFFileSecurityRef sec = CFFileSecurityCreate(NULL);
        mode_t mode = 0;
        uid_t uid = 0;
        check("fresh object has no mode", !CFFileSecurityGetMode(sec, &mode));
        check("fresh object has no owner", !CFFileSecurityGetOwner(sec, &uid));
        CFFileSecuritySetMode(sec, 04755);
        check("mode round trip with setuid", CFFileSecurityGetMode(sec, &mode) && mode == 04755);
        CFFileSecurityRef copy = CFFileSecurityCreateCopy(NULL, sec);
        check("copy keeps mode", copy && CFFileSecurityGetMode(copy, &mode) && mode == 04755);
        CFFileSecurityClearProperties(sec, kCFFileSecurityClearMode);
        check("cleared mode is absent", !CFFileSecurityGetMode(sec, &mode));
        CFRelease(copy);
        CFRelease(sec);

        char temp[] = "/tmp/darling-filesec-XXXXXX";
        char *root = mkdtemp(temp);
        if (!root)
            return 2;
        NSString *file = [[NSString stringWithUTF8String:root] stringByAppendingPathComponent:@"f"];
        int fd = open([file fileSystemRepresentation], O_CREAT | O_EXCL | O_WRONLY, 0600);
        if (fd < 0)
            return 2;
        close(fd);

        CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:file];
        CFTypeRef value = NULL;
        check("read NSURLFileSecurityKey",
              CFURLCopyResourcePropertyForKey(url, CFSTR("NSURLFileSecurityKey"), &value, NULL) && value);
        check("read mode matches stat", value && CFFileSecurityGetMode((CFFileSecurityRef)value, &mode) && mode == 0600);
        if (value)
            CFRelease(value);

        CFFileSecurityRef set = CFFileSecurityCreate(NULL);
        CFFileSecuritySetMode(set, 04750);
        check("write NSURLFileSecurityKey",
              CFURLSetResourcePropertyForKey(url, CFSTR("NSURLFileSecurityKey"), set, NULL));
        CFRelease(set);
        struct stat st;
        check("file mode updated incl. setuid", stat([file fileSystemRepresentation], &st) == 0 && (st.st_mode & 07777) == 04750);

        unlink([file fileSystemRepresentation]);
        rmdir(root);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
