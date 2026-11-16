//
//  NSObject.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSException.h>
#import "CFString.h"
#import "NSZombie.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#include <malloc/malloc.h>

//#import <libv/libv.h>
#define _GETENV(a,b) 0

#define SYMBOL_HERE_IN_3(sym, vers, n)                             \
	OBJC_EXPORT const char here_ ##n __asm__("$ld$add$os" #vers "$" #sym); const char here_ ##n = 0
#define SYMBOL_HERE_IN_2(sym, vers, n)     \
	SYMBOL_HERE_IN_3(sym, vers, n)
#define SYMBOL_HERE_IN(sym, vers)                  \
	SYMBOL_HERE_IN_2(sym, vers, __COUNTER__)

#if __OBJC2__
# define NSOBJECT_HERE_IN(vers)                       \
	SYMBOL_HERE_IN(_OBJC_CLASS_$_NSObject, vers);     \
	SYMBOL_HERE_IN(_OBJC_METACLASS_$_NSObject, vers); \
	SYMBOL_HERE_IN(_OBJC_IVAR_$_NSObject.isa, vers)
#else
# define NSOBJECT_HERE_IN(vers)                       \
	    SYMBOL_HERE_IN(.objc_class_name_NSObject, vers)
#endif

#if TARGET_OS_IOS

NSOBJECT_HERE_IN(2.0);
NSOBJECT_HERE_IN(2.1);
NSOBJECT_HERE_IN(2.2);
NSOBJECT_HERE_IN(3.0);
NSOBJECT_HERE_IN(3.1);
NSOBJECT_HERE_IN(3.2);
NSOBJECT_HERE_IN(4.0);
NSOBJECT_HERE_IN(4.1);
NSOBJECT_HERE_IN(4.2);
NSOBJECT_HERE_IN(4.3);
NSOBJECT_HERE_IN(5.0);
NSOBJECT_HERE_IN(5.1);

#elif TARGET_OS_MAC

NSOBJECT_HERE_IN(10.0);
NSOBJECT_HERE_IN(10.1);
NSOBJECT_HERE_IN(10.2);
NSOBJECT_HERE_IN(10.3);
NSOBJECT_HERE_IN(10.4);
NSOBJECT_HERE_IN(10.5);
NSOBJECT_HERE_IN(10.6);
NSOBJECT_HERE_IN(10.7);

#endif

void __CFZombifyNSObject(void) {
    Class cls = objc_lookUpClass("NSObject");
    Method dealloc_zombie = class_getInstanceMethod(cls, @selector(__dealloc_zombie));
    Method dealloc = class_getInstanceMethod(cls, @selector(dealloc));
    method_exchangeImplementations(dealloc_zombie, dealloc);
}

#if !__OBJC2__
// With the legacy Objective-C runtime (i386) class Protocol derives from Object, which has no
// memory management and none of the other basic NSObject messages. Protocol objects still have to
// work as ordinary objects: ARC-compiled code retains and releases them (for instance a Protocol *
// held in a strong variable), and containers and proxies send them -description and the like.
// Give Protocol the NSObject implementations of the messages it does not answer itself.
void __CFInitializeProtocolObjectMethods(void) {
    static const char *const names[] = {
        "retain", "release", "autorelease", "retainCount", "zone", "description", "superclass",
        "respondsToSelector:", "conformsToProtocol:", "isKindOfClass:", "isMemberOfClass:", "isProxy",
        "performSelector:", "performSelector:withObject:", "performSelector:withObject:withObject:",
    };
    Class protocol = objc_lookUpClass("Protocol");
    Class nsobject = objc_lookUpClass("NSObject");
    if (protocol == Nil || nsobject == Nil)
        return;
    for (Class cls = protocol; cls != Nil; cls = class_getSuperclass(cls)) {
        if (cls == nsobject)
            return;  // derives from NSObject (modern runtime layout): nothing to add
    }
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        SEL sel = sel_registerName(names[i]);
        if (class_getInstanceMethod(protocol, sel) != NULL)
            continue;
        Method method = class_getInstanceMethod(nsobject, sel);
        if (method != NULL)
            class_addMethod(protocol, sel, method_getImplementation(method), method_getTypeEncoding(method));
    }
    class_addProtocol(protocol, @protocol(NSObject));
}
#endif

static void NSUnrecognizedForwarding() { __asm__("int3"); }

@implementation NSObject (NSObject)

+ (void)doesNotRecognizeSelector:(SEL)sel
{
    if (_GETENV(BOOL, "NSUnrecognizedForwardingDisabled"))
    {
        RELEASE_LOG("+[%s %s]: unrecognized selector sent to instance %p; set a breakpoint on NSUnrecognizedForwarding to debug", class_getName(self), sel_getName(sel), self);
        NSUnrecognizedForwarding();
    }
    else
    {
        // DONT EVEN THINK ABOUT REMOVING/HACKING AROUND THIS!
        // EVER!
        // ...
        // yes, I mean YOU!
        [NSException raise:NSInvalidArgumentException format:@"+[%s %s]: unrecognized selector sent to instance %p", class_getName(self), sel_getName(sel), self];
    }
}

