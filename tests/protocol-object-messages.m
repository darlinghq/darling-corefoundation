// Copyright (C) 2026 Lubos Dolezel
//
// Protocol objects behave as ordinary objects: they can be retained and released (also through the
// runtime entry points that ARC-compiled code uses for strong variables), kept in collections, and
// answer the basic NSObject messages. With the legacy Objective-C runtime (i386) Protocol derives
// from Object, which has none of these. Checked on Mac OS X 10.14.4 (i386, x86_64) and macOS 26.7.3.
// Build without -fobjc-arc.
#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

@protocol ProtocolMessagesProbe
- (void)hello;
@end

// The runtime entry points ARC-compiled code uses for a strong variable.
extern id objc_retain(id);
extern void objc_release(id);
extern void objc_storeStrong(id *, id);

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
    @autoreleasepool
    {
        id p = @protocol(ProtocolMessagesProbe);

        id strong = nil;
        objc_storeStrong(&strong, p);
        CHECK(strong == p);
        objc_storeStrong(&strong, nil);
        CHECK(objc_retain(p) == p);
        objc_release(p);

        NSUInteger count = [p retainCount];
        CHECK([p retain] == p);
        CHECK([p retain] == p);
        CHECK([p retainCount] == count + 2);
        [p release];
        [p release];
        CHECK([p retainCount] == count);
        [p retain];
        CHECK([p autorelease] == p);

        CHECK([p zone] != NULL);
        CHECK([p isKindOfClass: [Protocol class]]);
        CHECK([p isMemberOfClass: [Protocol class]]);
        CHECK(![p isProxy]);
        CHECK([p conformsToProtocol: @protocol(NSObject)]);
        CHECK([p respondsToSelector: @selector(name)]);
        CHECK(![p respondsToSelector: @selector(noSuchSelectorOnProtocol)]);
        CHECK(strcmp((const char *)[p performSelector: @selector(name)], "ProtocolMessagesProbe") == 0);
        CHECK([p isEqual: @protocol(ProtocolMessagesProbe)]);
        NSString *description = [p description];
        CHECK([description hasPrefix: @"<Protocol: "]);

        NSArray *array = [NSArray arrayWithObject: p];
        CHECK([array objectAtIndex: 0] == p);
        NSSet *set = [NSSet setWithObject: p];
        CHECK([set containsObject: p]);
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
