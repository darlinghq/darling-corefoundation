// Run linked against the candidate Foundation/CoreFoundation runtime.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"owner"] = @"previous";
    dictionary[@"owner"] = @"replacement";
    assert([dictionary[@"owner"] isEqual:@"replacement"]);
    dictionary[@"owner"] = nil;
    assert(dictionary[@"owner"] == nil);
    dictionary[@"absent"] = nil;
    assert([dictionary count] == 0);
    BOOL rejected = NO;
    @try { [dictionary setObject:nil forKey:@"owner"]; }
    @catch (NSException *exception) {
        rejected = [[exception name] isEqual:NSInvalidArgumentException];
    }
    assert(rejected);
    rejected = NO;
    @try { [dictionary setObject:nil forKeyedSubscript:nil]; }
    @catch (NSException *exception) {
        rejected = [[exception name] isEqual:NSInvalidArgumentException];
    }
    assert(rejected);
    [pool drain];
    puts("PASS: nil subscript removal, replacement and invalid-argument contracts");
    return 0;
}
