#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>

static int failures;

static int s_nullRetains = 0;
static id (*s_origNullRetain)(id, SEL) = NULL;

static id s_swizzledNullRetain(id selfRef, SEL _cmd)
{
    s_nullRetains++;
    return s_origNullRetain(selfRef, _cmd);
}

static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static void check_key_copied(const char *label, NSDictionary *dict, NSMutableString *key)
{
    [key setString:@"changed"];
    check_result(label, [dict objectForKey:@"original"] != nil
        && [dict objectForKey:@"changed"] == nil
        && [[[dict allKeys] firstObject] isEqualToString:@"original"]);
}

// Source dictionary that retains (does not copy) its keys, so the receiver must do the copy.
static NSDictionary *non_copying_dictionary(id key, id value)
{
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(d, (__bridge const void *)key, (__bridge const void *)value);
    return CFBridgingRelease(d);
}

int main(void)
{
    @autoreleasepool
    {
        NSMutableString *key = [NSMutableString stringWithString:@"original"];
        NSDictionary *d = [NSDictionary dictionaryWithObjects:@[@1] forKeys:@[key]];
        check_key_copied("dictionaryWithObjects:forKeys: (immutable)", d, key);

        key = [NSMutableString stringWithString:@"original"];
        d = [NSDictionary dictionaryWithObject:@1 forKey:key];
        check_key_copied("dictionaryWithObject:forKey:", d, key);

        key = [NSMutableString stringWithString:@"original"];
        d = [[NSMutableDictionary alloc] initWithObjects:@[@1] forKeys:@[key]];
        check_key_copied("initWithObjects:forKeys: (mutable)", d, key);

        key = [NSMutableString stringWithString:@"original"];
        d = @{ key: @1 };
        check_key_copied("literal", d, key);

        key = [NSMutableString stringWithString:@"original"];
        NSDictionary *src = non_copying_dictionary(key, @1);
        d = [[NSDictionary alloc] initWithDictionary:src];
        check_key_copied("initWithDictionary:", d, key);

        key = [NSMutableString stringWithString:@"original"];
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        [m setObject:@1 forKey:key];
        check_key_copied("setObject:forKey:", m, key);

        key = [NSMutableString stringWithString:@"original"];
        m = [NSMutableDictionary dictionary];
        m[key] = @1;
        check_key_copied("subscripting", m, key);

        key = [NSMutableString stringWithString:@"original"];
        m = [NSMutableDictionary dictionary];
        [m setValue:@1 forKey:(NSString *)key];
        check_key_copied("setValue:forKey:", m, key);

        key = [NSMutableString stringWithString:@"original"];
        m = [NSMutableDictionary dictionary];
        [m addEntriesFromDictionary:non_copying_dictionary(key, @1)];
        check_key_copied("addEntriesFromDictionary:", m, key);

        key = [NSMutableString stringWithString:@"original"];
        m = [NSMutableDictionary dictionary];
        [m setObject:@1 forKey:key];
        [key appendString:@"X"];
        check_result("lookup by original value after mutation", [m objectForKey:@"original"] != nil);

        BOOL raised = NO;
        @try { [m setObject:@1 forKey:(id<NSCopying>)[[NSObject alloc] init]]; }
        @catch (NSException *e) { raised = [[e name] isEqualToString:NSInvalidArgumentException]; }
        check_result("setObject:forKey: raises for non-NSCopying key", raised);

        raised = NO;
        id bad = [[NSObject alloc] init];
        @try { (void)[NSDictionary dictionaryWithObjects:@[@1] forKeys:@[bad]]; }
        @catch (NSException *e) { raised = [[e name] isEqualToString:NSInvalidArgumentException]; }
        check_result("dictionaryWithObjects:forKeys: raises for non-NSCopying key", raised);

        NSNull *nullKey = [NSNull null];
        NSDictionary *dNull = [NSDictionary dictionaryWithObject:@1 forKey:nullKey];
        check_result("dictionaryWithObject:forKey: with NSNull key", [dNull objectForKey:nullKey] != nil && [dNull count] == 1);

        NSMutableDictionary *mNull = [NSMutableDictionary dictionary];
        [mNull setObject:@1 forKey:nullKey];
        check_result("setObject:forKey: with NSNull key", [mNull objectForKey:nullKey] != nil && [mNull count] == 1);

        mNull[nullKey] = @2;
        check_result("subscripting with NSNull key", [mNull objectForKey:nullKey] != nil && [mNull[nullKey] isEqual:@2]);

        NSDictionary *literalNull = @{ nullKey: @1 };
        check_result("literal with NSNull key", [literalNull objectForKey:nullKey] != nil && [literalNull count] == 1);

        Method mRetain = class_getInstanceMethod([NSNull class], @selector(retain));
        s_origNullRetain = (id (*)(id, SEL))method_getImplementation(mRetain);
        method_setImplementation(mRetain, (IMP)s_swizzledNullRetain);

        s_nullRetains = 0;
        NSNull *nCopy = [nullKey copy];
        [nCopy release];
        check_result("-[NSNull copy] dispatches retain (+1 contract)", s_nullRetains == 1);

        method_setImplementation(mRetain, (IMP)s_origNullRetain);
    }
    printf("%d failure(s)\n", failures);
    return failures != 0;
}
