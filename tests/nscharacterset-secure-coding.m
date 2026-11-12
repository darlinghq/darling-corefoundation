// Copyright (C) 2026 Lubos Dolezel
//
// NSCharacterSet and NSMutableCharacterSet secure coding: round trips of
// predefined, inverted, range, string and bitmap sets, the keys of the keyed
// archive, and refusal of malformed archives. Expected values were observed on
// macOS 27 (the same file builds and passes there).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

// Archives with arbitrary stored fields under a chosen class name.
@interface Spoof : NSObject <NSSecureCoding> {
@public
    NSDictionary *ints;
    NSDictionary *objects;
    NSDictionary *bytes;
}
@end
@implementation Spoof
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {
    for (NSString *key in ints) [coder encodeInt64:[ints[key] longLongValue] forKey:key];
    for (NSString *key in objects) [coder encodeObject:objects[key] forKey:key];
    for (NSString *key in bytes) [coder encodeBytes:[bytes[key] bytes] length:[bytes[key] length] forKey:key];
}
- (id)initWithCoder:(NSCoder *)coder { return nil; }
@end

static NSData *spoofArchive(NSString *className, NSDictionary *ints, NSDictionary *objects, NSDictionary *bytes) {
    Spoof *spoof = [[Spoof alloc] init];
    spoof->ints = ints;
    spoof->objects = objects;
    spoof->bytes = bytes;
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    [archiver setClassName:className forClass:[Spoof class]];
    [archiver encodeObject:spoof forKey:NSKeyedArchiveRootObjectKey];
    [archiver finishEncoding];
    NSData *data = [[[archiver encodedData] retain] autorelease];
    [archiver release];
    [spoof release];
    return data;
}

static id secureDecode(Class cls, NSData *data) {
    id result = nil;
    @try { result = [NSKeyedUnarchiver unarchivedObjectOfClass:cls fromData:data error:NULL]; }
    @catch (NSException *exception) { result = nil; }
    return result;
}

static void expectRefused(const char *label, NSData *data) {
    if (secureDecode([NSCharacterSet class], data) != nil) {
        printf("FAIL: malformed archive decoded: %s\n", label);
        failures++;
    }
}

// The keys of the object archived under the root, as a sorted array.
static NSArray *archivedKeys(id set) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:set requiringSecureCoding:YES error:NULL];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in plist[@"$objects"][1]) if (![key isEqualToString:@"$class"]) [keys addObject:key];
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

static id archivedValue(id set, NSString *key) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:set requiringSecureCoding:YES error:NULL];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    return plist[@"$objects"][1][key];
}

// The archived class name; the class record sits at a different index depending on how many values precede it.
static BOOL archiveNamesClass(NSDictionary *plist, NSString *name) {
    for (id object in plist[@"$objects"])
        if ([object isKindOfClass:[NSDictionary class]] && [object[@"$classname"] isEqual:name])
            return YES;
    return NO;
}

static NSCharacterSet *roundTrip(NSCharacterSet *set, Class cls) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:set requiringSecureCoding:YES error:&error];
    CHECK(data != nil);
    NSCharacterSet *back = data ? [NSKeyedUnarchiver unarchivedObjectOfClass:cls fromData:data error:&error] : nil;
    CHECK(back != nil);
    if (back == nil) printf("  error: %s\n", [[error description] UTF8String]);
    return back;
}

static BOOL sameMembers(NSCharacterSet *a, NSCharacterSet *b) {
    for (UTF32Char c = 0; c < 0x30000; c++)
        if ([a longCharacterIsMember:c] != [b longCharacterIsMember:c]) return NO;
    for (UTF32Char c = 0xE0000; c < 0xE0200; c++)
        if ([a longCharacterIsMember:c] != [b longCharacterIsMember:c]) return NO;
    return YES;
}

