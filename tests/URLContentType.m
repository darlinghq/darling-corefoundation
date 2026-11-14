// Copyright (C) 2026 Lubos Dolezel
// NSURLContentTypeKey: the UTType of a file URL, from its uniform type identifier.
// Build against Foundation and UniformTypeIdentifiers and run in the guest.
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;
static void expect(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static id contentType(NSString *path, NSError **error)
{
    id value = nil;
    BOOL ok = [[NSURL fileURLWithPath:path] getResourceValue:&value forKey:NSURLContentTypeKey error:error];
    return ok ? (value ?: [NSNull null]) : nil;
}

int main(void)
{
    @autoreleasepool {
        char temp[] = "/tmp/darling-url-content-type-XXXXXX";
        char *root = mkdtemp(temp);
        if (root == NULL)
            return 2;
        NSString *base = [NSString stringWithUTF8String:root];
        for (NSString *name in @[@"notes.txt", @"blob.qqqzzz"]) {
            int fd = open([[base stringByAppendingPathComponent:name] fileSystemRepresentation], O_CREAT | O_WRONLY, 0600);
            if (fd >= 0)
                close(fd);
        }
        mkdir([[base stringByAppendingPathComponent:@"folder"] fileSystemRepresentation], 0700);

        NSError *error = nil;
        UTType *type = contentType([base stringByAppendingPathComponent:@"notes.txt"], &error);
        expect("text file value is a UTType", [type isKindOfClass:[UTType class]]);
        expect("text file is public.plain-text", [type.identifier isEqualToString:@"public.plain-text"]);

        type = contentType([base stringByAppendingPathComponent:@"folder"], &error);
        expect("directory is public.folder", [type isKindOfClass:[UTType class]] && [type.identifier isEqualToString:@"public.folder"]);

        type = contentType([base stringByAppendingPathComponent:@"blob.qqqzzz"], &error);
        expect("unknown extension is a dynamic type conforming to public.data",
              [type isKindOfClass:[UTType class]] && type.isDynamic && [type conformsToType:UTTypeData]);

        error = nil;
        id missing = contentType([base stringByAppendingPathComponent:@"missing"], &error);
        expect("missing file fails with an error", missing == nil && error != nil);
        expect("missing file error is NSFileReadNoSuchFileError over POSIX ENOENT",
               [error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError &&
               [[error.userInfo[NSUnderlyingErrorKey] domain] isEqualToString:NSPOSIXErrorDomain] &&
               [error.userInfo[NSUnderlyingErrorKey] code] == ENOENT);

        NSDictionary *values = [[NSURL fileURLWithPath:[base stringByAppendingPathComponent:@"notes.txt"]]
            resourceValuesForKeys:@[NSURLContentTypeKey, NSURLTypeIdentifierKey] error:&error];
        expect("dictionary has both keys", values.count == 2);
        expect("type identifier matches the UTType", [[values[NSURLContentTypeKey] identifier] isEqualToString:values[NSURLTypeIdentifierKey]]);

        unlink([[base stringByAppendingPathComponent:@"notes.txt"] fileSystemRepresentation]);
        unlink([[base stringByAppendingPathComponent:@"blob.qqqzzz"] fileSystemRepresentation]);
        rmdir([[base stringByAppendingPathComponent:@"folder"] fileSystemRepresentation]);
        rmdir(root);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
