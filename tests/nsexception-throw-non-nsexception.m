// Objective-C code may throw any object, not only an NSException. A string, an instance of a
// class that does not descend from NSException and an instance of a root class that implements
// retain and release but not isKindOfClass: must reach the matching @catch unchanged, while an
// NSException thrown the same way still gets its call stack recorded.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

@interface PlainThrowable : NSObject
@end
@implementation PlainThrowable
@end

__attribute__((objc_root_class))
@interface RootThrowable
{
    Class isa;
}
+ (id)alloc;
- (id)retain;
- (void)release;
@end
@implementation RootThrowable
+ (id)alloc { return class_createInstance(self, 0); }
// objc_exception_throw retains the thrown object and releases it after the catch, so a root
// class must answer these two; it deliberately has no isKindOfClass: or any other method.
- (id)retain { return self; }
- (void)release {}
+ (void)initialize {}
@end

@interface MyException : NSException
@end
@implementation MyException
@end

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    // A string is delivered to @catch (NSString *) as the object that was thrown
    {
        NSString *thrown = [NSString stringWithFormat: @"a string %d", 1];
        id caught = nil;
        BOOL caughtAsString = NO;
        @try {
            @throw thrown;
        } @catch (NSString *s) {
            caughtAsString = YES;
            caught = s;
        } @catch (id other) {
            caught = other;
        }
        CHECK(caughtAsString, "a thrown string is caught by @catch (NSString *)");
        CHECK(caught == thrown, "the caught string is the thrown object");
    }

    // An NSObject subclass that is not an NSException
    {
        PlainThrowable *thrown = [[PlainThrowable new] autorelease];
        id caught = nil;
        @try {
            @throw thrown;
        } @catch (id other) {
            caught = other;
        }
        CHECK(caught == thrown, "a thrown PlainThrowable is caught as the same object");
    }

    // An NSException still gets its call stack recorded when it is thrown
    {
        NSException *thrown = [NSException exceptionWithName: @"Plain" reason: @"plain reason" userInfo: nil];
        NSException *caught = nil;
        @try {
            @throw thrown;
        } @catch (NSException *e) {
            caught = e;
        }
        CHECK(caught == thrown, "the caught NSException is the thrown object");
        CHECK([[caught callStackSymbols] count] > 0, "a thrown NSException has call stack symbols");
        CHECK([[caught callStackReturnAddresses] count] == [[caught callStackSymbols] count],
              "a thrown NSException has one return address per symbol");
    }

    // The same for an NSException subclass
    {
        MyException *thrown = [[[MyException alloc] initWithName: @"Sub" reason: @"sub reason" userInfo: nil] autorelease];
        id caught = nil;
        @try {
            @throw thrown;
        } @catch (id other) {
            caught = other;
        }
        CHECK(caught == thrown, "the caught NSException subclass instance is the thrown object");
        CHECK([[caught callStackSymbols] count] > 0, "a thrown NSException subclass has call stack symbols");
    }

    // A root class, last: it answers retain and release only, so it does not respond to isKindOfClass:
    {
        id thrown = [RootThrowable alloc];
        id caught = nil;
        @try {
            @throw thrown;
        } @catch (id other) {
            caught = other;
        }
        CHECK(caught == thrown, "a thrown root class instance is caught as the same object");
        object_dispose(thrown);
    }

    [pool release];
    printf("%s\n", failures == 0 ? "PASS" : "FAIL");
    return failures != 0;
}
