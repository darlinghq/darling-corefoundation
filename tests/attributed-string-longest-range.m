// Test regression for issue #1006: attribute:atIndex:longestEffectiveRange:inRange:
// traps when the attribute is absent.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    // String: "ab" (no "K") + "cd" ("K" = "x")
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:@"ab"];
    NSAttributedString *part2 = [[NSAttributedString alloc] initWithString:@"cd"
                                                                attributes:@{@"K": @"x"}];
    [s appendAttributedString:part2];
    [part2 release];

    NSRange r = NSMakeRange(999, 999);
    // 1. Effective range for absent attribute at index 0
    id val1 = [s attribute:@"K" atIndex:0 effectiveRange:&r];
    assert(val1 == nil);
    assert(r.location == 0 && r.length == 2);

    // 2. Longest effective range for absent attribute at index 0 within range {0, 4}
    // Must NOT trap with SIGTRAP, must return nil and range {0, 2}
    r = NSMakeRange(999, 999);
    id val2 = [s attribute:@"K" atIndex:0 longestEffectiveRange:&r inRange:NSMakeRange(0, 4)];
    assert(val2 == nil);
    assert(r.location == 0 && r.length == 2);

    // 3. Longest effective range for present attribute at index 2
    r = NSMakeRange(999, 999);
    id val3 = [s attribute:@"K" atIndex:2 longestEffectiveRange:&r inRange:NSMakeRange(0, 4)];
    assert([val3 isEqual:@"x"]);
    assert(r.location == 2 && r.length == 2);

    // 4. Consecutive runs without attribute: "ab" (no K) + "cd" ("K"="x") + "ef" (no K) + "gh" (no K)
    NSAttributedString *part3 = [[NSAttributedString alloc] initWithString:@"ef"];
    NSAttributedString *part4 = [[NSAttributedString alloc] initWithString:@"gh"
                                                                attributes:@{@"Other": @"y"}];
    [s appendAttributedString:part3];
    [s appendAttributedString:part4];
    [part3 release];
    [part4 release];

    // Index 4 ("ef") has no K, index 6 ("gh") also has no K: longest range must unite both: {4, 4}
    r = NSMakeRange(999, 999);
    id val4 = [s attribute:@"K" atIndex:4 longestEffectiveRange:&r inRange:NSMakeRange(0, 8)];
    assert(val4 == nil);
    assert(r.location == 4 && r.length == 4);

    [s release];
    [pool drain];
    puts("PASS: attribute:atIndex:longestEffectiveRange:inRange: with absent and present attributes");
    return 0;
}
