// Copyright (C) 2026 Lubos Dolezel
//
// NSFileSecurity (CFFileSecurityRef) secure coding: round trip of owner, group,
// mode and the UUIDs, the layout of the keyed archive, and refusal of
// non-keyed archivers. Expected values were observed on macOS 27 (the same
// file builds and passes there).
#import <Foundation/Foundation.h>
#include <CoreFoundation/CFFileSecurity.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

@interface Spoof : NSObject <NSSecureCoding> {
@public
    NSData *record;
}
@end
@implementation Spoof
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { if (record) [coder encodeBytes:[record bytes] length:[record length] forKey:@"NS.filesec"]; }
- (id)initWithCoder:(NSCoder *)coder { return nil; }
@end

static NSData *spoofArchive(NSData *record) {
    Spoof *spoof = [[Spoof alloc] init];
    spoof->record = record;
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    [archiver setClassName:@"__NSFileSecurity" forClass:[Spoof class]];
    [archiver encodeObject:spoof forKey:NSKeyedArchiveRootObjectKey];
    [archiver finishEncoding];
    NSData *data = [[[archiver encodedData] retain] autorelease];
    [archiver release];
    [spoof release];
    return data;
}

static NSData *recordOf(CFFileSecurityRef security) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:(id)security requiringSecureCoding:YES error:NULL];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    return plist[@"$objects"][1][@"NS.filesec"];
}

static uint32_t word(NSData *record, NSUInteger offset) {
    uint32_t v;
    memcpy(&v, (const char *)[record bytes] + offset, 4);
    return v; // the record is little-endian; the hosts running this test are too
}

