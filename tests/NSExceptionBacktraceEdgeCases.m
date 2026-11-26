#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

static void expect(BOOL cond, const char *msg) {
    if (!cond) {
        printf("FAIL: %s\n", msg);
        fflush(stdout);
        exit(1);
    }
}

int main(void) {
#ifdef __i386__
    // 32-bit processes use the legacy exception model: -[NSException _installStackTraceKeyIfNeeded] is not
    // called when an exception is thrown (no exception preprocessor), so there is nothing to test.
    puts("SKIP: no stack trace key installation on i386");
    return 0;
#endif
    @autoreleasepool {
        const char *mode = getenv("TEST_BACKTRACE_MODE");
        @try {
            [NSException raise:@"TestException" format:@"edge mode=%s", mode ? mode : "real"];
        } @catch (NSException *ex) {
            NSArray<NSString *> *syms = [ex callStackSymbols];
            NSArray<NSNumber *> *addrs = [ex callStackReturnAddresses];
            if (mode && (mode[0] == '0' || mode[0] == '1')) {
                expect(syms != nil && [syms count] == 0, "count <= 1 should yield empty callStackSymbols");
                expect(addrs != nil && [addrs count] == 0, "count <= 1 should yield empty callStackReturnAddresses");
            } else if (mode && mode[0] == 'n') {
                /* backtrace_symbols == NULL: _installStackTraceKeyIfNeeded returns NO, arrays remain empty/nil without crashing */
                expect(syms == nil || [syms count] == 0, "NULL backtrace_symbols must not crash");
            } else if (mode && mode[0] == '2') {
                expect([syms count] == 1 && [addrs count] == 1, "invalid UTF-8 symbol should fall back to formatted address");
                expect([syms[0] length] > 0, "fallback symbol string should be non-empty");
            }
            printf("PASS: mode=%s syms=%lu addrs=%lu\n",
                   mode ? mode : "real",
                   (unsigned long)[syms count],
                   (unsigned long)[addrs count]);
        }
    }
    return 0;
}
