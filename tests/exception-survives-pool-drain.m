// An exception that unwinds through an @finally block draining an
// autorelease pool must still be a valid object when the @catch receives it.
// Exceptions are autoreleased when created, so the drain frees them unless the
// runtime keeps them alive while they propagate. Also covers a block raising,
// a nested raise inside a @catch body, and many exceptions caught in a loop.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

static void raiseNamed(NSString *name)
{
    [NSException raise: name format: @"reason of %@", name];
}

static void drainPoolAround(void (^body)(void))
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    @try {
        body();
    } @finally {
        [pool release];
    }
}

int main(void)
{
    NSAutoreleasePool *outer = [NSAutoreleasePool new];

    // Plain function raising under a pool-draining @finally
    {
        NSString *name = nil, *reason = nil;
        @try {
            drainPoolAround(^{ raiseNamed(@"First"); });
        } @catch (NSException *e) {
            name = [[e name] copy];
            reason = [[e reason] copy];
        }
        CHECK([name isEqualToString: @"First"], "the exception name survives the pool drain");
        CHECK([reason isEqualToString: @"reason of First"], "the exception reason survives the pool drain");
        [name release];
        [reason release];
    }

    // Two nested draining frames
    {
        BOOL caught = NO;
        @try {
            drainPoolAround(^{ drainPoolAround(^{ raiseNamed(@"Nested"); }); });
        } @catch (NSException *e) {
            caught = [[e name] isEqualToString: @"Nested"];
        }
        CHECK(caught, "the exception survives two nested pool drains");
    }

    // A raise inside a @catch body leaves the caught exception usable
    {
        BOOL outerOk = NO, innerOk = NO;
        @try {
            drainPoolAround(^{ raiseNamed(@"Outer"); });
        } @catch (NSException *e) {
            @try {
                drainPoolAround(^{ raiseNamed(@"Inner"); });
            } @catch (NSException *inner) {
                innerOk = [[inner name] isEqualToString: @"Inner"];
            }
            outerOk = [[e name] isEqualToString: @"Outer"];
        }
        CHECK(innerOk, "the exception raised inside a @catch body is caught");
        CHECK(outerOk, "the exception being handled is still valid after another one was caught");
    }

    // Many exceptions, more than the runtime can hold on to
    {
        int caught = 0;
        for (int i = 0; i < 1000; i++) {
            @try {
                drainPoolAround(^{ raiseNamed(@"Loop"); });
            } @catch (NSException *e) {
                if ([[e name] isEqualToString: @"Loop"])
                    caught++;
            }
        }
        CHECK(caught == 1000, "every exception in a loop is caught intact");
    }

    // A rethrow from a @catch keeps the same object
    {
        NSException *first = nil, *second = nil;
        BOOL intact = NO;
        @try {
            @try {
                drainPoolAround(^{ raiseNamed(@"Rethrown"); });
            } @catch (NSException *e) {
                first = e;
                @throw;
            }
        } @catch (NSException *e) {
            second = e;
            intact = [[e name] isEqualToString: @"Rethrown"];
        }
        CHECK(first != nil && first == second, "a rethrown exception is the same object");
        CHECK(intact, "and it is intact");
    }

    [outer release];
    if (failures)
        return 1;
    puts("PASS: exceptions survive autorelease pool drains while unwinding");
    return 0;
}
