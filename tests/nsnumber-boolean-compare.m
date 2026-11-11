// Copyright (C) 2026 Lubos Dolezel
//
// Comparing numbers with the boolean singletons @YES and @NO: a boolean
// behaves as the number 1 or 0 (observed on macOS 27 for every number kind).
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
    @autoreleasepool
    {
        NSArray *ones = @[@1, @1LL, @(1.0f), @(1.0), @((char)1), @((unsigned char)1), @((short)1), @(1UL)];
        for (NSNumber *one in ones) {
            CHECK([one isEqual:@YES]);
            CHECK([@YES isEqual:one]);
            CHECK([one isEqualToNumber:@YES]);
            CHECK(![one isEqual:@NO]);
            CHECK([one compare:@YES] == NSOrderedSame);
            CHECK([one compare:@NO] == NSOrderedDescending);
            CHECK([@YES compare:one] == NSOrderedSame);
            CHECK([@NO compare:one] == NSOrderedAscending);
        }
        NSArray *zeros = @[@0, @0LL, @(0.0f), @(0.0), @((char)0), @((short)0)];
        for (NSNumber *zero in zeros) {
            CHECK([zero isEqual:@NO]);
            CHECK([@NO isEqual:zero]);
            CHECK(![zero isEqual:@YES]);
            CHECK([zero compare:@YES] == NSOrderedAscending);
            CHECK([zero compare:@NO] == NSOrderedSame);
        }
        CHECK(![@1.5 isEqual:@YES] && [@1.5 compare:@YES] == NSOrderedDescending);
        CHECK(![@5LL isEqual:@YES] && [@5LL compare:@NO] == NSOrderedDescending);
        CHECK(![@(-1) isEqual:@NO] && [@(-1) compare:@NO] == NSOrderedAscending);
        CHECK([@YES isEqual:@YES] && ![@YES isEqual:@NO] && [@YES compare:@NO] == NSOrderedDescending);

        // A number decoded from an archive, from NSArchiver and from a keyed archive.
        NSNumber *viaArchiver = [NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:@1]];
        CHECK(viaArchiver != nil && [viaArchiver isEqual:@YES]);
        NSNumber *flag = [NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:@YES]];
        CHECK(flag != nil && [flag isEqual:@YES] && ![flag isEqual:@NO]);
        NSData *keyed = [NSKeyedArchiver archivedDataWithRootObject:@1 requiringSecureCoding:NO error:NULL];
        NSNumber *viaKeyed = [NSKeyedUnarchiver unarchiveObjectWithData:keyed];
        CHECK(viaKeyed != nil && [viaKeyed isEqual:@YES]);
        NSNumber *decodedBool = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:@YES requiringSecureCoding:NO error:NULL]];
        CHECK(decodedBool != nil && [decodedBool isEqual:@YES] && [decodedBool isEqual:@1] && ![decodedBool isEqual:@0]);

        // In collections: arrays and dictionaries compare their elements with -isEqual:.
        CHECK(([@[@1, @0] isEqualToArray:@[@YES, @NO]]));
        CHECK(([@{@"k": @1} isEqualToDictionary:@{@"k": @YES}]));
    }
    if (failures != 0) { printf("%d failures\n", failures); return 1; }
    printf("PASS: NSNumber comparison with booleans\n");
    return 0;
}