static CFFileSecurityRef roundTrip(CFFileSecurityRef security) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:(id)security requiringSecureCoding:YES error:&error];
    CHECK(data != nil);
    id back = data ? [NSKeyedUnarchiver unarchivedObjectOfClass:[NSFileSecurity class] fromData:data error:&error] : nil;
    CHECK(back != nil);
    return (CFFileSecurityRef)back;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    CHECK([NSFileSecurity supportsSecureCoding]);

    CFFileSecurityRef full = CFFileSecurityCreate(NULL);
    CHECK(strcmp(object_getClassName((id)full), "__NSFileSecurity") == 0);
    CHECK(class_getSuperclass(object_getClass((id)full)) == [NSFileSecurity class]);
    CFFileSecuritySetOwner(full, 0x01020304);
    CFFileSecuritySetGroup(full, 0x05060708);
    CFFileSecuritySetMode(full, 0644);
    CFUUIDRef ownerUUID = CFUUIDCreateWithBytes(NULL, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
    CFUUIDRef groupUUID = CFUUIDCreateWithBytes(NULL, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0);
    CHECK(CFFileSecuritySetOwnerUUID(full, ownerUUID));
    CHECK(CFFileSecuritySetGroupUUID(full, groupUUID));

    // Layout: flags, owner at 8, group at 16, mode at 24, UUIDs at 32 and 48, 72 bytes in all.
    NSData *record = recordOf(full);
    CHECK([record length] == 72);
    CHECK(word(record, 0) == (0x01 | 0x02 | 0x04 | 0x08 | 0x10));
    CHECK(word(record, 8) == 0x01020304 && word(record, 16) == 0x05060708 && word(record, 24) == 0644);
    CHECK(memcmp((const char *)[record bytes] + 32, (uint8_t[]){1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}, 16) == 0);
    CHECK(memcmp((const char *)[record bytes] + 48, (uint8_t[]){0xa1,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7,0xa8,0xa9,0xaa,0xab,0xac,0xad,0xae,0xaf,0xb0}, 16) == 0);
    CFFileSecurityRef ownerOnly = CFFileSecurityCreate(NULL);
    CFFileSecuritySetOwner(ownerOnly, 0x01020304);
    CHECK(word(recordOf(ownerOnly), 0) == 0x01 && word(recordOf(ownerOnly), 8) == 0x01020304 && word(recordOf(ownerOnly), 24) == 0);
    CHECK(word(recordOf(CFFileSecurityCreate(NULL)), 0) == 0);

    // Round trip keeps what is set and leaves the rest unset.
    CFFileSecurityRef back = roundTrip(full);
    uid_t owner = 0; gid_t group = 0; mode_t mode = 0;
    CHECK(CFFileSecurityGetOwner(back, &owner) && owner == 0x01020304);
    CHECK(CFFileSecurityGetGroup(back, &group) && group == 0x05060708);
    CHECK(CFFileSecurityGetMode(back, &mode) && mode == 0644);
    CFUUIDRef gotOwner = NULL, gotGroup = NULL;
    CHECK(CFFileSecurityCopyOwnerUUID(back, &gotOwner) && CFEqual(gotOwner, ownerUUID));
    CHECK(CFFileSecurityCopyGroupUUID(back, &gotGroup) && CFEqual(gotGroup, groupUUID));
    CHECK(strcmp(object_getClassName((id)back), "__NSFileSecurity") == 0);

    CFFileSecurityRef partial = roundTrip(ownerOnly);
    CHECK(CFFileSecurityGetOwner(partial, &owner) && owner == 0x01020304);
    CHECK(!CFFileSecurityGetGroup(partial, &group) && !CFFileSecurityGetMode(partial, &mode));
    CHECK(!CFFileSecurityCopyOwnerUUID(partial, &gotOwner) && !CFFileSecurityCopyGroupUUID(partial, &gotGroup));

    // The mode keeps the file type bits too (16 bits).
    CFFileSecurityRef typed = CFFileSecurityCreate(NULL);
    CFFileSecuritySetMode(typed, 0170777);
    CHECK(CFFileSecurityGetMode(typed, &mode) && mode == 0170777);
    CHECK(word(recordOf(typed), 24) == 0170777);
    CHECK(CFFileSecurityGetMode(roundTrip(typed), &mode) && mode == 0170777);

    // A cleared property is not archived.
    CFFileSecurityRef cleared = CFFileSecurityCreate(NULL);
    CFFileSecuritySetMode(cleared, 0755);
    CFFileSecuritySetOwner(cleared, 9);
    CFFileSecurityClearProperties(cleared, kCFFileSecurityClearOwner);
    CHECK(word(recordOf(cleared), 0) == 0x10 && word(recordOf(cleared), 8) == 0);

    // A copy archives like the original.
    CFFileSecurityRef copy = CFFileSecurityCreateCopy(NULL, full);
    CHECK([recordOf(copy) isEqualToData:record]);

    // The default archiver works too.
    NSData *plain = [NSKeyedArchiver archivedDataWithRootObject:(id)full requiringSecureCoding:NO error:NULL];
    CFFileSecurityRef plainBack = (CFFileSecurityRef)[NSKeyedUnarchiver unarchiveObjectWithData:plain];
    CHECK(plainBack && CFFileSecurityGetOwner(plainBack, &owner) && owner == 0x01020304);

    // Non-keyed archivers are refused.
    BOOL raised = NO;
    @try { [NSArchiver archivedDataWithRootObject:(id)full]; }
    @catch (NSException *e) { raised = [e.name isEqual:NSInvalidArgumentException]; }
    CHECK(raised);

    // Malformed archives: no record, a short record.
    id nothing = nil;
    @try { nothing = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSFileSecurity class] fromData:spoofArchive(nil) error:NULL]; } @catch (NSException *e) {}
    CHECK(nothing == nil);
    @try { nothing = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSFileSecurity class] fromData:spoofArchive([NSMutableData dataWithLength:16]) error:NULL]; } @catch (NSException *e) {}
    CHECK(nothing == nil);
    // A well-formed record decodes, so the refusals above are not an artifact of the spoof.
    NSMutableData *ok = [NSMutableData dataWithLength:72];
    ((uint8_t *)[ok mutableBytes])[0] = 0x10;
    ((uint8_t *)[ok mutableBytes])[24] = 0x80; ((uint8_t *)[ok mutableBytes])[25] = 0x01;
    CFFileSecurityRef decoded = (CFFileSecurityRef)[NSKeyedUnarchiver unarchivedObjectOfClass:[NSFileSecurity class] fromData:spoofArchive(ok) error:NULL];
    CHECK(decoded && CFFileSecurityGetMode(decoded, &mode) && mode == 0600);

    [pool drain];
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("PASS: NSFileSecurity secure coding\n");
    return 0;
}
