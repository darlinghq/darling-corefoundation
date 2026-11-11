#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    @autoreleasepool {
        const char *names[] = {
            "URLUserAllowedCharacterSet", "URLPasswordAllowedCharacterSet",
            "URLHostAllowedCharacterSet", "URLPathAllowedCharacterSet",
            "URLQueryAllowedCharacterSet", "URLFragmentAllowedCharacterSet"
        };
        // RFC 3986 unreserved characters plus component-specific delimiters.
        const char *unreserved =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
        const char *extra[] = {
            "!$&'()*+,;=", "!$&'()*+,;=", "!$&'()*+,;=:[]",
            "!$&'()*+,/:=@", "!$&'()*+,/:;=?@", "!$&'()*+,/:;=?@"
        };
        for (unsigned i = 0; i < 6; ++i) {
            SEL selector = sel_registerName(names[i]);
            assert([NSCharacterSet respondsToSelector:selector]);
            NSCharacterSet *set = [NSCharacterSet performSelector:selector];
            assert(set != nil);
            assert(set == [NSCharacterSet performSelector:selector]);
            for (unsigned c = 0; c < 128; ++c) {
                BOOL expected = c != 0 &&
                    (strchr(unreserved, c) != NULL || strchr(extra[i], c) != NULL);
                assert([set characterIsMember:(unichar)c] == expected);
            }
            assert(![set characterIsMember:0x00e9]);
            assert(![set characterIsMember:0x4e2d]);
            NSMutableCharacterSet *copy = [set mutableCopy];
            [copy addCharactersInString:@" %"];
            assert([copy characterIsMember:' ']);
            assert(![set characterIsMember:' ']);
            assert(![set characterIsMember:'%']);
            [copy release];
        }
    }
    puts("PASS: six URL character sets, ASCII membership and independent mutable copies");
    return 0;
}
