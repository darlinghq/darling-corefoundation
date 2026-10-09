#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

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
    }
    printf("%d failure(s)\n", failures);
    return failures != 0;
}
