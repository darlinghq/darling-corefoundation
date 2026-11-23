// Copyright (C) 2026 Lubos Dolezel
//
// -[NSDictionary initWithDictionary:copyItems:] and -mutableCopy of a dictionary that is not a CFDictionary
// (a subclass that implements only the primitive methods, like NSFileAttributes) leave the new dictionary the
// only extra owner of each value: one reference per value without copyItems, and the copies owned by the new
// dictionary alone with copyItems. Built without ARC.
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;
static int liveCopies;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
}

@interface Item : NSObject <NSCopying> {
    BOOL isCopy;
}
@end
@implementation Item
- (id)copyWithZone:(NSZone *)zone
{
    Item *c = [[Item alloc] init];
    c->isCopy = YES;
    liveCopies++;
    return c;
}
- (void)dealloc
{
    if (isCopy)
        liveCopies--;
    [super dealloc];
}
@end

// Implements only the primitives, so copies go through the generic NSDictionary code.
@interface Wrapper : NSDictionary {
    NSDictionary *backing;
}
- (id)initWithBacking:(NSDictionary *)b;
@end
@implementation Wrapper
- (id)initWithBacking:(NSDictionary *)b
{
    if ((self = [super init]))
        backing = [b retain];
    return self;
}
- (void)dealloc
{
    [backing release];
    [super dealloc];
}
- (NSUInteger)count { return [backing count]; }
- (id)objectForKey:(id)key { return [backing objectForKey:key]; }
- (NSEnumerator *)keyEnumerator { return [backing keyEnumerator]; }
@end

int main(void)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    Item *a = [[Item alloc] init], *b = [[Item alloc] init];
    NSDictionary *source = [NSDictionary dictionaryWithObjectsAndKeys:a, @"a", b, @"b", nil];
    Wrapper *wrapper = [[Wrapper alloc] initWithBacking:source];

    NSUInteger before = [a retainCount];
    NSMutableDictionary *m = [wrapper mutableCopy];
    expect([a retainCount] == before + 1, "mutableCopy: the copy owns each value once");
    [m release];
    expect([a retainCount] == before, "mutableCopy: releasing the copy gives the references back");

    NSUInteger bbefore = [b retainCount];
    NSMutableDictionary *n = [[NSMutableDictionary alloc] initWithDictionary:wrapper copyItems:NO];
    expect([b retainCount] == bbefore + 1, "initWithDictionary:copyItems:NO: the new dictionary owns each value once");
    [n release];
    expect([b retainCount] == bbefore, "initWithDictionary:copyItems:NO: releasing the copy gives back one reference per value");

    NSMutableDictionary *c = [[NSMutableDictionary alloc] initWithDictionary:wrapper copyItems:YES];
    expect(liveCopies == 2, "copyItems:YES makes one copy per value");
    [c release];
    expect(liveCopies == 0, "copyItems:YES: the copies are freed with the dictionary");

    NSDictionary *plain = [[NSDictionary alloc] initWithDictionary:source copyItems:YES];
    expect(liveCopies == 2, "copyItems:YES of a plain dictionary makes one copy per value");
    [plain release];
    expect(liveCopies == 0, "copyItems:YES of a plain dictionary: the copies are freed with it");

    [wrapper release];
    [a release];
    [b release];
    [pool drain];
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
