#import <Foundation/Foundation.h>
#include <CoreFoundation/CFURLEnumerator.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;

static void check_result(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    fflush(stdout);
    failures += !ok;
}

static BOOL contains(CFStringRef haystack, CFStringRef needle)
{
    return haystack != NULL && CFStringFind(haystack, needle, 0).location != kCFNotFound;
}

// The type checks run before describing the error, so a pre-fix build reports FAIL before it crashes.
static void check_posix_error(const char *label, CFErrorRef error, CFIndex expectedErrno)
{
    char text[256];
    snprintf(text, sizeof(text), "%s: error is POSIX with the errno", label);
    check_result(text, error != NULL && CFEqual(CFErrorGetDomain(error), kCFErrorDomainPOSIX) && CFErrorGetCode(error) == expectedErrno);
    if (error == NULL)
        return;

    CFDictionaryRef userInfo = CFErrorCopyUserInfo(error);
    CFTypeRef underlying = userInfo != NULL ? CFDictionaryGetValue(userInfo, kCFErrorUnderlyingErrorKey) : NULL;
    BOOL isError = underlying != NULL && CFGetTypeID(underlying) == CFErrorGetTypeID();
    snprintf(text, sizeof(text), "%s: underlying error is a CFError", label);
    check_result(text, isError);
    snprintf(text, sizeof(text), "%s: underlying error is POSIX with the errno", label);
    check_result(text, isError && CFEqual(CFErrorGetDomain((CFErrorRef)underlying), kCFErrorDomainPOSIX) && CFErrorGetCode((CFErrorRef)underlying) == expectedErrno);

    NSLog(@"%s: %@", label, (NSError *)error);
    CFStringRef description = CFCopyDescription(error);
    snprintf(text, sizeof(text), "%s: description shows the underlying error", label);
    check_result(text, contains(description, CFSTR("NSUnderlyingError=0x")));
    if (description != NULL)
        CFRelease(description);
    if (userInfo != NULL)
        CFRelease(userInfo);
}

static void check_url_resource_error(NSString *base)
{
    NSURL *missing = [NSURL fileURLWithPath:[base stringByAppendingPathComponent:@"missing"]];
    NSError *error = nil;
    NSDictionary *values = [missing resourceValuesForKeys:@[NSURLIsRegularFileKey] error:&error];
    check_result("NSURL missing file returns nil", values == nil);
    check_posix_error("NSURL missing file", (CFErrorRef)error, ENOENT);
}

static void check_enumerator_error(NSString *base)
{
    NSString *locked = [base stringByAppendingPathComponent:@"locked"];
    if (mkdir([locked fileSystemRepresentation], 0) != 0) {
        check_result("enumerator: create unreadable directory", NO);
        return;
    }
    if (access([locked fileSystemRepresentation], R_OK) == 0) {
        check_result("enumerator: unreadable directory is unreadable (not running as root)", NO);
        rmdir([locked fileSystemRepresentation]);
        return;
    }

    CFURLEnumeratorRef enumerator = CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault, (CFURLRef)[NSURL fileURLWithPath:base], kCFURLEnumeratorDefaultBehavior, NULL);
    check_result("enumerator: created for the base directory", enumerator != NULL);
    CFErrorRef error = NULL;
    CFURLEnumeratorResult result = kCFURLEnumeratorEnd;
    while (enumerator != NULL && error == NULL) {
        CFURLRef url = NULL;
        result = CFURLEnumeratorGetNextURL(enumerator, &url, &error);
        if (url != NULL)
            CFRelease(url);
        if (result == kCFURLEnumeratorEnd)
            break;
    }
    check_result("enumerator: unreadable directory reports an error", result == kCFURLEnumeratorError);
    check_posix_error("enumerator unreadable directory", error, EACCES);
    if (error != NULL)
        CFRelease(error);
    if (enumerator != NULL)
        CFRelease(enumerator);
    rmdir([locked fileSystemRepresentation]);
}

static void check_non_error_underlying_value(void)
{
    const void *key = kCFErrorUnderlyingErrorKey;
    const void *value = CFSTR("bare string");
    CFErrorRef error = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, kCFErrorDomainPOSIX, EIO, &key, &value, 1);
    CFStringRef description = CFCopyDescription(error);
    check_result("CFString underlying value is described as a value", contains(description, CFSTR("NSUnderlyingError=bare string")));
    if (description != NULL)
        CFRelease(description);
    CFRelease(error);

    NSError *nsError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:@{NSUnderlyingErrorKey: @"bare NSString"}];
    check_result("NSString underlying value is described as a value", [[nsError description] rangeOfString:@"NSUnderlyingError=bare NSString"].location != NSNotFound);

    NSError *inner = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
    NSError *outer = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:@{NSUnderlyingErrorKey: inner}];
    check_result("NSError underlying value is still described as an error", [[outer description] rangeOfString:@"NSUnderlyingError=0x"].location != NSNotFound);
}

int main(void)
{
    @autoreleasepool {
        char temp[] = "/tmp/darling-cferror-underlying-XXXXXX";
        char *root = mkdtemp(temp);
        if (root == NULL) {
            perror("mkdtemp");
            return 2;
        }
        NSString *base = [NSString stringWithUTF8String:root];
        check_url_resource_error(base);
        check_enumerator_error(base);
        check_non_error_underlying_value();
        rmdir(root);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
