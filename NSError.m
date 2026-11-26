//
//  NSError.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <objc/runtime.h>
#import <Foundation/NSError.h>
#import <Foundation/NSError_Private.h>

#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSValue.h>
#import "ForFoundationOnly.h"
#import "NSObjectInternal.h"
#import "CFInternal.h"
#include <pthread.h>

CF_PRIVATE
@interface __NSCFError : __NSCFType
@end


// These are CoreFoundation's private copies, used by the NSError implementation in this
// image. The exported constants (NSPOSIXErrorDomain and the rest of NSError.h) are defined by
// Foundation, which is where binaries built for macOS import them from.
CF_PRIVATE NSString *const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
CF_PRIVATE NSString *const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
CF_PRIVATE NSString *const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
CF_PRIVATE NSString *const NSMachErrorDomain = @"NSMachErrorDomain";
CF_PRIVATE NSString *const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
CF_PRIVATE NSString *const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
CF_PRIVATE NSString *const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
CF_PRIVATE NSString *const NSLocalizedRecoveryOptionsErrorKey = @"NSLocalizedRecoveryOptions";
CF_PRIVATE NSString *const NSRecoveryAttempterErrorKey = @"NSRecoveryAttempter";
CF_PRIVATE NSString *const NSHelpAnchorErrorKey = @"NSHelpAnchor";

static NSError *_outOfmemoryError = nil;

// The user info value providers, by domain.
static NSMutableDictionary *_valueProviders = nil;
static pthread_mutex_t _valueProvidersLock = PTHREAD_MUTEX_INITIALIZER;

static id (^copyValueProvider(NSString *domain))(NSError *, NSString *)
{
    pthread_mutex_lock(&_valueProvidersLock);
    id (^provider)(NSError *, NSString *) = [[_valueProviders objectForKey:domain] retain];
    pthread_mutex_unlock(&_valueProvidersLock);
    return provider;
}

CF_PRIVATE CFTypeRef _CFErrorCopyValueFromProvider(CFErrorRef err, CFStringRef key)
{
    id (^provider)(NSError *, NSString *) = copyValueProvider((NSString *)CFErrorGetDomain(err));
    if (provider == nil)
    {
        return NULL;
    }
    id value = [provider((NSError *)err, (NSString *)key) retain];
    [provider release];
    return (CFTypeRef)value;
}

// The user info's value for the key, or else the domain's value provider's.
static id userInfoValue(NSError *error, NSString *key)
{
    id value = [[error userInfo] objectForKey:key];
    if (value == nil)
    {
        value = [(id)_CFErrorCopyValueFromProvider((CFErrorRef)error, (CFStringRef)key) autorelease];
    }
    return value;
}

@implementation NSError

+ (void)initialize
{
    static dispatch_once_t once = 0L;
    dispatch_once(&once, ^{
        _outOfmemoryError = [[NSError errorWithDomain:NSPOSIXErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Out of memory"}] retain];
    });
}

+ (NSError *)_outOfMemoryError
{
    return _outOfmemoryError;
}

- (CFTypeID)_cfTypeID
{
    return CFErrorGetTypeID();
}

+ (instancetype)errorWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict
{
    return [[[self alloc] initWithDomain:domain code:code userInfo:dict] autorelease];
}

- (instancetype)initWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict
{
    self = [super init];

    if (self)
    {
        _code = code;
        _domain = [domain copy];
        _userInfo = [dict copy];
    }

    return self;
}

- (NSString *)domain
{
    return _domain;
}

- (NSInteger)code
{
    return _code;
}

- (NSDictionary *)userInfo
{
    return _userInfo;
}

- (NSString *)description
{
    return [(NSString *)_CFErrorCreateDebugDescription((CFErrorRef)self) autorelease];
}

+ (void)setUserInfoValueProviderForDomain:(NSString *)domain provider:(id (^)(NSError *, NSString *))provider
{
    pthread_mutex_lock(&_valueProvidersLock);
    if (provider != nil)
    {
        if (_valueProviders == nil)
        {
            _valueProviders = [[NSMutableDictionary alloc] init];
        }
        id copied = [provider copy];
        [_valueProviders setObject:copied forKey:domain];
        [copied release];
    }
    else
    {
        [_valueProviders removeObjectForKey:domain];
    }
    pthread_mutex_unlock(&_valueProvidersLock);
}

+ (id (^)(NSError *, NSString *))userInfoValueProviderForDomain:(NSString *)domain
{
    return [copyValueProvider(domain) autorelease];
}

- (NSString *)localizedDescription
{
    NSString *desc = [[self userInfo][NSLocalizedDescriptionKey] copy];

    if (desc == nil)
    {
        // Asks the value provider for the description and the failure reason.
        desc = (NSString *)_CFErrorCreateLocalizedDescription((CFErrorRef)self);
        if (desc == nil)
        {
            desc = (NSString *)CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("Operation could not be completed. %@ %d"), [self domain], [self code]);
        }
    }
    
    return [desc autorelease];
}

// The failure reason and the recovery suggestion come from the userInfo, or else from the callback registered
// for the error domain (see CFErrorSetCallBackForDomain), as the description does.
- (NSString *)localizedFailureReason
{
    return [(NSString *)_CFErrorCreateLocalizedFailureReason((CFErrorRef)self) autorelease];
}

- (NSString *)localizedRecoverySuggestion
{
    return [(NSString *)_CFErrorCreateLocalizedRecoverySuggestion((CFErrorRef)self) autorelease];
}

- (NSArray *)localizedRecoveryOptions
{
    return userInfoValue(self, NSLocalizedRecoveryOptionsErrorKey);
}

- (id)recoveryAttempter
{
    return userInfoValue(self, NSRecoveryAttempterErrorKey);
}

- (NSString *)helpAnchor
{
    return userInfoValue(self, NSHelpAnchorErrorKey);
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[NSError allocWithZone:zone] initWithDomain:[self domain] code:[self code] userInfo:[self userInfo]];
}

