// Copyright (C) 2026 Lubos Dolezel
//
// A keyed archive in the XML property list format writes each object reference as a one-entry
// dictionary with the key CF$UID and reads it back; the archive round trips. Only public API is
// used, so the file also builds and passes on macOS.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
    @autoreleasepool {
        NSArray *original = @[@"one", @2, @{@"key": @"value"}];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
        [archiver setOutputFormat:NSPropertyListXMLFormat_v1_0];
        [archiver encodeObject:original forKey:NSKeyedArchiveRootObjectKey];
        [archiver finishEncoding];
        NSData *data = [[[archiver encodedData] retain] autorelease];
        [archiver release];

        CHECK(data.length > 5 && memcmp(data.bytes, "<?xml", 5) == 0);
        NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        CHECK([text rangeOfString:@"<key>CF$UID</key>"].location != NSNotFound);

        NSError *error = nil;
        id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
        CHECK(plist != nil && error == nil);
        CHECK([plist isKindOfClass:[NSDictionary class]] && [[plist objectForKey:@"$top"] isKindOfClass:[NSDictionary class]]);

        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        CHECK(unarchiver != nil);
        [unarchiver setRequiresSecureCoding:NO];
        id decoded = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
        CHECK([decoded isEqual:original]);
        [unarchiver release];
    }
    printf("%s\n", failures ? "FAIL" : "PASS: keyed archiver XML UIDs");
    return failures ? 1 : 0;
}