static void check_round_trips(void) {
    CHECK([NSCharacterSet supportsSecureCoding]);
    CHECK([NSMutableCharacterSet supportsSecureCoding]);

    NSMutableCharacterSet *mixed = [NSMutableCharacterSet characterSetWithCharactersInString:@"abc"];
    [mixed addCharactersInRange:NSMakeRange(0x400, 3)];
    NSMutableCharacterSet *inv = [NSMutableCharacterSet characterSetWithCharactersInString:@"abc"];
    [inv invert];
    NSMutableCharacterSet *digitsPlusA = [[[NSCharacterSet decimalDigitCharacterSet] mutableCopy] autorelease];
    [digitsPlusA addCharactersInString:@"a"];
    NSArray *sets = @[
        [NSCharacterSet decimalDigitCharacterSet], [NSCharacterSet letterCharacterSet],
        [NSCharacterSet whitespaceCharacterSet], [NSCharacterSet whitespaceAndNewlineCharacterSet],
        [NSCharacterSet controlCharacterSet], [NSCharacterSet illegalCharacterSet],
        [NSCharacterSet punctuationCharacterSet], [NSCharacterSet symbolCharacterSet],
        [NSCharacterSet newlineCharacterSet], [NSCharacterSet capitalizedLetterCharacterSet],
        [[NSCharacterSet decimalDigitCharacterSet] invertedSet], [[NSCharacterSet symbolCharacterSet] invertedSet],
        [NSCharacterSet characterSetWithRange:NSMakeRange('a', 3)],
        [[NSCharacterSet characterSetWithRange:NSMakeRange('a', 3)] invertedSet],
        [NSCharacterSet characterSetWithRange:NSMakeRange(0x1F600, 5)],
        [NSCharacterSet characterSetWithCharactersInString:@"xyz"],
        [[NSCharacterSet characterSetWithCharactersInString:@"xyz"] invertedSet],
        [NSCharacterSet characterSetWithCharactersInString:@"a\U0001F600"],
        [NSCharacterSet characterSetWithCharactersInString:@""],
        [NSCharacterSet characterSetWithBitmapRepresentation:[[NSCharacterSet characterSetWithRange:NSMakeRange('a', 3)] bitmapRepresentation]],
        [NSCharacterSet URLHostAllowedCharacterSet],
        mixed, inv, digitsPlusA,
    ];
    for (NSCharacterSet *set in sets) {
        // Whether the archive names the mutable class (some immutable sets are instances of a mutable subclass on macOS).
        NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:set requiringSecureCoding:YES error:NULL];
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:archived options:0 format:NULL error:NULL];
        BOOL isMutable = archiveNamesClass(plist, @"NSMutableCharacterSet");
        NSCharacterSet *back = roundTrip(set, [NSCharacterSet class]);
        if (back && !sameMembers(set, back)) { printf("FAIL: membership differs after the round trip of %s\n", [[set description] UTF8String]); failures++; }
        if (isMutable) {
            // A mutable set decodes as a mutable set when asked for as one.
            NSMutableCharacterSet *mutableBack = (NSMutableCharacterSet *)roundTrip(set, [NSMutableCharacterSet class]);
            CHECK([mutableBack respondsToSelector:@selector(addCharactersInString:)]);
            [mutableBack addCharactersInString:@"Q"];
            CHECK([mutableBack characterIsMember:'Q']);
        }
    }
}

