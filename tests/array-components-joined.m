// Copyright (C) 2026 Lubos Dolezel
//
// -[NSArray componentsJoinedByString:] puts the separator between every pair of adjacent
// elements, whether or not an element is the same object as another one.
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

static void check_joined(const char *label, NSString *got, NSString *want)
{
    BOOL ok = [got isEqualToString:want];
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    if (!ok)
    {
        printf("  got '%s', want '%s'\n", [got UTF8String], [want UTF8String]);
        failures++;
    }
}

int main(void)
{
    @autoreleasepool
    {
        NSString *x = @"x";
        NSString *y = @"y";

        check_joined("distinct elements", [[NSArray arrayWithObjects:@"a", @"b", @"c", nil] componentsJoinedByString:@", "], @"a, b, c");
        check_joined("last element repeated", [[NSArray arrayWithObjects:x, y, y, nil] componentsJoinedByString:@"-"], @"x-y-y");
        check_joined("first element repeated", [[NSArray arrayWithObjects:x, x, y, nil] componentsJoinedByString:@"-"], @"x-x-y");
        check_joined("all elements the same object", [[NSArray arrayWithObjects:x, x, x, x, nil] componentsJoinedByString:@"/"], @"x/x/x/x");
        check_joined("element repeated with gaps", [[NSArray arrayWithObjects:x, y, x, y, x, nil] componentsJoinedByString:@"|"], @"x|y|x|y|x");
        check_joined("two identical elements", [[NSArray arrayWithObjects:x, x, nil] componentsJoinedByString:@" "], @"x x");
        check_joined("one element", [[NSArray arrayWithObject:x] componentsJoinedByString:@","], @"x");
        check_joined("no elements", [[NSArray array] componentsJoinedByString:@","], @"");
        check_joined("empty separator", [[NSArray arrayWithObjects:x, x, y, nil] componentsJoinedByString:@""], @"xxy");
        check_joined("mutable array", [[NSMutableArray arrayWithObjects:x, y, y, nil] componentsJoinedByString:@"+"], @"x+y+y");
        check_joined("non-string elements", [[NSArray arrayWithObjects:[NSNumber numberWithInt:1], [NSNumber numberWithInt:1], nil] componentsJoinedByString:@"."], @"1.1");

        BOOL raised = NO;
        @try
        {
            (void)[[NSArray arrayWithObject:x] componentsJoinedByString:(NSString *)[NSNumber numberWithInt:1]];
        }
        @catch (NSException *e)
        {
            raised = [[e name] isEqualToString:NSInvalidArgumentException];
        }
        printf("%s non-string separator raises NSInvalidArgumentException\n", raised ? "PASS" : "FAIL");
        failures += !raised;
    }
    return failures ? 1 : 0;
}
