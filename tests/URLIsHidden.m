// CFLAGS: -framework Foundation -fobjc-arc
// ARGS: "$(mktemp -d)/h"
// NSURLIsHiddenKey: what makes an item hidden, and what setting the key stores.
//
// Observed on macOS 10.14.4 and 26.7.3 (black-box, the same on both):
//  - a plain file is not hidden; a name starting with "." is;
//  - a file or folder whose com.apple.FinderInfo has kIsInvisible (Finder flags 0x4000, big endian at offset 8, so
//    byte 8 = 0x40) is hidden; kExtensionIsHidden alone (0x0010) does not make it hidden;
//  - UF_HIDDEN in st_flags makes it hidden;
//  - setResourceValue:@YES sets UF_HIDDEN and kIsInvisible (a new FinderInfo is otherwise all zeros).
// This test passes unchanged on both. Usage: URLIsHidden <new directory>.
#import <Foundation/Foundation.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <unistd.h>

static int failures;

static void expect(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static BOOL hidden(NSString *path)
{
    NSNumber *value = nil;
    [[NSURL fileURLWithPath: path] getResourceValue: &value forKey: NSURLIsHiddenKey error: NULL];
    return [value boolValue];
}

static NSString *make(NSString *dir, NSString *name, BOOL folder)
{
    NSString *path = [dir stringByAppendingPathComponent: name];
    if (folder)
        [[NSFileManager defaultManager] createDirectoryAtPath: path withIntermediateDirectories: NO attributes: nil error: NULL];
    else
        [[NSData data] writeToFile: path atomically: NO];
    return path;
}

static void setFinderInfo(NSString *path, unsigned char byte8, unsigned char byte9)
{
    unsigned char info[32] = { 0 };
    info[8] = byte8;
    info[9] = byte9;
    setxattr([path fileSystemRepresentation], "com.apple.FinderInfo", info, sizeof info, 0, XATTR_NOFOLLOW);
}

static ssize_t finderInfo(NSString *path, unsigned char *info)
{
    memset(info, 0, 32);
    return getxattr([path fileSystemRepresentation], "com.apple.FinderInfo", info, 32, 0, XATTR_NOFOLLOW);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: %s <new directory>\n", argv[0]);
            return 2;
        }
        NSString *dir = [NSString stringWithUTF8String: argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: NULL];

        expect("a plain file is not hidden", !hidden(make(dir, @"plain.txt", NO)));
        expect("a name starting with . is hidden", hidden(make(dir, @".dot", NO)));

        NSString *invisible = make(dir, @"invisible.txt", NO);
        setFinderInfo(invisible, 0x40, 0);
        expect("kIsInvisible in FinderInfo hides a file", hidden(invisible));
        NSString *invisibleFolder = make(dir, @"Invisible Folder", YES);
        setFinderInfo(invisibleFolder, 0x40, 0);
        expect("kIsInvisible in FinderInfo hides a folder", hidden(invisibleFolder));
        NSString *extension = make(dir, @"extension.txt", NO);
        setFinderInfo(extension, 0, 0x10);
        expect("kExtensionIsHidden alone does not hide", !hidden(extension));

        NSString *flagged = make(dir, @"flagged.txt", NO);
        if (chflags([flagged fileSystemRepresentation], UF_HIDDEN) == 0)
            expect("UF_HIDDEN hides", hidden(flagged));
        else
            printf("SKIP UF_HIDDEN hides: chflags fails here (%s)\n", strerror(errno));

        // Setting the key: kIsInvisible is set, the rest of the FinderInfo kept; clearing it clears the bit
        NSString *set = make(dir, @"set.txt", NO);
        setFinderInfo(set, 0, 0x10);
        NSError *error = nil;
        BOOL ok = [[NSURL fileURLWithPath: set] setResourceValue: @YES forKey: NSURLIsHiddenKey error: &error];
        unsigned char info[32];
        ssize_t length = finderInfo(set, info);
        expect("setResourceValue:@YES succeeds", ok);
        expect("and the item reads back as hidden", hidden(set));
        expect("FinderInfo now has kIsInvisible, and keeps kExtensionIsHidden",
              length == 32 && (info[8] & 0x40) != 0 && info[9] == 0x10);
        ok = [[NSURL fileURLWithPath: set] setResourceValue: @NO forKey: NSURLIsHiddenKey error: &error];
        length = finderInfo(set, info);
        expect("setResourceValue:@NO succeeds", ok);
        expect("and the item reads back as not hidden", !hidden(set));
        expect("FinderInfo has no kIsInvisible any more, and keeps kExtensionIsHidden",
              length == 32 && (info[8] & 0x40) == 0 && info[9] == 0x10);

        NSString *fresh = make(dir, @"fresh.txt", NO);
        ok = [[NSURL fileURLWithPath: fresh] setResourceValue: @YES forKey: NSURLIsHiddenKey error: &error];
        length = finderInfo(fresh, info);
        unsigned char expected[32] = { 0 };
        expected[8] = 0x40;
        expect("on an item without FinderInfo, setting makes one with only kIsInvisible",
              ok && length == 32 && memcmp(info, expected, 32) == 0);

        // Nothing can be stored for an item that doesn't exist
        error = nil;
        ok = [[NSURL fileURLWithPath: [dir stringByAppendingPathComponent: @"missing.txt"]] setResourceValue: @YES
                                                                                        forKey: NSURLIsHiddenKey
                                                                                         error: &error];
        expect("setting it on a missing item fails, with an error", !ok && error != nil);

        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
