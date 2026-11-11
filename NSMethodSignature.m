//
//  NSMethodSignature.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import "NSInvocationInternal.h"
#import "NSObjCRuntimeInternal.h"
#import "NSObjectInternal.h"

#define ALIGN_TO(value, alignment) \
(((value) % (alignment)) ? \
((value) + (alignment) - ((value) % (alignment))) : \
(value) \
)

extern void __CFStringAppendBytes(CFMutableStringRef, const char *, CFIndex, CFStringEncoding);

#if defined(__arm64__)
// AAPCS64 passes and returns structs made of one to four doubles in d registers.
// Float aggregates are not recognised.
unsigned __NSARM64DoubleHFACount(const char *type)
{
    type = stripQualifiersAndComments(type);
    if (*type != _C_STRUCT_B)
    {
        return 0;
    }

    unsigned count = 0, depth = 0;
    for (const char *p = type; *p; p++)
    {
        if (*p == _C_STRUCT_B)
        {
            p = strchr(p, '=');
            if (p == NULL)
            {
                return 0;
            }
            depth++;
        }
        else if (*p == _C_STRUCT_E)
        {
            if (--depth == 0)
            {
                return count;
            }
        }
        else if (*p == '"')
        {
            p = strchr(p + 1, '"');
            if (p == NULL)
            {
                return 0;
            }
        }
        else if (*p != _C_DBL || ++count > 4)
        {
            return 0;
        }
    }
    return 0;
}
#endif

// The arm64, x86_64 and i386 ABIs as implemented by the compiler used for Apple platforms extend
// integer arguments and results narrower than int to 32 bits (callers extend arguments, callees
// extend results), and compiled code relies on that. value holds a value of the given type in the
// low bytes of a 4+ byte slot.
void __NSExtendNarrowInteger(void *value, const char *type)
{
    switch (*stripQualifiersAndComments(type))
    {
        case _C_CHR:
        {
            int32_t extended = *(int8_t *)value;
            memcpy(value, &extended, sizeof(extended));
            break;
        }
        case _C_SHT:
        {
            int32_t extended = *(int16_t *)value;
            memcpy(value, &extended, sizeof(extended));
            break;
        }
        case _C_UCHR:
        case _C_BOOL:
        {
            uint32_t extended = *(uint8_t *)value;
            memcpy(value, &extended, sizeof(extended));
            break;
        }
        case _C_USHT:
        {
            uint32_t extended = *(uint16_t *)value;
            memcpy(value, &extended, sizeof(extended));
            break;
        }
    }
}

#if defined(__x86_64__)
// System V AMD64 classification. Each eightbyte of an argument or result is INTEGER or SSE;
// anything that needs memory (larger than 16 bytes, long double, too many members) is passed on
// the stack or returned through a hidden pointer.
enum { SysVNoClass = 0, SysVInteger, SysVSSE };

typedef struct {
    BOOL memory;
    BOOL x87;               // a lone long double: passed in memory, returned in st(0)
    unsigned eightbytes;
    unsigned char classes[2];
    unsigned longDoubles;
    unsigned otherScalars;
} SysVClassification;

static void sysvMergeClass(SysVClassification *c, NSUInteger offset, unsigned char cls)
{
    c->otherScalars++;
    if (offset / 8 >= 2)
    {
        c->memory = YES;
        return;
    }
    unsigned char *slot = &c->classes[offset / 8];
    *slot = (*slot == SysVInteger || cls == SysVInteger) ? SysVInteger : cls;
}

static const char *sysvClassifyMember(const char *type, NSUInteger offset, SysVClassification *c)
{
    type = stripQualifiersAndComments(type);
    const char *next = type;
    NSUInteger size = 0, alignment = 0;

    switch (*type)
    {
        case _C_STRUCT_B:
        case _C_UNION_B:
        {
            BOOL isUnion = *type == _C_UNION_B;
            char end = isUnion ? _C_UNION_E : _C_STRUCT_E;
            const char *p = type + 1;
            while (*p != '\0' && *p != '=' && *p != end)
            {
                p++;
            }
            if (*p == '=')
            {
                p++;
            }
            NSUInteger memberOffset = 0;
            while (*p != '\0' && *p != end)
            {
                NSUInteger memberSize = 0, memberAlignment = 0;
                __NSGetSizeAndAlignment(p, &memberSize, &memberAlignment, NO);
                if (memberAlignment == 0)
                {
                    memberAlignment = 1;
                }
                memberOffset = isUnion ? 0 : ALIGN_TO(memberOffset, memberAlignment);
                p = sysvClassifyMember(p, offset + memberOffset, c);
                if (!isUnion)
                {
                    memberOffset += memberSize;
                }
            }
            return *p == end ? p + 1 : p;
        }

        case _C_ARY_B:
        {
            char *p;
            long count = strtol(type + 1, &p, 10);
            NSUInteger elementSize = 0, elementAlignment = 0;
            __NSGetSizeAndAlignment(p, &elementSize, &elementAlignment, NO);
            const char *after = p;
            for (long i = 0; i < count; i++)
            {
                after = sysvClassifyMember(p, offset + i * elementSize, c);
            }
            if (count == 0)
            {
                after = __NSGetSizeAndAlignment(p, &elementSize, &elementAlignment, NO);
            }
            return *after == _C_ARY_E ? after + 1 : after;
        }

        case _C_FLT:
        case _C_DBL:
            sysvMergeClass(c, offset, SysVSSE);
            break;

        case _C_LNG_DBL:
            c->longDoubles++;
            break;

        default:
            sysvMergeClass(c, offset, SysVInteger);
            break;
    }

    return __NSGetSizeAndAlignment(next, &size, &alignment, NO);
}

