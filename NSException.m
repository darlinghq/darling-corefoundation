//
//  NSException.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <Foundation/NSException.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import "CFString.h"
#import "CFNumber.h"
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <execinfo.h>

@interface NSException ()
- (BOOL)_installStackTraceKeyIfNeeded;
@end

typedef id (*objc_exception_preprocessor)(id exception);
extern objc_exception_preprocessor objc_setExceptionPreprocessor(objc_exception_preprocessor fn);

static NSException *__exceptionPreprocess(NSException *exception)
{
    // this is quite expensive (1/3 sec lag), when it can be made more performant (under 1/60 sec) this should be re-enabled
    // UPDATE(facekapow): i've re-enabled this even though nothing has really changed in the code, but from limited testing
    //                    it seems that this is pretty performant. besides, exceptions are just that: *exceptions*.
    //                    you shouldn't be constantly throwing around exceptions.
#if 1
    [exception _installStackTraceKeyIfNeeded];
#endif
    return exception;
}

static void NSExceptionInitializer() __attribute__((constructor));
static void NSExceptionInitializer()
{
#ifndef __i386__
    objc_setExceptionPreprocessor(&__exceptionPreprocess);
#endif
}

NSString *const NSGenericException = @"NSGenericException";
NSString *const NSRangeException = @"NSRangeException";
NSString *const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSString *const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
NSString *const NSMallocException = @"NSMallocException";

@implementation NSException

- (instancetype) init {
    [self release]; // initWithName:reason:userInfo: is the only acceptable init method
    return nil;
}

- (instancetype) initWithName: (NSExceptionName) name
                       reason: (NSString *) reason
                     userInfo: (NSDictionary *) userInfo
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _reason = [reason copy];
        _userInfo = [userInfo copy];
    }
    return self;
}

- (instancetype) copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (void) dealloc {
    [_name release];
    [_reason release];
    [_userInfo release];
    [_reserved release];
    [super dealloc];
}

- (void) raise {
    @throw self;
}

+ (void) raise: (NSExceptionName) name
        format: (NSString *) format, ...
{
    va_list args;
    va_start(args, format);
    CFStringRef reason = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL, (CFStringRef) format, args);
    va_end(args);
    NSException *exc = [self exceptionWithName: name
                                        reason: (NSString*)reason
                                      userInfo: nil];
    [exc raise];
    CFRelease(reason);
}

+ (void) raise: (NSExceptionName) name
        format: (NSString *) format
     arguments: (va_list) args
{
    CFStringRef reason = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL, (CFStringRef) format, args);
    NSException *exc = [self exceptionWithName: name
                                        reason: (NSString*)reason
                                      userInfo: nil];
    [exc raise];
    CFRelease(reason);
}

+ (NSException *) exceptionWithName: (NSExceptionName) name
                             reason: (NSString *) reason
                           userInfo: (NSDictionary *) userInfo
{
    return [[[self alloc] initWithName: name
                                reason: reason
                              userInfo: userInfo] autorelease];
}

- (NSExceptionName) name {
    return _name;
}

- (NSString *) reason {
    return _reason;
}

- (NSDictionary *) userInfo {
    return _userInfo;
}

- (BOOL) _installStackTraceKeyIfNeeded {
    if (_reserved == NULL) {
        _reserved = [[NSMutableDictionary alloc] init];
    }

    NSArray *callStackSymbols = nil;
    if (_userInfo != nil) {
        callStackSymbols = _userInfo[@"NSStackTraceKey"];
    }

    if (callStackSymbols == nil) {
        callStackSymbols = _reserved[@"callStackSymbols"];
    } else {
        _reserved[@"callStackSymbols"] = callStackSymbols;
    }

    if (callStackSymbols == nil) {
        void *stack[128] = { NULL };
        CFStringRef symbols[128] = { nil };
        CFNumberRef returnAddresses[128] = { nil };

        int count = backtrace(stack, sizeof(stack) / sizeof(stack[0]));
        char **sym = backtrace_symbols(stack, count);
        if (sym == NULL) {
            return NO;
        }

        // Make sure to skip this frame since it is just an instantiator.
        for (int i = 1; i < count; i++) {
            returnAddresses[i - 1] = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &stack[i]);
            symbols[i - 1] = CFStringCreateWithCString(kCFAllocatorDefault, sym[i], kCFStringEncodingUTF8);
        }

        free(sym);
        callStackSymbols = [[NSArray alloc] initWithObjects: (id *) symbols
                                                      count: count - 1];
        NSArray *callStackReturnAddresses = [[NSArray alloc] initWithObjects: (id *) returnAddresses
                                                                       count: count - 1];
        _reserved[@"callStackSymbols"] = callStackSymbols;
        _reserved[@"callStackReturnAddresses"] = callStackReturnAddresses;

        for (int i = 1; i < count; i++) {
            CFRelease(returnAddresses[i - 1]);
            CFRelease(symbols[i - 1]);
        }

        [callStackSymbols release];
        [callStackReturnAddresses release];
    }

    return callStackSymbols != nil;
}

- (NSArray *) callStackReturnAddresses {
    return _reserved[@"callStackReturnAddresses"];
}

- (NSArray *) callStackSymbols {
    return _reserved[@"callStackSymbols"];
}

- (NSString *) description {
    if (_reason != nil) {
        return _reason;
    }
    return _name;
}

@end
