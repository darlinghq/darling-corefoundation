#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static NSMutableArray *five(void)
{
    return [NSMutableArray arrayWithObjects:@1, @2, @3, @4, @5, nil];
}

static BOOL removes(NSRange range, NSArray *expected)
{
    NSMutableArray *a = five();
    @try
    {
        [a removeObjectsInRange:range];
    }
    @catch (NSException *e)
    {
        printf("  raised %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        return NO;
    }
    return [a isEqualToArray:expected];
}

static BOOL raisesRange(NSMutableArray *a, NSRange range)
{
    NSArray *before = [[a copy] autorelease];
    @try
    {
        [a removeObjectsInRange:range];
    }
    @catch (NSException *e)
    {
        return [[e name] isEqualToString:NSRangeException] && [a isEqualToArray:before];
    }
    return NO;
}

int main(void)
{
    @autoreleasepool
    {
        check_result("prefix (0, 3)", removes(NSMakeRange(0, 3), @[@4, @5]));
        check_result("middle (1, 3)", removes(NSMakeRange(1, 3), @[@1, @5]));
        check_result("suffix (3, 2)", removes(NSMakeRange(3, 2), @[@1, @2, @3]));
        check_result("whole array (0, 5)", removes(NSMakeRange(0, 5), @[]));
        check_result("first element (0, 1)", removes(NSMakeRange(0, 1), @[@2, @3, @4, @5]));
        check_result("last element (4, 1)", removes(NSMakeRange(4, 1), @[@1, @2, @3, @4]));
        check_result("empty range at start (0, 0)", removes(NSMakeRange(0, 0), @[@1, @2, @3, @4, @5]));
        check_result("empty range inside (2, 0)", removes(NSMakeRange(2, 0), @[@1, @2, @3, @4, @5]));
        check_result("empty range at end (5, 0)", removes(NSMakeRange(5, 0), @[@1, @2, @3, @4, @5]));

        NSMutableArray *empty = [NSMutableArray array];
        @try
        {
            [empty removeObjectsInRange:NSMakeRange(0, 0)];
            check_result("empty range on an empty array", [empty count] == 0);
        }
        @catch (NSException *e)
        {
            check_result("empty range on an empty array", NO);
        }

        check_result("range past the end raises NSRangeException", raisesRange(five(), NSMakeRange(3, 3)));
        check_result("location past the end raises NSRangeException", raisesRange(five(), NSMakeRange(6, 0)));
        check_result("length wrapping NSMaxRange raises NSRangeException", raisesRange(five(), NSMakeRange(1, NSUIntegerMax)));
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