static SysVClassification sysvClassify(const char *type, NSUInteger size)
{
    SysVClassification c = { NO, NO, (unsigned)((size + 7) / 8), { SysVNoClass, SysVNoClass }, 0, 0 };
    type = stripQualifiersAndComments(type);

    if (size > 16)
    {
        c.memory = YES;
        return c;
    }
    if (size == 0)
    {
        return c;
    }

    sysvClassifyMember(type, 0, &c);
    if (c.longDoubles > 0)
    {
        // A long double alone is returned in st(0); combined with anything else it is MEMORY.
        c.x87 = c.longDoubles == 1 && c.otherScalars == 0;
        c.memory = YES;
        return c;
    }
    for (unsigned i = 0; i < c.eightbytes; i++)
    {
        if (c.classes[i] == SysVNoClass)
        {
            c.classes[i] = SysVInteger;
        }
    }
    return c;
}

// Assigns the location of an argument in the frame. Register arguments live in the saved register
// block (see NSInvocationInternal.h); arguments that are split across an integer and an SSE register
// (or two SSE registers) have the offset of their second eightbyte in the upper 32 bits of the result.
static size_t sysvPlaceArgument(const SysVClassification *c, NSUInteger size, NSUInteger alignment,
                                unsigned *usedGPRegisters, unsigned *usedSSERegisters, NSUInteger *frameLength)
{
    if (!c->memory)
    {
        unsigned needGP = 0, needSSE = 0;
        for (unsigned i = 0; i < c->eightbytes; i++)
        {
            if (c->classes[i] == SysVSSE)
            {
                needSSE++;
            }
            else
            {
                needGP++;
            }
        }

        if (*usedGPRegisters + needGP <= 6 && *usedSSERegisters + needSSE <= 8)
        {
            size_t offsets[2] = { 0, 0 };
            for (unsigned i = 0; i < c->eightbytes; i++)
            {
                if (c->classes[i] == SysVSSE)
                {
                    offsets[i] = SYSV_SSE_AREA + 16 * (*usedSSERegisters)++;
                }
                else
                {
                    offsets[i] = 8 * (*usedGPRegisters)++;
                }
            }

            BOOL contiguous = c->eightbytes < 2 || (c->classes[0] == SysVInteger && c->classes[1] == SysVInteger);
            return contiguous ? offsets[0] : (offsets[0] | (offsets[1] << 32));
        }
    }

    // Stack arguments occupy whole eightbytes, aligned to their type but at least to 8.
    NSUInteger stackAlignment = MAX(alignment, 8);
    *frameLength = ALIGN_TO(*frameLength, stackAlignment);
    size_t offset = *frameLength;
    *frameLength += ALIGN_TO(size, 8);
    return offset;
}

void __NSSysVStoreArgument(void *frame, size_t offset, NSUInteger size, const void *value)
{
    if ((offset >> 32) == 0)
    {
        memcpy((char *)frame + offset, value, size);
        return;
    }

    size_t offsets[2] = { offset & 0xffffffffu, offset >> 32 };
    for (unsigned i = 0; i < 2 && size > 8 * i; i++)
    {
        memcpy((char *)frame + offsets[i], (const char *)value + 8 * i, MIN(size - 8 * i, (NSUInteger)8));
    }
}

void __NSSysVLoadArgument(const void *frame, size_t offset, NSUInteger size, void *value)
{
    if ((offset >> 32) == 0)
    {
        memcpy(value, (const char *)frame + offset, size);
        return;
    }

    size_t offsets[2] = { offset & 0xffffffffu, offset >> 32 };
    for (unsigned i = 0; i < 2 && size > 8 * i; i++)
    {
        memcpy((char *)value + 8 * i, (const char *)frame + offsets[i], MIN(size - 8 * i, (NSUInteger)8));
    }
}

