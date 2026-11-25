// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: +[NSError setUserInfoValueProviderForDomain:provider:]
// (https://developer.apple.com/documentation/foundation/nserror/setuserinfovalueproviderfordomain(_:provider:)).
// An error's accessors, and CFError's, ask the provider of its domain for a
// key that its user info lacks; the user info itself is unchanged. Expected
// values were observed on macOS 26.7.3 (x86_64) with the same inputs.
#import <Foundation/Foundation.h>

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        NSString *domain = @"ValueProviderTestDomain";
        NSMutableArray *asked = [NSMutableArray array];

        report("no provider at first", [NSError userInfoValueProviderForDomain: domain] == nil);
        [NSError setUserInfoValueProviderForDomain: domain provider: ^id(NSError *error, NSString *key) {
            [asked addObject: key];
            if ([key isEqualToString: NSLocalizedFailureReasonErrorKey])
                return @"reason";
            if ([key isEqualToString: NSHelpAnchorErrorKey])
                return @"anchor";
            if ([key isEqualToString: NSLocalizedRecoveryOptionsErrorKey])
                return @[ @"option" ];
            if ([key isEqualToString: NSLocalizedRecoverySuggestionErrorKey])
                return @"provided";
            return nil;
        }];
        report("the provider is kept", [NSError userInfoValueProviderForDomain: domain] != nil);
        report("only for its domain", [NSError userInfoValueProviderForDomain: @"OtherTestDomain"] == nil);

        NSError *error = [NSError errorWithDomain: domain code: 5
                                         userInfo: @{ NSLocalizedRecoverySuggestionErrorKey: @"own" }];
        report("localizedFailureReason", [error.localizedFailureReason isEqualToString: @"reason"]);
        report("helpAnchor", [error.helpAnchor isEqualToString: @"anchor"]);
        report("localizedRecoveryOptions", [error.localizedRecoveryOptions isEqual: @[ @"option" ]]);
        report("recoveryAttempter: the provider gives nil", error.recoveryAttempter == nil);
        report("localizedDescription: from the failure reason",
               [error.localizedDescription isEqualToString: @"The operation couldn’t be completed. reason"]);

        [asked removeAllObjects];
        report("the user info's value comes first", [error.localizedRecoverySuggestion isEqualToString: @"own"]
               && [asked count] == 0);
        report("the user info is unchanged", [error.userInfo count] == 1
               && [error.userInfo objectForKey: NSLocalizedFailureReasonErrorKey] == nil);

        CFStringRef reason = CFErrorCopyFailureReason((CFErrorRef) error);
        report("CFErrorCopyFailureReason", reason != NULL && [(NSString *) reason isEqualToString: @"reason"]);
        if (reason != NULL)
            CFRelease(reason);
        CFStringRef description = CFErrorCopyDescription((CFErrorRef) error);
        report("CFErrorCopyDescription", description != NULL
               && [(NSString *) description isEqualToString: @"The operation couldn’t be completed. reason"]);
        if (description != NULL)
            CFRelease(description);

        [NSError setUserInfoValueProviderForDomain: domain provider: nil];
        report("nil removes it", [NSError userInfoValueProviderForDomain: domain] == nil
               && error.localizedFailureReason == nil);
    }
    return failures != 0;
}
