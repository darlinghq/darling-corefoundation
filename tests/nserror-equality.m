// Copyright (C) 2026 Lubos Dolezel
//
// NSError equality: errors are equal when their domain, code and user info
// are (a missing user info equals an empty one); the hash agrees with that.
// Checked on macOS 27.
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
    @autoreleasepool
    {
        NSError *a = [NSError errorWithDomain:@"d" code:1 userInfo:nil];
        NSError *same = [NSError errorWithDomain:[NSString stringWithFormat:@"%@", @"d"] code:1 userInfo:nil];
        NSError *empty = [NSError errorWithDomain:@"d" code:1 userInfo:@{}];
        NSError *info = [NSError errorWithDomain:@"d" code:1 userInfo:@{@"k": @1}];
        NSError *info2 = [NSError errorWithDomain:@"d" code:1 userInfo:@{@"k": @1}];
        NSError *otherInfo = [NSError errorWithDomain:@"d" code:1 userInfo:@{@"k": @2}];

        CHECK([a isEqual:a]);
        CHECK([a isEqual:same] && [same isEqual:a]);
        CHECK([a hash] == [same hash]);
        CHECK([a isEqual:empty] && [empty isEqual:a]);
        CHECK([info isEqual:info2] && [info hash] == [info2 hash]);
        CHECK(![info isEqual:otherInfo]);
        CHECK(![a isEqual:info]);
        CHECK(![a isEqual:[NSError errorWithDomain:@"d" code:2 userInfo:nil]]);
        CHECK(![a isEqual:[NSError errorWithDomain:@"e" code:1 userInfo:nil]]);
        CHECK(![a isEqual:@"d"]);
        CHECK(![a isEqual:nil]);

        // Errors inside a user info compare by value too.
        NSError *outer1 = [NSError errorWithDomain:@"o" code:3 userInfo:@{NSUnderlyingErrorKey: a}];
        NSError *outer2 = [NSError errorWithDomain:@"o" code:3 userInfo:@{NSUnderlyingErrorKey: same}];
        CHECK([outer1 isEqual:outer2]);
        NSSet *set = [NSSet setWithObjects:a, same, empty, nil];
        CHECK([set count] == 1);
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS: NSError equality\n");
    return 0;
}