// regs holds rax, rdx, the low halves of xmm0 and xmm1, and an x87 flag, as filled in by
// __invoke__ and consumed by the forwarding entry points.
BOOL __NSSysVReturnsInX87(const char *type)
{
    NSUInteger size = 0, alignment = 0;
    __NSGetSizeAndAlignment(type, &size, &alignment, NO);
    return sysvClassify(type, size).x87;
}

void __NSSysVReturnFromRegisters(const void *regs, const char *type, NSUInteger size, void *value)
{
    const uint64_t *r = regs;
    SysVClassification c = sysvClassify(type, size);
    if (c.x87)
    {
        memcpy(value, r, MIN(size, (NSUInteger)16));
        return;
    }
    unsigned gp = 0, sse = 0;
    for (unsigned i = 0; i < c.eightbytes && !c.memory; i++)
    {
        uint64_t part = c.classes[i] == SysVSSE ? r[2 + sse++] : r[gp++];
        memcpy((char *)value + 8 * i, &part, MIN(size - 8 * i, (NSUInteger)8));
    }
}

void __NSSysVReturnToRegisters(const void *value, const char *type, NSUInteger size, void *regs)
{
    uint64_t *r = regs;
    memset(r, 0, SYSV_RETURN_REGS_SIZE);
    SysVClassification c = sysvClassify(type, size);
    if (c.x87)
    {
        memcpy(r, value, MIN(size, (NSUInteger)16));
        r[4] = 1;
        return;
    }
    unsigned gp = 0, sse = 0;
    for (unsigned i = 0; i < c.eightbytes && !c.memory; i++)
    {
        uint64_t part = 0;
        memcpy(&part, (const char *)value + 8 * i, MIN(size - 8 * i, (NSUInteger)8));
        if (c.classes[i] == SysVSSE)
        {
            r[2 + sse++] = part;
        }
        else
        {
            r[gp++] = part;
        }
    }
}
#endif

#if defined(__i386__)
// i386 (Darwin) results: a struct or union of 1, 2, 4 or 8 bytes whose members are all of such
// sizes comes back in eax:edx, unless its only member (possibly nested, or an array of one) is a
// float or double, which comes back in st(0); other aggregates use a hidden pointer; an empty one
// returns nothing.
static const char *i386SingleScalar(const char *type)
{
    type = stripQualifiersAndComments(type);
    switch (*type)
    {
        case _C_STRUCT_B:
        case _C_UNION_B:
        {
            char end = *type == _C_STRUCT_B ? _C_STRUCT_E : _C_UNION_E;
            const char *p = type + 1;
            while (*p != '\0' && *p != '=' && *p != end)
            {
                p++;
            }
            if (*p != '=')
            {
                return NULL;
            }
            p++;
            NSUInteger size = 0, alignment = 0;
            const char *after = __NSGetSizeAndAlignment(p, &size, &alignment, NO);
            return (*p != end && *after == end) ? i386SingleScalar(p) : NULL;
        }

        case _C_ARY_B:
        {
            char *p;
            return strtol(type + 1, &p, 10) == 1 ? i386SingleScalar(p) : NULL;
        }

        default:
            return type;
    }
}

static BOOL i386FitsInRegisters(const char *type)
{
    type = stripQualifiersAndComments(type);
    NSUInteger size = 0, alignment = 0;
    __NSGetSizeAndAlignment(type, &size, &alignment, NO);
    if (size != 1 && size != 2 && size != 4 && size != 8)
    {
        return NO;
    }

    if (*type == _C_STRUCT_B || *type == _C_UNION_B)
    {
        char end = *type == _C_STRUCT_B ? _C_STRUCT_E : _C_UNION_E;
        const char *p = type + 1;
        while (*p != '\0' && *p != '=' && *p != end)
        {
            p++;
        }
        if (*p == '=')
        {
            p++;
        }
        while (*p != '\0' && *p != end)
        {
            if (!i386FitsInRegisters(p))
            {
                return NO;
            }
            NSUInteger memberSize = 0, memberAlignment = 0;
            p = __NSGetSizeAndAlignment(p, &memberSize, &memberAlignment, NO);
        }
    }
    else if (*type == _C_ARY_B)
    {
        char *p;
        strtol(type + 1, &p, 10);
        return i386FitsInRegisters(p);
    }
    return YES;
}

BOOL __NSI386ResultInMemory(const char *type, NSUInteger size)
{
    type = stripQualifiersAndComments(type);
    return (*type == _C_STRUCT_B || *type == _C_UNION_B) && size != 0 && !i386FitsInRegisters(type);
}

