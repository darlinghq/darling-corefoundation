//
//  NSCharacterSet.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <dispatch/dispatch.h>
#import <Foundation/NSCharacterSet.h>
#import "NSCFType.h"
#import "CFInternal.h"
#import "NSObjectInternal.h"
#import "CFCharacterSetPriv.h"

extern Boolean __CFCharacterSetIsMutable(CFCharacterSetRef cset);
extern void CFCharacterSetFast(CFMutableCharacterSetRef theSet);
extern void CFCharacterSetCompact(CFMutableCharacterSetRef theSet);

CF_PRIVATE
@interface __NSCFCharacterSet : __NSCFType
@end

@implementation NSCharacterSet

// Match the URL component sets in swift-corelibs-foundation's
// CoreFoundation/URL.subproj/CFURLComponents_URIParser.c. In particular,
// host permits IPv6 brackets, while path excludes the RFC 1808 parameter
// separator ';'. These are immutable process-lifetime singletons.
+ (NSCharacterSet *)URLUserAllowedCharacterSet
{
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [[NSCharacterSet characterSetWithCharactersInString:
            @"!$&'()*+,-.0123456789;=ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"] retain];
    });
    return set;
}

+ (NSCharacterSet *)URLPasswordAllowedCharacterSet
{
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [[NSCharacterSet characterSetWithCharactersInString:
            @"!$&'()*+,-.0123456789;=ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"] retain];
    });
    return set;
}

+ (NSCharacterSet *)URLHostAllowedCharacterSet
{
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [[NSCharacterSet characterSetWithCharactersInString:
            @"!$&'()*+,-.0123456789:;=ABCDEFGHIJKLMNOPQRSTUVWXYZ[]_abcdefghijklmnopqrstuvwxyz~"] retain];
    });
    return set;
}

+ (NSCharacterSet *)URLPathAllowedCharacterSet
{
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [[NSCharacterSet characterSetWithCharactersInString:
            @"!$&'()*+,-./0123456789:=@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"] retain];
    });
    return set;
}

+ (NSCharacterSet *)URLQueryAllowedCharacterSet
{
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [[NSCharacterSet characterSetWithCharactersInString:
            @"!$&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"] retain];
    });
    return set;
}

+ (NSCharacterSet *)URLFragmentAllowedCharacterSet
{
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [[NSCharacterSet characterSetWithCharactersInString:
            @"!$&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"] retain];
    });
    return set;
}

+ (id)controlCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetControl);
}

+ (id)whitespaceCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetWhitespace);
}

+ (id)whitespaceAndNewlineCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetWhitespaceAndNewline);
}

+ (id)decimalDigitCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetDecimalDigit);
}

+ (id)letterCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetLetter);
}

+ (id)lowercaseLetterCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetLowercaseLetter);
}

+ (id)uppercaseLetterCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetUppercaseLetter);
}

+ (id)nonBaseCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetNonBase);
}

+ (id)alphanumericCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetAlphaNumeric);
}

+ (id)decomposableCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetDecomposable);
}

+ (id)illegalCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetIllegal);
}

+ (id)punctuationCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetPunctuation);
}

+ (id)capitalizedLetterCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetCapitalizedLetter);
}

+ (id)symbolCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetSymbol);
}

+ (id)newlineCharacterSet
{
    return (id)CFCharacterSetGetPredefined(kCFCharacterSetNewline);
}

+ (id)characterSetWithRange:(NSRange)range
{
    return [(NSCharacterSet *)CFCharacterSetCreateWithCharactersInRange(kCFAllocatorDefault, CFRangeMake(range.location, range.length)) autorelease];
}

+ (id)characterSetWithCharactersInString:(NSString *)string
{
    return [(NSCharacterSet *)CFCharacterSetCreateWithCharactersInString(kCFAllocatorDefault, (CFStringRef)string) autorelease];
}

+ (id)characterSetWithBitmapRepresentation:(NSData *)data
{
    return [(NSCharacterSet *)CFCharacterSetCreateWithBitmapRepresentation(kCFAllocatorDefault, (CFDataRef)data) autorelease];
}

+ (id)characterSetWithContentsOfFile:(NSString *)path
{
    return [self characterSetWithBitmapRepresentation:[NSData dataWithContentsOfMappedFile:path]];
}

- (id)init
{
    [self release];
    return (id)CFCharacterSetCreateWithCharactersInRange(kCFAllocatorDefault, CFRangeMake(0, 0));
}

- (BOOL)characterIsMember:(unichar)character
{
    NSRequestConcreteImplementation();
    return NO;
}

