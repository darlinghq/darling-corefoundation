// NSURLIsVolumeKey, NSURLParentDirectoryURLKey, NSURLFileResourceIdentifierKey and NSURLVolumeIsReadOnlyKey, as
// documented in the Foundation reference for URLResourceKey (developer.apple.com/documentation/foundation/urlresourcekey):
// - isVolumeKey: a Boolean NSNumber, YES for the top directory of a volume;
// - parentDirectoryURLKey: the directory that contains the resource; there is none (nil) for a volume's top directory;
// - fileResourceIdentifierKey: values compare equal with isEqual: for the same path, and for two paths that reach one
//   inode of one file system (hard links);
// - volumeIsReadOnlyKey: a Boolean NSNumber telling whether the volume is read-only.
// A missing item is a read error, NSCocoaErrorDomain 260 (NSFileReadNoSuchFileError).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/statvfs.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static id Value(NSURL *url, NSString *key) {
    id value = nil;
    NSError *error = nil;
    if (![url getResourceValue: &value forKey: key error: &error]) {
        fprintf(stderr, "FAIL reading %s of %s\n", [key UTF8String], [[url path] UTF8String]);
        failures++;
        return nil;
    }
    return value;
}

static void CheckMissing(NSURL *url, NSString *key) {
    id value = nil;
    NSError *error = nil;
    CHECK(![url getResourceValue: &value forKey: key error: &error]);
    CHECK([[error domain] isEqualToString: @"NSCocoaErrorDomain"]);
    CHECK([error code] == 260);
}

int main(void) {
    @autoreleasepool {
        char tmpl[] = "/tmp/nsurlvolume.XXXXXX";
        if (mkdtemp(tmpl) == NULL)
            return 2;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [fm stringWithFileSystemRepresentation: tmpl length: strlen(tmpl)];
        NSString *file = [dir stringByAppendingPathComponent: @"a.txt"];
        NSString *other = [dir stringByAppendingPathComponent: @"b.txt"];
        NSString *hardLink = [dir stringByAppendingPathComponent: @"a-link.txt"];
        NSString *folder = [dir stringByAppendingPathComponent: @"folder"];
        NSString *missing = [dir stringByAppendingPathComponent: @"missing.txt"];
        [fm createFileAtPath: file contents: [NSData dataWithBytes: "abcd" length: 4] attributes: nil];
        [fm createFileAtPath: other contents: [NSData dataWithBytes: "abcd" length: 4] attributes: nil];
        [fm createDirectoryAtPath: folder withIntermediateDirectories: YES attributes: nil error: NULL];
        CHECK(link([file fileSystemRepresentation], [hardLink fileSystemRepresentation]) == 0);

        NSURL *root = [NSURL fileURLWithPath: @"/" isDirectory: YES];
        NSURL *fileURL = [NSURL fileURLWithPath: file];
        NSURL *folderURL = [NSURL fileURLWithPath: folder isDirectory: YES];

        // NSURLIsVolumeKey
        CHECK([Value(root, NSURLIsVolumeKey) isEqual: @YES]);
        CHECK([Value(fileURL, NSURLIsVolumeKey) isEqual: @NO]);
        CHECK([Value(folderURL, NSURLIsVolumeKey) isEqual: @NO]);
        CheckMissing([NSURL fileURLWithPath: missing], NSURLIsVolumeKey);

        // NSURLParentDirectoryURLKey
        CHECK(Value(root, NSURLParentDirectoryURLKey) == nil);
        NSURL *parent = Value(fileURL, NSURLParentDirectoryURLKey);
        CHECK([[parent path] isEqualToString: dir]);
        CHECK([[Value(folderURL, NSURLParentDirectoryURLKey) path] isEqualToString: dir]);

        // NSURLFileResourceIdentifierKey
        id identifier = Value(fileURL, NSURLFileResourceIdentifierKey);
        CHECK(identifier != nil);
        CHECK([identifier isEqual: Value([NSURL fileURLWithPath: file], NSURLFileResourceIdentifierKey)]);
        CHECK([identifier isEqual: Value([NSURL fileURLWithPath: hardLink], NSURLFileResourceIdentifierKey)]);
        CHECK(![identifier isEqual: Value([NSURL fileURLWithPath: other], NSURLFileResourceIdentifierKey)]);
        CHECK(![identifier isEqual: Value(folderURL, NSURLFileResourceIdentifierKey)]);
        CheckMissing([NSURL fileURLWithPath: missing], NSURLFileResourceIdentifierKey);

        // NSURLVolumeIsReadOnlyKey: the directory was just written to, so its volume is not read-only. The value
        // must also follow the volume's flag for these well-known directories, so that a constant answer fails
        // wherever one of them is on a read-only volume (if none is on this machine, only the NO case runs).
        CHECK([Value(fileURL, NSURLVolumeIsReadOnlyKey) isEqual: @NO]);
        for (NSString *known in @[@"/", @"/usr", @"/bin", @"/System", @"/boot", @"/cdrom"]) {
            struct statvfs vfs;
            if (statvfs([known fileSystemRepresentation], &vfs) != 0)
                continue;
            BOOL readOnly = (vfs.f_flag & ST_RDONLY) != 0;
            CHECK([Value([NSURL fileURLWithPath: known isDirectory: YES], NSURLVolumeIsReadOnlyKey) isEqual: @(readOnly)]);
        }
        CheckMissing([NSURL fileURLWithPath: missing], NSURLVolumeIsReadOnlyKey);

        NSDictionary *values = [fileURL resourceValuesForKeys: @[NSURLIsVolumeKey, NSURLVolumeIsReadOnlyKey] error: NULL];
        CHECK([[values objectForKey: NSURLIsVolumeKey] isEqual: @NO]);
        CHECK([[values objectForKey: NSURLVolumeIsReadOnlyKey] isEqual: @NO]);

        for (NSString *name in [fm contentsOfDirectoryAtPath: dir error: NULL])
            [fm removeItemAtPath: [dir stringByAppendingPathComponent: name] error: NULL];
        rmdir(tmpl);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
