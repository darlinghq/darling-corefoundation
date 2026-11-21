// Bookmark data (NSURL bookmarkDataWithOptions:..., +URLByResolvingBookmarkData:..., +resourceValuesForKeys:fromBookmarkData:),
// from the Foundation reference for NSURL (developer.apple.com/documentation/foundation/nsurl):
// - the data is made from an item; the resource values asked for are stored and can be read back from the data
//   without resolving it (resourceValuesForKeys:fromBookmarkData:);
// - with relativeToURL the data is relative to that URL, and resolving relative to another URL finds the item
//   in the same place below it;
// - a URL that is not a file URL gives data holding only the URL;
// - failure returns nil with an error.
// Not from the documentation (the reference is silent), so these lines pin this implementation's choices (GUESS):
// the item is missing -> NSCocoaErrorDomain 260, on creating and on resolving; another file (another inode) at the
// path -> resolves and is stale; data that is not bookmark data -> nil with an error; a relative bookmark is made
// for an item below the URL given, taken as a directory.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <limits.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        char tmpl[] = "/tmp/nsurlbookmark.XXXXXX";
        if (mkdtemp(tmpl) == NULL)
            return 2;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [fm stringWithFileSystemRepresentation: tmpl length: strlen(tmpl)];
        NSString *docs = [dir stringByAppendingPathComponent: @"docs"];
        NSString *sub = [docs stringByAppendingPathComponent: @"sub"];
        NSString *file = [sub stringByAppendingPathComponent: @"f.txt"];
        [fm createDirectoryAtPath: sub withIntermediateDirectories: YES attributes: nil error: NULL];
        [fm createFileAtPath: file contents: [NSData dataWithBytes: "abcd" length: 4] attributes: nil];
        NSURL *fileURL = [NSURL fileURLWithPath: file];
        NSURL *subURL = [NSURL fileURLWithPath: sub isDirectory: YES];
        NSError *error = nil;
        BOOL stale = YES;

        // Round trip, a file and a directory.
        NSData *data = [fileURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: nil error: &error];
        CHECK(data != nil);
        NSURL *resolved = [NSURL URLByResolvingBookmarkData: data options: 0 relativeToURL: nil bookmarkDataIsStale: &stale error: &error];
        CHECK([[resolved path] isEqualToString: file]);
        CHECK(!stale);
        NSData *dirData = [subURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: nil error: NULL];
        NSURL *dirResolved = [NSURL URLByResolvingBookmarkData: dirData options: 0 relativeToURL: nil bookmarkDataIsStale: NULL error: NULL];
        CHECK([[dirResolved path] isEqualToString: sub]);
        CHECK([dirResolved hasDirectoryPath]);

        // Resource values are read back from the data, also once the item is gone.
        NSData *withValues = [fileURL bookmarkDataWithOptions: 0
                                includingResourceValuesForKeys: @[NSURLNameKey, NSURLFileSizeKey, NSURLParentDirectoryURLKey]
                                                 relativeToURL: nil error: &error];
        NSDictionary *stored = [NSURL resourceValuesForKeys: @[NSURLNameKey, NSURLFileSizeKey, NSURLParentDirectoryURLKey, NSURLIsDirectoryKey]
                                            fromBookmarkData: withValues];
        CHECK([[stored objectForKey: NSURLNameKey] isEqual: @"f.txt"]);
        CHECK([[stored objectForKey: NSURLFileSizeKey] isEqual: @4]);
        CHECK([[[stored objectForKey: NSURLParentDirectoryURLKey] path] isEqualToString: sub]);
        CHECK([stored objectForKey: NSURLIsDirectoryKey] == nil);

        // Relative to a URL: the directory moves, the item is found in the same place below the new location.
        NSURL *docsURL = [NSURL fileURLWithPath: docs isDirectory: YES];
        NSData *relativeData = [fileURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: docsURL error: &error];
        CHECK(relativeData != nil);
        NSString *moved = [dir stringByAppendingPathComponent: @"moved"];
        CHECK([fm moveItemAtPath: docs toPath: moved error: NULL]);
        NSURL *movedURL = [NSURL fileURLWithPath: moved isDirectory: YES];
        stale = YES;
        resolved = [NSURL URLByResolvingBookmarkData: relativeData options: 0 relativeToURL: movedURL bookmarkDataIsStale: &stale error: &error];
        CHECK([[resolved path] isEqualToString: [moved stringByAppendingPathComponent: @"sub/f.txt"]]);
        CHECK(!stale);
        file = [moved stringByAppendingPathComponent: @"sub/f.txt"];
        fileURL = [NSURL fileURLWithPath: file];

        // Another file at the path: the data resolves, and is stale.
        data = [fileURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: nil error: NULL];
        NSString *kept = [file stringByAppendingString: @".old"];
        CHECK([fm moveItemAtPath: file toPath: kept error: NULL]);
        [fm createFileAtPath: file contents: [NSData data] attributes: nil];
        stale = NO;
        resolved = [NSURL URLByResolvingBookmarkData: data options: 0 relativeToURL: nil bookmarkDataIsStale: &stale error: NULL];
        CHECK([[resolved path] isEqualToString: file]);
        CHECK(stale);

        // Two candidates: the relative path finds another file while the original is still at the absolute path;
        // the one with the recorded identity is the item.
        NSString *old = [dir stringByAppendingPathComponent: @"pick-old.txt"];
        NSString *shadowDir = [dir stringByAppendingPathComponent: @"shadow"];
        [fm createFileAtPath: old contents: [NSData data] attributes: nil];
        [fm createDirectoryAtPath: shadowDir withIntermediateDirectories: YES attributes: nil error: NULL];
        [fm createFileAtPath: [shadowDir stringByAppendingPathComponent: @"pick-old.txt"] contents: [NSData data] attributes: nil];
        NSURL *pickBase = [NSURL fileURLWithPath: dir isDirectory: YES];
        NSData *pickData = [[NSURL fileURLWithPath: old] bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil
                                                                    relativeToURL: pickBase error: NULL];
        stale = YES;
        resolved = [NSURL URLByResolvingBookmarkData: pickData options: 0 relativeToURL: [NSURL fileURLWithPath: shadowDir isDirectory: YES]
                                 bookmarkDataIsStale: &stale error: NULL];
        CHECK([[resolved path] isEqualToString: old]);
        CHECK(!stale);

        // A missing item.
        [fm removeItemAtPath: file error: NULL];
        resolved = [NSURL URLByResolvingBookmarkData: data options: 0 relativeToURL: nil bookmarkDataIsStale: NULL error: &error];
        CHECK(resolved == nil);
        CHECK([[error domain] isEqualToString: NSCocoaErrorDomain] && [error code] == 260);
        error = nil;
        CHECK([fileURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: nil error: &error] == nil);
        CHECK([[error domain] isEqualToString: NSCocoaErrorDomain] && [error code] == 260);

        // A URL that is not a file URL.
        NSURL *web = [NSURL URLWithString: @"https://example.com/a?b=c"];
        data = [web bookmarkDataWithOptions: 0 includingResourceValuesForKeys: @[NSURLNameKey] relativeToURL: nil error: &error];
        CHECK(data != nil);
        resolved = [NSURL URLByResolvingBookmarkData: data options: 0 relativeToURL: nil bookmarkDataIsStale: NULL error: &error];
        CHECK([[resolved absoluteString] isEqualToString: @"https://example.com/a?b=c"]);

        // Data that is not bookmark data, or is damaged or forged: nil with an error, never a crash.
        NSMutableArray *bad = [NSMutableArray array];
        [bad addObject: [NSData dataWithBytes: "xyz" length: 3]];
        [bad addObject: [NSData dataWithBytes: "DLBK" length: 4]];
        [bad addObject: [NSData dataWithBytes: "DLBKnot a property list" length: 23]];
        for (id wrongPath in @[@5, @[@"a"], @{@"a": @1}]) {
            NSData *list = [NSPropertyListSerialization dataWithPropertyList: @{@"path": wrongPath}
                                                                      format: NSPropertyListBinaryFormat_v1_0 options: 0 error: NULL];
            NSMutableData *forged = [NSMutableData dataWithBytes: "DLBK" length: 4];
            [forged appendData: list];
            [bad addObject: forged];
        }
        NSData *noPath = [NSPropertyListSerialization dataWithPropertyList: @{@"inode": @1}
                                                                    format: NSPropertyListBinaryFormat_v1_0 options: 0 error: NULL];
        NSMutableData *noPathData = [NSMutableData dataWithBytes: "DLBK" length: 4];
        [noPathData appendData: noPath];
        [bad addObject: noPathData];
        for (NSData *item in bad) {
            error = nil;
            resolved = [NSURL URLByResolvingBookmarkData: item options: 0 relativeToURL: nil bookmarkDataIsStale: NULL error: &error];
            CHECK(resolved == nil && error != nil);
            CHECK([NSURL resourceValuesForKeys: @[NSURLNameKey] fromBookmarkData: item] == nil);
        }

        // A valid path with values of the wrong types around it: values of the wrong type are ignored.
        NSString *real = [dir stringByAppendingPathComponent: @"real.txt"];
        [fm createFileAtPath: real contents: [NSData data] attributes: nil];
        NSDictionary *forgedRecord = @{@"path": real, @"inode": @"x", @"relativePath": @7, @"resourceValues": @9};
        NSMutableData *forgedData = [NSMutableData dataWithBytes: "DLBK" length: 4];
        [forgedData appendData: [NSPropertyListSerialization dataWithPropertyList: forgedRecord
                                                                           format: NSPropertyListBinaryFormat_v1_0 options: 0 error: NULL]];
        stale = YES;
        resolved = [NSURL URLByResolvingBookmarkData: forgedData options: 0 relativeToURL: movedURL bookmarkDataIsStale: &stale error: NULL];
        CHECK([[resolved path] isEqualToString: real]);
        CHECK(!stale);
        CHECK([[NSURL resourceValuesForKeys: @[NSURLNameKey] fromBookmarkData: forgedData] count] == 0);
        NSDictionary *forgedValues = @{@"path": real, @"resourceValues": @{NSURLNameKey: @{@"DLURL": @5}, NSURLIsDirectoryKey: @NO}};
        NSMutableData *forgedValuesData = [NSMutableData dataWithBytes: "DLBK" length: 4];
        [forgedValuesData appendData: [NSPropertyListSerialization dataWithPropertyList: forgedValues
                                                                                 format: NSPropertyListBinaryFormat_v1_0 options: 0 error: NULL]];
        NSDictionary *forgedStored = [NSURL resourceValuesForKeys: @[NSURLNameKey, NSURLIsDirectoryKey] fromBookmarkData: forgedValuesData];
        CHECK([[forgedStored objectForKey: NSURLIsDirectoryKey] isEqual: @NO]);

        // Data made by earlier versions, the path alone; for an item that is gone it is nil with 260.
        NSData *legacy = [kept dataUsingEncoding: NSUTF8StringEncoding];
        resolved = [NSURL URLByResolvingBookmarkData: legacy options: 0 relativeToURL: nil bookmarkDataIsStale: &stale error: NULL];
        CHECK([[resolved path] isEqualToString: kept]);
        CHECK(!stale);
        [fm removeItemAtPath: kept error: NULL];
        error = nil;
        resolved = [NSURL URLByResolvingBookmarkData: legacy options: 0 relativeToURL: nil bookmarkDataIsStale: NULL error: &error];
        CHECK(resolved == nil);
        CHECK([[error domain] isEqualToString: NSCocoaErrorDomain] && [error code] == 260);

        // A file name that is not valid UTF-8 (skipped where the file system refuses the name): no bookmark, an error, no crash.
        char badPath[PATH_MAX];
        snprintf(badPath, sizeof(badPath), "%s/\xff\xfe.txt", [dir fileSystemRepresentation]);
        int fd = open(badPath, O_CREAT | O_WRONLY, 0600);
        if (fd >= 0) {
            close(fd);
            NSURL *badURL = [NSURL fileURLWithFileSystemRepresentation: badPath isDirectory: NO relativeToURL: nil];
            error = nil;
            CHECK([badURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: nil error: &error] == nil);
            CHECK(error != nil);
            unlink(badPath);
        }

        [fm removeItemAtPath: dir error: NULL];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
