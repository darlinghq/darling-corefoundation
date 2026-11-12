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

CF_PRIVATE
@interface __NSCFError : __NSCFType
@end


NSString *const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
NSString *const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
NSString *const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
NSString *const NSMachErrorDomain = @"NSMachErrorDomain";
NSString *const NSUnderlyingErrorKey = @"NSUnderlyingError";
NSString *const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
NSString *const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
NSString *const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
NSString *const NSLocalizedRecoveryOptionsErrorKey = @"NSLocalizedRecoveryOptions";
NSString *const NSRecoveryAttempterErrorKey = @"NSRecoveryAttempter";
NSString *const NSHelpAnchorErrorKey = @"NSHelpAnchor";
NSString *const NSStringEncodingErrorKey = @"NSStringEncoding";
NSString *const NSURLErrorKey = @"NSURL";
NSString *const NSFilePathErrorKey = @"NSFilePath";
NSString *const NSDebugDescriptionErrorKey = @"NSDebugDescription";
NSString *const NSLocalizedFailureErrorKey = @"NSLocalizedFailure";

static NSError *_outOfmemoryError = nil;

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

+ (id)errorWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict
{
    return [[[self alloc] initWithDomain:domain code:code userInfo:dict] autorelease];
}

- (id)initWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict
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

- (NSString *)localizedDescription
{
    NSString *desc = [[self userInfo][NSLocalizedDescriptionKey] copy];

    if (desc == nil)
    {
        desc = (NSString *)_CFErrorCreateLocalizedDescription((CFErrorRef)self);
        if (desc == nil)
        {
            desc = (NSString *)CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("Operation could not be completed. %@ %d"), [self domain], [self code]);
        }
    }
    
    return [desc autorelease];
}

- (NSString *)localizedFailureReason
{
    return [self userInfo][NSLocalizedFailureReasonErrorKey];
}

- (NSString *)localizedRecoverySuggestion
{
    return [self userInfo][NSLocalizedRecoverySuggestionErrorKey];
}

- (NSArray *)localizedRecoveryOptions
{
    return [self userInfo][NSLocalizedRecoveryOptionsErrorKey];
}

- (id)recoveryAttempter
{
    return [self userInfo][NSRecoveryAttempterErrorKey];
}

- (NSString *)helpAnchor
{
    return [self userInfo][NSHelpAnchorErrorKey];
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
