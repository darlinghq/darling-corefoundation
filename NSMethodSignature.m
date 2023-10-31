//
//  NSMethodSignature.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <Foundation/NSMethodSignature.h>
#import "NSObjCRuntimeInternal.h"
#import "NSObjectInternal.h"

#define ALIGN_TO(value, alignment) \
(((value) % (alignment)) ? \
((value) + (alignment) - ((value) % (alignment))) : \
(value) \
)

extern void __CFStringAppendBytes(CFMutableStringRef, const char *, CFIndex, CFStringEncoding);

@implementation NSMethodSignature

- (instancetype)initWithObjCTypes:(const char *)types
{
    self = [super init];

    if (self == nil)
    {
        return nil;
    }

    _count = 0;
    _frameLength = 0;
    _typeString = CFStringCreateMutable(NULL, strlen(types));
    // strlen(types) is a safe overapproximation to the actual number of types.
    _types = calloc(sizeof(NSMethodType), strlen(types));

    if (UNLIKELY(_types == NULL))
    {
        [self release];
        return nil;
    }

    const char *currentType = types;
    const char *nextType = types;

#ifdef __LP64__
    unsigned short usedGPRegisters = 0;
    unsigned short usedFPRegisters = 0;

    // On x86-64, the first few arguments are passed in registers as long as
    // they satisfy certain conditions. __CF_forwarding_prep and __invoke__
    // pack and unpack all register values into a 0xe0-sized block preceeding
    // the actual stack frame contents. This means frameLength always starts
    // at 0xe0 and grows from there if there are any on-stack arguments.
    _frameLength = 0xe0;
#endif

    while (nextType[0])
    {
        NSMethodType *ms = &_types[_count];

        if (nextType[0] == '>' && nextType[1] == '\0') {
            // handle the case where we initialize the signature using the extended type description of a block parameter
            // (this is so that we don't have to copy the string and null terminate it in `_signatureForBlockAtArgumentIndex:`)
            break;
        }

        currentType = nextType;
        nextType = NSGetSizeAndAlignment(currentType, &ms->size, &ms->alignment);

        // append the type info WITHOUT the extended type info
        __CFStringAppendBytes(_typeString, currentType, nextType - currentType, kCFStringEncodingUTF8);

        // we need to be able to handle extended type encodings.
        // these don't affect the size or alignment of the type, but they are considered part of the type and we need to store them
        if (nextType[0] == '"') {
            // this describes what kind of object the argument expects.
            // this case is simple; no nesting possible
            nextType = strchr(nextType + 1, '"');
            if (!nextType) {
                // no closing quotation mark? invalid type encoding.
                [NSException raise: NSInvalidArgumentException format: @"Invalid type encoding: expected closing quotation mark"];
            }
            ++nextType; // skip the closing quotation mark
        } else if (nextType[0] == '<') {
            // this describes the block signature.
            // this case is little more complicated; nesting is possible
            size_t nestLevel = 1;
            ++nextType;
            for (; nestLevel > 0 && nextType[0] != '\0'; ++nextType) {
                if (nextType[0] == '<') {
                    ++nestLevel;
                } else if (nextType[0] == '>') {
                    --nestLevel;
                }
            }
            if (nestLevel > 0) {
                // still missing a closing angle bracket? invalid type encoding.
                [NSException raise: NSInvalidArgumentException format: @"Invalid type encoding: expected closing angle bracket"];
            }
        }

        // there might other extended type encodings i haven't encountered, but those two should be the two most important ones

        ms->type = calloc(nextType - currentType + 1, 1);
        if (UNLIKELY(ms->type == NULL))
        {
            [self release];
            return nil;
        }
        strncpy(ms->type, currentType, nextType - currentType);

        // Skip advisory size
        // (but record the size start offset so we can append into the type string)
        const char* sizeStart = nextType;
        strtol(nextType, (char **)&nextType, 10);

        // append the size info
        if (nextType - sizeStart > 0) {
            __CFStringAppendBytes(_typeString, sizeStart, nextType - sizeStart, kCFStringEncodingUTF8);
        }

        NSUInteger frameAlignment = MAX(ms->alignment, sizeof(int));
        NSUInteger frameSize = ALIGN_TO(ms->size, frameAlignment);

        if (_count == 0)
        {
            // Determine whether the method is stret, based on the
            // type of the return value.
            switch (*stripQualifiersAndComments(_types[0].type))
            {
                case _C_STRUCT_B:
                {
                    if (frameSize > sizeof(int))
                    {
                        // Account for the stret return pointer.
                        _frameLength += sizeof(void *);
                        _stret = YES;
#if __LP64__
                        // on x86_64, the first GP register (rdi) is used to pass the stret pointer
                        ++usedGPRegisters;
#endif
                    }
                    break;
                }

                default:
                    // All other cases are non-stret.
                    break;
            }
        }
        else
        {
#if __arm__
            _frameLength = ALIGN_TO(_frameLength, frameAlignment);
#elif __LP64__
            // FIXME: This is far from being a complete implementation of
            // the x86-64 calling convention.
            BOOL isFP = currentType[0] == _C_FLT || currentType[0] == _C_DBL;
            if (isFP) {
                unsigned short registersNeeded = ALIGN_TO(frameSize, 16) / 16;
                if (usedFPRegisters + registersNeeded > 8) {
                    _types[_count].offset = _frameLength;
                    _frameLength += frameSize;
                } else {
                    _types[_count].offset = 0x30 + usedFPRegisters * 16;
                    usedFPRegisters += registersNeeded;
                }
            } else {
                unsigned short registersNeeded = ALIGN_TO(frameSize, 8) / 8;
                if (usedGPRegisters + registersNeeded > 6 || frameSize > 16) {
                    _types[_count].offset = _frameLength;
                    _frameLength += frameSize;
                } else {
                    _types[_count].offset = usedGPRegisters * 8;
                    usedGPRegisters += registersNeeded;
                }
            }
#else
            _types[_count].offset = _frameLength;
            _frameLength += frameSize;
#endif
        }

        _count++;
    }

    // Check whether the method is oneway by reading all the
    // qualifiers of the return type.
    static const char *qualifiers = "nNoOrRV";
    char *cur = _types[0].type;
    while (strchr(qualifiers, *cur)) {
        if (*cur == 'V') {
            _isOneway = YES;
            break;
        }
        cur++;
    }

    return self;
}