- (NSData *)bitmapRepresentation
{
    NSRequestConcreteImplementation();
    return nil;
}

- (NSCharacterSet *)invertedSet
{
    NSRequestConcreteImplementation();
    return nil;
}

- (BOOL)longCharacterIsMember:(UTF32Char)character
{
    NSRequestConcreteImplementation();
    return NO;
}

- (BOOL)isSupersetOfSet:(NSCharacterSet *)other
{
    NSRequestConcreteImplementation();
    return NO;
}

- (BOOL)hasMemberInPlane:(uint8_t)plane
{
    NSRequestConcreteImplementation();
    return NO;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

// Keyed archive layout: one of NSBuiltinID (a predefined set), NSRange (location
// in the high 32 bits, length in the low 32), NSString (a BMP-only set kept as a
// string) or NSBitmap (the bitmap representation); NSIsInverted marks an
// inverted builtin, range or string set. Predefined sets that CoreFoundation
// archives with their bitmap too (symbol, newline) use NSBitmap together with
// NSBuiltinID2 and NSIsInverted2.
static const NSUInteger kBitmapPlaneSize = 8192;
static const NSUInteger kMaxBitmapPlanes = 16;

static CFCharacterSetRef CreateCharacterSetFromArchive(NSCoder *coder)
{
    if (![coder allowsKeyedCoding])
    {
        NSData *bitmap = [coder decodeObject];
        if (![bitmap isKindOfClass:objc_lookUpClass("NSData")])
        {
            return NULL;
        }
        return CFCharacterSetCreateWithBitmapRepresentation(kCFAllocatorDefault, (CFDataRef)bitmap);
    }

    if ([coder containsValueForKey:@"NSBitmap"])
    {
        NSUInteger length = 0;
        const uint8_t *bytes = [coder decodeBytesForKey:@"NSBitmap" returnedLength:&length];
        // A bitmap is the BMP plane followed by (plane number, plane bits) pairs for other planes.
        if (bytes == NULL || length < kBitmapPlaneSize || (length - kBitmapPlaneSize) % (kBitmapPlaneSize + 1) != 0 ||
            (length - kBitmapPlaneSize) / (kBitmapPlaneSize + 1) > kMaxBitmapPlanes)
        {
            return NULL;
        }
        CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, length);
        CFCharacterSetRef set = CFCharacterSetCreateWithBitmapRepresentation(kCFAllocatorDefault, data);
        CFRelease(data);
        return set;
    }

    CFCharacterSetRef set = NULL;
    if ([coder containsValueForKey:@"NSBuiltinID"])
    {
        NSInteger identifier = [coder decodeIntegerForKey:@"NSBuiltinID"];
        if (identifier < kCFCharacterSetControl || identifier > kCFCharacterSetNewline)
        {
            return NULL;
        }
        set = (CFCharacterSetRef)CFRetain(CFCharacterSetGetPredefined((CFCharacterSetPredefinedSet)identifier));
    }
    else if ([coder containsValueForKey:@"NSRange"])
    {
        uint64_t packed = (uint64_t)[coder decodeInt64ForKey:@"NSRange"];
        uint64_t location = packed >> 32;
        uint64_t length = packed & 0xffffffffu;
        if (location + length > 0x110000)
        {
            return NULL;
        }
        set = CFCharacterSetCreateWithCharactersInRange(kCFAllocatorDefault, CFRangeMake((CFIndex)location, (CFIndex)length));
    }
    else if ([coder containsValueForKey:@"NSString"])
    {
        NSString *string = [coder decodeObjectOfClass:objc_lookUpClass("NSString") forKey:@"NSString"];
        if (string == nil)
        {
            return NULL;
        }
        set = CFCharacterSetCreateWithCharactersInString(kCFAllocatorDefault, (CFStringRef)string);
    }
    else
    {
        return NULL;
    }

    if ([coder decodeBoolForKey:@"NSIsInverted"])
    {
        CFCharacterSetRef inverted = CFCharacterSetCreateInvertedSet(kCFAllocatorDefault, set);
        CFRelease(set);
        set = inverted;
    }
    return set;
}

// self is a plain placeholder instance; the result is a CoreFoundation character set.
- (id)initWithCoder:(NSCoder *)aDecoder
{
    BOOL wantsMutable = [self isKindOfClass:[NSMutableCharacterSet class]];
    [self release];

    CFCharacterSetRef set = CreateCharacterSetFromArchive(aDecoder);
    if (set == NULL)
    {
        return nil;
    }
    if (wantsMutable && !__CFCharacterSetIsMutable(set))
    {
        CFCharacterSetRef mutableSet = CFCharacterSetCreateMutableCopy(kCFAllocatorDefault, set);
        CFRelease(set);
        set = mutableSet;
    }
    return (id)set;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    NSRequestConcreteImplementation();
}