char __NSI386X87ResultType(const char *type)
{
    type = stripQualifiersAndComments(type);
    if (*type == _C_FLT || *type == _C_DBL || *type == _C_LNG_DBL)
    {
        return *type;
    }
    if (*type == _C_STRUCT_B || *type == _C_UNION_B)
    {
        const char *scalar = i386FitsInRegisters(type) ? i386SingleScalar(type) : NULL;
        if (scalar != NULL && (*scalar == _C_FLT || *scalar == _C_DBL))
        {
            return *scalar;
        }
    }
    return 0;
}
#endif

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

#if defined(__arm64__)
    // AAPCS64 frame, as used by __invoke__ and __CF_forwarding_prep_0: x0-x7 at 0x0,
    // d0-d7 at 0x40 and stack arguments from 0x80.
    unsigned short usedGPRegisters = 0;
    unsigned short usedFPRegisters = 0;
    _frameLength = 0x80;
#elif defined(__x86_64__)
    // On x86-64, arguments are passed in registers as classified by the System V ABI.
    // __CF_forwarding_prep and __invoke__ pack and unpack all register values into a
    // 0xe0-sized block preceeding the actual stack frame contents. This means
    // frameLength always starts at 0xe0 and grows from there if there are any
    // on-stack arguments.
    unsigned usedGPRegisters = 0;
    unsigned usedSSERegisters = 0;
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
                case _C_UNION_B:
                case _C_STRUCT_B:
                {
#if defined(__arm64__)
                    // Larger results, other than double aggregates, are returned through x8.
                    _stret = ms->size > 16 && __NSARM64DoubleHFACount(currentType) == 0;
#elif defined(__x86_64__)
                    // Results classified as MEMORY are written through a hidden pointer that is
                    // passed in rdi, ahead of self; smaller aggregates come back in rax, rdx,
                    // xmm0 and xmm1.
                    SysVClassification resultClass = sysvClassify(currentType, ms->size);
                    if (resultClass.memory && !resultClass.x87)
                    {
                        _stret = YES;
                        ++usedGPRegisters;
                    }
#else
                    // On i386 small aggregates come back in eax:edx or st(0); others are written
                    // through a hidden pointer that is passed on the stack, ahead of self.
                    if (__NSI386ResultInMemory(currentType, ms->size))
                    {
                        _frameLength += sizeof(void *);
                        _stret = YES;
                    }
#endif
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
#elif defined(__arm64__)
            const char *argType = stripQualifiersAndComments(currentType);
            unsigned hfaCount = __NSARM64DoubleHFACount(argType);
            BOOL isFP = argType[0] == _C_FLT || argType[0] == _C_DBL || argType[0] == 'D';
            BOOL inRegisters = NO;
            if (isFP || hfaCount)
            {
                unsigned short registersNeeded = isFP ? 1 : hfaCount;
                if (usedFPRegisters + registersNeeded <= 8)
                {
                    _types[_count].offset = 0x40 + usedFPRegisters * 8;
                    usedFPRegisters += registersNeeded;
                    inRegisters = YES;
                }
                else
                {
                    usedFPRegisters = 8;
                }
            }
            else if (ms->size <= 16)
            {
                unsigned short registersNeeded = ALIGN_TO(ms->size, 8) / 8;
                if (usedGPRegisters + registersNeeded <= 8)
                {
                    _types[_count].offset = usedGPRegisters * 8;
                    usedGPRegisters += registersNeeded;
                    inRegisters = YES;
                }
                else
                {
                    usedGPRegisters = 8;
                }
            }
            // FIXME: structs over 16 bytes (other than double aggregates) should be passed by reference.
            if (!inRegisters)
            {
                // Apple's arm64 ABI packs scalar stack arguments by their own size and alignment,
                // but aggregates still take 8-byte-aligned slots rounded up to 8 bytes.
                BOOL isAggregate = argType[0] == _C_STRUCT_B || argType[0] == _C_UNION_B || argType[0] == _C_ARY_B;
                NSUInteger stackAlignment = isAggregate ? MAX(ms->alignment, 8) : ms->alignment;
                NSUInteger stackSize = isAggregate ? ALIGN_TO(ms->size, 8) : ms->size;
                _frameLength = ALIGN_TO(_frameLength, stackAlignment);
                _types[_count].offset = _frameLength;
                _frameLength += stackSize;
            }
#elif defined(__x86_64__)
            {
                SysVClassification classification = sysvClassify(currentType, ms->size);
                _types[_count].offset = sysvPlaceArgument(&classification, ms->size, ms->alignment,
                                                          &usedGPRegisters, &usedSSERegisters, &_frameLength);
            }
#else
            _types[_count].offset = _frameLength;
            _frameLength += frameSize;
#endif
        }

        _count++;
    }

#if defined(__arm64__)
    // __invoke__ copies stack arguments in 8-byte words.
    _frameLength = ALIGN_TO(_frameLength, 8);
#endif

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