- (void)doesNotRecognizeSelector:(SEL)sel
{
    if (_GETENV(BOOL, "NSUnrecognizedForwardingDisabled"))
    {
        RELEASE_LOG("+[%s %s]: unrecognized selector sent to instance %p; set a breakpoint on NSUnrecognizedForwarding to debug", object_getClassName(self), sel_getName(sel), self);
        NSUnrecognizedForwarding();
    }
    else
    {
        // DONT EVEN THINK ABOUT REMOVING/HACKING AROUND THIS!
        // EVER!
        // ...
        // yes, I mean YOU!
        [NSException raise:NSInvalidArgumentException format:@"-[%s %s]: unrecognized selector sent to instance %p", object_getClassName(self), sel_getName(sel), self];
    }
}

+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)sel
{
    if (sel == NULL)
    {
        return nil;
    }

    Method m = class_getInstanceMethod(self, sel);

    if (m == NULL)
    {
        return nil;
    }

    return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
}

+ (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    if (sel == NULL)
    {
        return nil;
    }

    Method m = class_getClassMethod(self, sel);

    if (m == NULL)
    {
        return nil;
    }

    return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
}


- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    if (sel == NULL)
    {
        return nil;
    }

    Method m = class_getInstanceMethod(object_getClass(self), sel);

    if (m == NULL)
    {
        return nil;
    }

    return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
}

+ (NSString *)description
{
    CFStringRef description = CFStringCreateWithCString(kCFAllocatorDefault, class_getName(self), kCFStringEncodingUTF8);
    return [(NSString *)description autorelease];
}

- (NSString *)description
{
    CFStringRef description = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("<%s: %p>"), object_getClassName(self), self);
    return [(NSString *)description autorelease];
}

+ (BOOL)implementsSelector:(SEL)selector
{
    if (selector == NULL)
    {
        [NSException raise:NSInvalidArgumentException format:@"selector cannot be NULL"];
        return NO;
    }

    return class_getMethodImplementation(object_getClass(self), selector) != (IMP)&_objc_msgForward;
}

- (BOOL)implementsSelector:(SEL)selector
{
    if (selector == NULL)
    {
        [NSException raise:NSInvalidArgumentException format:@"selector cannot be NULL"];
        return NO;
    }

    // sneaky! this calls [self class]!!
    return class_getMethodImplementation([self class], selector) != (IMP)&_objc_msgForward;
}

+ (BOOL)instancesImplementSelector:(SEL)selector
{
    if (selector == NULL)
    {
        [NSException raise:NSInvalidArgumentException format:@"selector cannot be NULL"];
        return NO;
    }

    return class_getMethodImplementation(self, selector) != (IMP)&_objc_msgForward;
}

+ (void)forwardInvocation:(NSInvocation *)inv
{
    [self doesNotRecognizeSelector:[inv selector]];
}

- (void)forwardInvocation:(NSInvocation *)inv
{
    [self doesNotRecognizeSelector:[inv selector]];
}

- (void)__dealloc_zombie
{
    const char *className = object_getClassName(self);
    char *zombieClassName = NULL;
    do {
        if (asprintf(&zombieClassName, "%s%s", ZOMBIE_PREFIX, className) == -1)
        {
            break;
        }

        Class zombieClass = objc_getClass(zombieClassName);

        if (zombieClass == Nil)
        {
            zombieClass = objc_duplicateClass(objc_getClass(ZOMBIE_PREFIX), zombieClassName, 0);
        }

        if (zombieClass == Nil)
        {
            break;
        }

        objc_destructInstance(self);

        object_setClass(self, zombieClass);

    } while (0);

    if (zombieClassName != NULL)
    {
        free(zombieClassName);
    }
}

@end

@implementation NSObject (NSCoderMethods)

- (BOOL)_allowsDirectEncoding
{
    return NO;
}

+ (NSInteger)version
{
    return class_getVersion(self);
}

+ (void)setVersion:(NSInteger)aVersion
{
    class_setVersion(self, aVersion);
}

- (Class)classForCoder
{
    return [self class];
}

- (id)replacementObjectForCoder:(NSCoder *)aCoder
{
    return self;
}

- (id)awakeAfterUsingCoder:(NSCoder *)aDecoder
{
    return self;
}

@end

@implementation NSObject (__NSIsKinds)

- (BOOL)isNSValue__
{
    return NO;
}

- (BOOL)isNSTimeZone__
{
    return NO;
}

- (BOOL)isNSString__
{
    return NO;
}

- (BOOL)isNSSet__
{
    return NO;
}

- (BOOL)isNSOrderedSet__
{
    return NO;
}

- (BOOL)isNSNumber__
{
    return NO;
}

- (BOOL)isNSDictionary__
{
    return NO;
}

- (BOOL)isNSDate__
{
    return NO;
}

- (BOOL)isNSData__
{
    return NO;
}

- (BOOL)isNSArray__
{
    return NO;
}

@end
