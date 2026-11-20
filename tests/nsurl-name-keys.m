// Copyright (C) 2026 Lubos Dolezel
//
// NSURLNameKey is the item's file-system name as it is, extension included; NSURLLocalizedNameKey is the same name
// unless the item has the extension-hidden flag. Both fail for a missing item with NSCocoaErrorDomain 260
// (NSFileReadNoSuchFileError). Observed on macOS 26.7.3 (x86_64) and macOS 10.14.4, identical on both: "t.mp3" for a
// file t.mp3, "folder" for a directory, "lnk" for a symbolic link (also a dangling one is not looked through).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void CheckName(NSURL *url, NSString *key, NSString *expected) {
    id value = nil;
    NSError *error = nil;
    BOOL ok = [url getResourceValue: &value forKey: key error: &error];
    if (!ok || ![value isEqual: expected]) {
        fprintf(stderr, "FAIL %s of %s: ok=%d value=%s want %s\n", [key UTF8String], [[url path] UTF8String], (int) ok,
                value ? [[value description] UTF8String] : "(nil)", [expected UTF8String]);
        failures++;
    }
}

static void CheckMissing(NSURL *url, NSString *key) {
    id value = nil;
    NSError *error = nil;
    BOOL ok = [url getResourceValue: &value forKey: key error: &error];
    CHECK(!ok);
    CHECK([[error domain] isEqualToString: @"NSCocoaErrorDomain"]);
    CHECK([error code] == 260);
}

int main(void) {
    @autoreleasepool {
        char tmpl[] = "/tmp/nsurlname.XXXXXX";
        if (mkdtemp(tmpl) == NULL)
            return 2;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [fm stringWithFileSystemRepresentation: tmpl length: strlen(tmpl)];
        NSString *file = [dir stringByAppendingPathComponent: @"t.mp3"];
        NSString *folder = [dir stringByAppendingPathComponent: @"folder"];
        NSString *link = [dir stringByAppendingPathComponent: @"lnk"];
        NSString *dangling = [dir stringByAppendingPathComponent: @"dangling.flac"];
        NSString *missing = [dir stringByAppendingPathComponent: @"missing.mp3"];
        [fm createFileAtPath: file contents: [NSData dataWithBytes: "abcd" length: 4] attributes: nil];
        [fm createDirectoryAtPath: folder withIntermediateDirectories: YES attributes: nil error: NULL];
        [fm createSymbolicLinkAtPath: link withDestinationPath: folder error: NULL];
        [fm createSymbolicLinkAtPath: dangling withDestinationPath: missing error: NULL];

        for (NSString *key in @[NSURLNameKey, NSURLLocalizedNameKey]) {
            CheckName([NSURL fileURLWithPath: file], key, @"t.mp3");
            CheckName([NSURL fileURLWithPath: folder], key, @"folder");
            CheckName([NSURL fileURLWithPath: link], key, @"lnk");
            CheckName([NSURL fileURLWithPath: dangling], key, @"dangling.flac");
            CheckMissing([NSURL fileURLWithPath: missing], key);
        }

        NSDictionary *values = [[NSURL fileURLWithPath: file] resourceValuesForKeys: @[NSURLNameKey] error: NULL];
        CHECK([[values objectForKey: NSURLNameKey] isEqual: @"t.mp3"]);

        for (NSString *name in [fm contentsOfDirectoryAtPath: dir error: NULL])
            [fm removeItemAtPath: [dir stringByAppendingPathComponent: name] error: NULL];
        rmdir(tmpl);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