+ (NSMethodSignature *)signatureWithObjCTypes:(const char *)types
{
    return [[[self alloc] initWithObjCTypes:types] autorelease];
}

- (void)dealloc
{
    for (NSUInteger idx = 0; idx < _count; idx++)
    {
        if (_types[idx].type != NULL)
        {
            free(_types[idx].type);
        }
    }

    if (_types != NULL)
    {
        free(_types);
    }

    CFRelease(_typeString);
    [super dealloc];
}

- (NSUInteger)numberOfArguments
{
    return _count - 1;
}

- (const char *)getArgumentTypeAtIndex:(NSUInteger)idx
{
    return _types[idx + 1].type;
}

- (NSUInteger)frameLength
{
    return _frameLength;
}

- (BOOL)isOneway
{
    return _isOneway;
}

- (const char *)methodReturnType
{
    return _types[0].type;
}

- (NSUInteger)methodReturnLength
{
    return _types[0].size;
}

- (NSMethodType *)_argInfo:(NSUInteger)index
{
    return &_types[index];
}

- (BOOL)_stret
{
    return _stret;
}

- (CFStringRef) _typeString
{
    return _typeString;
}

- (NSMethodSignature*)_signatureForBlockAtArgumentIndex: (NSUInteger)index
{
    const char* argType = _types[index].type;
    argType = strchr(argType, '<');
    if (!argType) {
        return nil;
    }
    return [NSMethodSignature signatureWithObjCTypes: argType + 1];
}

- (Class)_classForObjectAtArgumentIndex: (NSUInteger)index
{
    const char* argType = _types[index].type;
    argType = strchr(argType, '"');
    if (!argType) {
        return nil;
    }
    return objc_getClass(argType + 1);
}

@end
