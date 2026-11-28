// NSMutableOrderedSet removal methods that evaluate a block while enumerating.
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface NSMutableOrderedSet (DarlingRemovalTest)
- (void)removeObjectsWithOptions:(NSEnumerationOptions)options passingTest:(BOOL (^)(id obj, NSUInteger idx, BOOL *stop))test;
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes options:(NSEnumerationOptions)options passingTest:(BOOL (^)(id obj, NSUInteger idx, BOOL *stop))test;
@end

static int failures;

static void check_result(const char *label, int ok)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", label);
	failures += !ok;
}

static BOOL (^is_even)(id, NSUInteger, BOOL *) = ^BOOL(id object, NSUInteger index, BOOL *stop) {
	(void)index;
	(void)stop;
	return [object integerValue] % 2 == 0;
};

static int array_is(NSOrderedSet *set, NSArray *expected)
{
	return [[set array] isEqualToArray:expected];
}

int main(void)
{
	@autoreleasepool {
		NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:@[@0, @1, @2, @3, @4]];

		[set removeObjectsWithOptions:0 passingTest:is_even];
		check_result("remove all passing: even objects removed", array_is(set, @[@1, @3]));

		set = [NSMutableOrderedSet orderedSetWithArray:@[@0, @1, @2, @3, @4]];
		[set removeObjectsWithOptions:NSEnumerationReverse passingTest:is_even];
		check_result("remove all passing: reverse enumeration removes the same objects", array_is(set, @[@1, @3]));

		set = [NSMutableOrderedSet orderedSetWithArray:@[@0, @1, @2, @3, @4]];
		NSMutableIndexSet *candidates = [NSMutableIndexSet indexSet];
		[candidates addIndex:1];
		[candidates addIndex:2];
		[candidates addIndex:4];
		[set removeObjectsAtIndexes:candidates options:0 passingTest:is_even];
		check_result("remove at indexes passing: only matching candidates removed", array_is(set, @[@0, @1, @3]));

		set = [NSMutableOrderedSet orderedSetWithArray:@[@0, @1, @2, @3, @4]];
		__block NSUInteger stopIndex = NSNotFound;
		[set removeObjectsWithOptions:0 passingTest:^(id object, NSUInteger index, BOOL *stop) {
			if (index == 2) {
				*stop = YES;
				stopIndex = index;
			}
			return is_even(object, index, stop);
		}];
		check_result("remove all passing: stop is honoured", stopIndex == 2 && array_is(set, @[@1, @2, @3, @4]));
	}
	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