- (NSUInteger)hash
{
    return [_domain hash] + (NSUInteger)_code;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
    {
        return YES;
    }
    if (![other isKindOfClass:[NSError class]])
    {
        return NO;
    }
    if (_code != [other code] || ![_domain isEqual:[other domain]])
    {
        return NO;
    }
    // A missing user info and an empty one are the same.
    NSDictionary *otherInfo = [other userInfo];
    if ([_userInfo count] == 0 && [otherInfo count] == 0)
    {
        return YES;
    }
    return [_userInfo isEqual:otherInfo];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (![aDecoder allowsKeyedCoding])
    {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"NSError requires a keyed coder"];
        return nil;
    }
    NSString *domain = [aDecoder decodeObjectOfClass:objc_lookUpClass("NSString") forKey:@"NSDomain"];
    NSInteger code = [aDecoder decodeIntegerForKey:@"NSCode"];
    // Values in the user info may only be of these classes; an underlying
    // error is itself an NSError. NSString and NSNumber are looked up by name:
    // they live in Foundation, and the 32-bit runtime needs a link-time symbol
    // for a class named in source.
    NSSet *infoClasses = [NSSet setWithObjects:
        [NSDictionary class], [NSArray class], objc_lookUpClass("NSString"), objc_lookUpClass("NSNumber"),
        [NSData class], [NSDate class], [NSURL class], [NSError class], nil];
    NSDictionary *userInfo = [aDecoder decodeObjectOfClasses:infoClasses forKey:@"NSUserInfo"];
    if (domain == nil || (userInfo != nil && ![userInfo isKindOfClass:[NSDictionary class]]))
    {
        [self release];
        return nil;
    }
    return [self initWithDomain:domain code:code userInfo:userInfo];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (![aCoder allowsKeyedCoding])
    {
        [NSException raise:NSInvalidArgumentException format:@"NSError requires a keyed coder"];
    }
    [aCoder encodeObject:[self domain] forKey:@"NSDomain"];
    [aCoder encodeInteger:[self code] forKey:@"NSCode"];
    [aCoder encodeObject:[self userInfo] forKey:@"NSUserInfo"];
}

@end

@implementation NSError (NSErrorPrivateStuff)

+ (void)_setFileNameLocalizationEnabled:(BOOL)enabled
{
    // silently ignore it
}

@end

@implementation __NSCFError

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    return NO;
}

- (id)copyWithZone:(NSZone *)zone
{
    return (id)CFErrorCreate(kCFAllocatorDefault, (CFStringRef)[self domain], [self code], (CFDictionaryRef)[self userInfo]);
}

- (Class)classForCoder
{
    return [NSError class];
}

- (NSDictionary *)userInfo
{
    return [(NSDictionary *)CFErrorCopyUserInfo((CFErrorRef)self) autorelease];
}

- (NSString *)domain
{
    return (NSString *)CFErrorGetDomain((CFErrorRef)self);
}

- (NSInteger)code
{
    return CFErrorGetCode((CFErrorRef)self);
}

- (NSUInteger)retainCount
{
    return CFGetRetainCount((CFTypeRef)self);
}

- (BOOL)_isDeallocating
{
    return _CFIsDeallocating((CFTypeRef)self);
}

- (BOOL)_tryRetain
{
    return _CFTryRetain((CFTypeRef)self) != NULL;
}

- (oneway void)release
{
    CFRelease((CFTypeRef)self);
}

- (id)retain
{
    return (id)CFRetain((CFTypeRef)self);
}

- (NSUInteger)hash
{
    return CFHash((CFTypeRef)self);
}

- (BOOL)isEqual:(id)other
{
    if (other == nil)
    {
        return NO;
    }
    return CFEqual((CFTypeRef)self, (CFTypeRef)other);
}

@end