- (id)copyWithZone:(NSZone *)zone
{
    NSRequestConcreteImplementation();
    return nil;
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    NSRequestConcreteImplementation();
    return nil;
}

- (CFTypeID)_cfTypeID
{
    return CFCharacterSetGetTypeID();
}

- (void)makeImmutable
{

}

- (BOOL)isMutable
{
    return NO;
}

- (CFCharacterSetRef)_expandedCFCharacterSet
{
    return NULL;
}

@end

@implementation NSMutableCharacterSet

+ (id)characterSetWithContentsOfFile:(NSString *)path
{
    return [[[NSCharacterSet characterSetWithContentsOfFile:path] mutableCopyWithZone:nil] autorelease];
}

+ (id)characterSetWithBitmapRepresentation:(NSData *)data
{
    return [[[NSCharacterSet characterSetWithBitmapRepresentation:data] mutableCopyWithZone:nil] autorelease];
}

+ (id)newlineCharacterSet
{
    return [[[NSCharacterSet newlineCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)symbolCharacterSet
{
    return [[[NSCharacterSet symbolCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)capitalizedLetterCharacterSet
{
    return [[[NSCharacterSet capitalizedLetterCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)punctuationCharacterSet
{
    return [[[NSCharacterSet punctuationCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)illegalCharacterSet
{
    return [[[NSCharacterSet illegalCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)decomposableCharacterSet
{
    return [[[NSCharacterSet decomposableCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)alphanumericCharacterSet
{
    return [[[NSCharacterSet alphanumericCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)nonBaseCharacterSet
{
    return [[[NSCharacterSet nonBaseCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)uppercaseLetterCharacterSet
{
    return [[[NSCharacterSet uppercaseLetterCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)lowercaseLetterCharacterSet
{
    return [[[NSCharacterSet lowercaseLetterCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)letterCharacterSet
{
    return [[[NSCharacterSet letterCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)decimalDigitCharacterSet
{
    return [[[NSCharacterSet decimalDigitCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)whitespaceAndNewlineCharacterSet
{
    return [[[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)whitespaceCharacterSet
{
    return [[[NSCharacterSet whitespaceCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)controlCharacterSet
{
    return [[[NSCharacterSet controlCharacterSet] mutableCopyWithZone:nil] autorelease];
}

+ (id)characterSetWithCharactersInString:(NSString *)string
{
    return [[[NSCharacterSet characterSetWithCharactersInString:string] mutableCopyWithZone:nil] autorelease];
}

+ (id)characterSetWithRange:(NSRange)range
{
    return [[[NSCharacterSet characterSetWithRange:range] mutableCopyWithZone:nil] autorelease];
}

- (void)addCharactersInRange:(NSRange)range
{
    NSRequestConcreteImplementation();
}

- (void)removeCharactersInRange:(NSRange)range
{
    NSRequestConcreteImplementation();
}

- (void)addCharactersInString:(NSString *)string
{
    NSRequestConcreteImplementation();
}

- (void)removeCharactersInString:(NSString *)string
{
    NSRequestConcreteImplementation();
}

- (void)formUnionWithCharacterSet:(NSCharacterSet *)other
{
    NSRequestConcreteImplementation();
}

- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)other
{
    NSRequestConcreteImplementation();
}

- (void)invert
{
    NSRequestConcreteImplementation();
}

- (BOOL)isMutable
{
    return YES;
}

@end

@implementation __NSCFCharacterSet

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    return NO;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    CFCharacterSetRef set = (CFCharacterSetRef)self;
    if (![coder allowsKeyedCoding])
    {
        [coder encodeObject:[self bitmapRepresentation]];
        return;
    }

    BOOL inverted = _CFCharacterSetIsInverted(set);
    switch (_CFCharacterSetGetKeyedCodingType(set))
    {
        case kCFCharacterSetKeyedCodingTypeBuiltin:
            [coder encodeInteger:_CFCharacterSetGetKeyedCodingBuiltinType(set) forKey:@"NSBuiltinID"];
            if (inverted)
            {
                [coder encodeBool:YES forKey:@"NSIsInverted"];
            }
            break;
        case kCFCharacterSetKeyedCodingTypeBuiltinAndBitmap:
        {
            NSData *bitmap = [self bitmapRepresentation];
            [coder encodeBytes:[bitmap bytes] length:[bitmap length] forKey:@"NSBitmap"];
            [coder encodeInteger:_CFCharacterSetGetKeyedCodingBuiltinType(set) forKey:@"NSBuiltinID2"];
            if (inverted)
            {
                [coder encodeBool:YES forKey:@"NSIsInverted2"];
            }
            break;
        }
        case kCFCharacterSetKeyedCodingTypeRange:
        {
            CFRange range = _CFCharacterSetGetKeyedCodingRange(set);
            [coder encodeInt64:(int64_t)(((uint64_t)range.location << 32) | (uint64_t)range.length) forKey:@"NSRange"];
            if (inverted)
            {
                [coder encodeBool:YES forKey:@"NSIsInverted"];
            }
            break;
        }
        case kCFCharacterSetKeyedCodingTypeString:
        {
            NSString *string = (NSString *)_CFCharacterSetCreateKeyedCodingString(set);
            [coder encodeObject:string forKey:@"NSString"];
            [string release];
            if (inverted)
            {
                [coder encodeBool:YES forKey:@"NSIsInverted"];
            }
            break;
        }
        default:
        {
            NSData *bitmap = [self bitmapRepresentation];
            [coder encodeBytes:[bitmap bytes] length:[bitmap length] forKey:@"NSBitmap"];
            break;
        }
    }
}

- (Class)classForCoder
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        return [NSMutableCharacterSet class];
    }
    else
    {
        return [NSCharacterSet class];
    }
}

- (Class)classForKeyedArchiver
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        return [NSMutableCharacterSet class];
    }
    else
    {
        return [NSCharacterSet class];
    }
}

- (void)makeCharacterSetFast
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetFast((CFMutableCharacterSetRef)self);
    }
}

- (void)makeCharacterSetCompact
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetCompact((CFMutableCharacterSetRef)self);
    }
}

- (void)invert
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetInvert((CFMutableCharacterSetRef)self);
    }
}

- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)other
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetIntersect((CFMutableCharacterSetRef)self, (CFCharacterSetRef)other);
    }
}

- (void)formUnionWithCharacterSet:(NSCharacterSet *)other
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetUnion((CFMutableCharacterSetRef)self, (CFCharacterSetRef)other);
    }
}

- (void)removeCharactersInString:(NSString *)string
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetRemoveCharactersInString((CFMutableCharacterSetRef)self, (CFStringRef)string);
    }
}

- (void)addCharactersInString:(NSString *)string
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetAddCharactersInString((CFMutableCharacterSetRef)self, (CFStringRef)string);
    }
}

- (void)removeCharactersInRange:(NSRange)range
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetRemoveCharactersInRange((CFMutableCharacterSetRef)self, CFRangeMake(range.location, range.length));
    }
}

- (void)addCharactersInRange:(NSRange)range
{
    if (__CFCharacterSetIsMutable((CFCharacterSetRef)self))
    {
        CFCharacterSetAddCharactersInRange((CFMutableCharacterSetRef)self, CFRangeMake(range.location, range.length));
    }
}

- (NSCharacterSet *)invertedSet
{
    return [(NSCharacterSet *)CFCharacterSetCreateInvertedSet(kCFAllocatorDefault, (CFCharacterSetRef)self) autorelease];
}

- (NSData *)bitmapRepresentation
{
    return [(NSData *)CFCharacterSetCreateBitmapRepresentation(kCFAllocatorDefault, (CFCharacterSetRef)self) autorelease];
}

- (BOOL)hasMemberInPlane:(uint8_t)plane
{
    return CFCharacterSetHasMemberInPlane((CFCharacterSetRef)self, plane);
}

- (BOOL)isSupersetOfSet:(id)other
{
    return CFCharacterSetIsSupersetOfSet((CFCharacterSetRef)self, (CFCharacterSetRef)other);
}

- (BOOL)longCharacterIsMember:(UTF32Char)character
{
    return CFCharacterSetIsLongCharacterMember((CFCharacterSetRef)self, character);
}

- (BOOL)characterIsMember:(unichar)character
{
    return CFCharacterSetIsCharacterMember((CFCharacterSetRef)self, character);
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    return (id)CFCharacterSetCreateMutableCopy(kCFAllocatorDefault, (CFCharacterSetRef)self);
}

- (id)copyWithZone:(NSZone *)zone
{
    return (id)CFCharacterSetCreateCopy(kCFAllocatorDefault, (CFCharacterSetRef)self);
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