static void check_archive_keys(void) {
    CHECK([archivedValue([NSCharacterSet decimalDigitCharacterSet], @"NSBuiltinID") intValue] == 4);
    CHECK([archivedValue([NSCharacterSet letterCharacterSet], @"NSBuiltinID") intValue] == 5);
    CHECK([archivedValue([NSCharacterSet illegalCharacterSet], @"NSBuiltinID") intValue] == 12);
    CHECK([archivedKeys([NSCharacterSet decimalDigitCharacterSet]) isEqual:@[@"NSBuiltinID"]]);
    NSArray *invertedKeys = @[@"NSBuiltinID", @"NSIsInverted"];
    CHECK([archivedKeys([[NSCharacterSet decimalDigitCharacterSet] invertedSet]) isEqual:invertedKeys]);

    // The range is packed as location << 32 | length.
    NSCharacterSet *range = [NSCharacterSet characterSetWithRange:NSMakeRange('a', 3)];
    CHECK([archivedKeys(range) isEqual:@[@"NSRange"]]);
    CHECK([archivedValue(range, @"NSRange") longLongValue] == (((long long)'a' << 32) | 3));
    CHECK([archivedKeys([range invertedSet]) isEqual:(@[@"NSIsInverted", @"NSRange"])]);

    // A BMP-only set built from characters keeps its string.
    NSCharacterSet *string = [NSCharacterSet characterSetWithCharactersInString:@"xyz"];
    CHECK([archivedKeys(string) isEqual:@[@"NSString"]]);
    // The string is an archived object, so the key holds a reference to it.
    NSData *stringArchive = [NSKeyedArchiver archivedDataWithRootObject:string requiringSecureCoding:YES error:NULL];
    NSDictionary *stringPlist = [NSPropertyListSerialization propertyListWithData:stringArchive options:0 format:NULL error:NULL];
    CHECK([stringPlist[@"$objects"] containsObject:@"xyz"]);

    // test_quirk_empty_string_set_stores_nil_string (MC26.13, macOS 26.7.3): the empty set keeps the
    // NSString key but its value is nil, not an archived empty string.
    NSCharacterSet *emptySet = [NSCharacterSet characterSetWithCharactersInString:@""];
    CHECK([archivedKeys(emptySet) isEqual:@[@"NSString"]]);
    NSData *emptyArchive = [NSKeyedArchiver archivedDataWithRootObject:emptySet requiringSecureCoding:YES error:NULL];
    NSDictionary *emptyPlist = [NSPropertyListSerialization propertyListWithData:emptyArchive options:0 format:NULL error:NULL];
    CHECK(![emptyPlist[@"$objects"] containsObject:@""]);

    // Everything else is a bitmap: the BMP plane, then (plane number, plane) pairs.
    NSCharacterSet *bitmap = [NSCharacterSet characterSetWithCharactersInString:@"a\U0001F600"];
    CHECK([archivedKeys(bitmap) isEqual:@[@"NSBitmap"]]);
    CHECK([archivedValue(bitmap, @"NSBitmap") length] == 8192 + 1 + 8192);

    // Symbol and newline are archived with their bitmap and an identifier under NSBuiltinID2.
    CHECK([archivedKeys([NSCharacterSet symbolCharacterSet]) isEqual:(@[@"NSBitmap", @"NSBuiltinID2"])]);
    CHECK([archivedValue([NSCharacterSet symbolCharacterSet], @"NSBuiltinID2") intValue] == 14);
    CHECK([archivedValue([NSCharacterSet newlineCharacterSet], @"NSBuiltinID2") intValue] == 15);

    // The archive records the mutable class.
    NSMutableCharacterSet *m = [NSMutableCharacterSet characterSetWithCharactersInString:@"abc"];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:m requiringSecureCoding:YES error:NULL];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    CHECK(archiveNamesClass(plist, @"NSMutableCharacterSet"));
}

static void check_default_archiver(void) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[NSCharacterSet letterCharacterSet] requiringSecureCoding:NO error:NULL];
    NSCharacterSet *back = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    CHECK([back characterIsMember:'a'] && ![back characterIsMember:'1']);
}

static void check_malformed(void) {
    NSString *name = @"NSCharacterSet";
    expectRefused("no stored value", spoofArchive(name, @{}, nil, nil));
    expectRefused("unknown builtin id", spoofArchive(name, @{@"NSBuiltinID": @99}, nil, nil));
    expectRefused("builtin id zero", spoofArchive(name, @{@"NSBuiltinID": @0}, nil, nil));
    expectRefused("range beyond Unicode", spoofArchive(name, @{@"NSRange": @(((long long)0x110000 << 32) | 1)}, nil, nil));
    expectRefused("range length beyond Unicode", spoofArchive(name, @{@"NSRange": @(((long long)0x10FFFF << 32) | 5)}, nil, nil));
    expectRefused("string of the wrong class", spoofArchive(name, nil, @{@"NSString": @42}, nil));

    // A well-formed spoofed archive decodes, so the refusals above are not an artifact of the spoof.
    NSCharacterSet *ok = secureDecode([NSCharacterSet class], spoofArchive(name, @{@"NSRange": @(((long long)'a' << 32) | 3)}, nil, nil));
    CHECK(ok != nil && [ok characterIsMember:'b'] && ![ok characterIsMember:'d']);

    // Asking for another class is refused.
    CHECK(secureDecode([NSString class], [NSKeyedArchiver archivedDataWithRootObject:[NSCharacterSet letterCharacterSet] requiringSecureCoding:YES error:NULL]) == nil);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    check_round_trips();
    check_archive_keys();
    check_default_archiver();
    check_malformed();
    [pool drain];
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("PASS: NSCharacterSet secure coding\n");
    return 0;
}
