//
//  NSInvocation.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>

#import "Block_private.h"
#import "NSInvocationInternal.h"
#import "NSObjCRuntimeInternal.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>


@implementation NSInvocation

+ (void)load
{
#if LEGACY_METHOD
    // signature should be @encode(long long) @encode(id) @encode(SEL) @encode(SEL) @encode(marg_list)
    class_addMethod([NSObject class], @selector(forward::), (IMP)&_CF_forwarding_prep_0, "q@::^v");
#else
    objc_setForwardHandler(&_CF_forwarding_prep_0, &_CF_forwarding_prep_1);
#endif
}

#if defined(__arm64__)
// On arm64 a struct passed by reference has its frame slot hold a pointer to a copy. The
// invocation keeps those copies in one block after the frame, so that the struct can be
// read and written by value like any other argument. The callee is handed the copy itself, so
// a callee that modifies its parameter changes the stored argument, as it does on macOS.
static BOOL isByReference(NSMethodSignature *signature, NSUInteger idx)
{
    NSMethodType *info = [signature _argInfo:idx];
    return __NSARM64PassedByReference(info->type, info->size);
}

// Offset of argument idx's copy within the block (the block's length when idx is past the end).
static NSUInteger referenceCopyOffset(NSMethodSignature *signature, NSUInteger idx)
{
    NSUInteger offset = 0;
    for (NSUInteger i = 1; i < idx; i++)
    {
        if (isByReference(signature, i))
        {
            offset += (([signature _argInfo:i]->size + 15) & ~(NSUInteger)15);
        }
    }
    return offset;
}

static NSUInteger referenceCopiesLength(NSMethodSignature *signature)
{
    return referenceCopyOffset(signature, [signature numberOfArguments] + 1);
}

// Points every by-reference slot of frame at its copy within copies.
static void bindReferenceCopies(NSMethodSignature *signature, void *frame, void *copies)
{
    for (NSUInteger i = 1; i <= [signature numberOfArguments]; i++)
    {
        if (isByReference(signature, i))
        {
            void *copy = (unsigned char *)copies + referenceCopyOffset(signature, i);
            *(void **)((unsigned char *)frame + [signature _argInfo:i]->offset) = copy;
        }
    }
}
#endif

- (void **)_idxToArg:(NSUInteger)idx
{
    if (idx == 0)
    {
        return _retdata;
    }

#if defined(__arm64__)
    if (isByReference(_signature, idx))
    {
        return (void **)((unsigned char *)_frame + [_signature frameLength] + referenceCopyOffset(_signature, idx));
    }
#endif
    NSMethodType *argType = [_signature _argInfo:idx];
    // On x86_64 an argument split across register files is reached through
    // __NSSysVLoadArgument and __NSSysVStoreArgument; this is where its first part lives.
    return _frame + (argType->offset & 0xffffffffu);
}

// NSInvocation can retain its arguments, including copies of C
// strings which it places in an NSData. For such strings, this method
// therefore modifies the frame to use an internal pointer to the
// NSData rather than to the original string.
- (void)_retainArgument:(NSUInteger)idx
{
    NSMethodType *argInfo = [_signature _argInfo: idx];
    const char *type = stripQualifiersAndComments(argInfo->type);
    void **arg = [self _idxToArg: idx];

    if (type[0] == _C_ID)
    {
        id object = (id) *arg;
        if (object != nil)
        {
            [_container addObject: (id) *arg];
        }
    }
    else if (type[0] == _C_CHARPTR)
    {
        char *str = (char *) *arg;
        if (str != NULL)
        {
            NSUInteger length = strlen(str) + 1;
            NSData *data = [NSData dataWithBytes: str length: length];
            *arg = [data bytes];
            [_container addObject: data];
        }
    }
}

- (void) _addAttachedObject: (id) object
{
    if (_container == nil)
    {
        _container = [[NSMutableArray alloc] init];
    }
    [_container addObject: object];
}

- (instancetype)_initWithMethodSignature: (NSMethodSignature*)sig frame: (void*)frame
{
    if (sig == nil)
    {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"signature cannot be nil"];
        return nil;
    }

    self = [super init];

    if (self)
    {
        _signature = [sig retain];

        NSUInteger retSize = 0;
        NSGetSizeAndAlignment([_signature methodReturnType], &retSize, NULL);
        retSize = MAX(retSize, RET_SIZE_ARGS);
        NSUInteger copiesLength = 0;
#if defined(__arm64__)
        copiesLength = referenceCopiesLength(_signature);
#endif
        _retdata = calloc(retSize + [_signature frameLength] + copiesLength, 1);
        _frame = _retdata + retSize;

        if (frame) {
            memcpy(_frame, frame, [_signature frameLength]);
        }

#if defined(__arm64__)
        // Take our own copy of each struct the caller passed by reference.
        void *copies = (unsigned char *)_frame + [_signature frameLength];
        for (NSUInteger i = 1; i <= [_signature numberOfArguments]; i++)
        {
            if (isByReference(_signature, i))
            {
                void *source = frame ? *(void **)((unsigned char *)frame + [_signature _argInfo:i]->offset) : NULL;
                void *copy = (unsigned char *)copies + referenceCopyOffset(_signature, i);
                if (source != NULL)
                {
                    memcpy(copy, source, [_signature _argInfo:i]->size);
                }
            }
        }
        bindReferenceCopies(_signature, _frame, copies);
#endif

#if !defined(__arm64__)
        // On arm64 the indirect result location travels in x8, outside the frame.
        if ([sig _stret])
        {
            // Set up the return value pointer for the objc_msgSend_stret call.
            void **ret = _frame;
            *ret = _retdata;
        }
#endif
    }

    return self;
}

- (instancetype)initWithMethodSignature:(NSMethodSignature *)sig
{
    return [self _initWithMethodSignature: sig frame: NULL];
}

- (instancetype)init
{
    [self release]; // init should not work on NSInvocation
    return nil;
}

- (void)dealloc
{
    [_container release];
    [_signature release];
    free(_retdata);
    [super dealloc];
}


+ (instancetype)_invocationWithMethodSignature: (NSMethodSignature*)sig frame: (void*)frame
{
    return [[[self alloc] _initWithMethodSignature: sig frame: frame] autorelease];
}

+ (instancetype)invocationWithMethodSignature:(NSMethodSignature *)sig
{
    return [[[self alloc] initWithMethodSignature:sig] autorelease];
}

- (NSMethodSignature *)methodSignature
{
    return _signature;
}

- (void)retainArguments
{
    if (_retainedArgs)
    {
        return;
    }
    _retainedArgs = YES;

    NSUInteger capacity = [_signature numberOfArguments] + 1; // Add one for return value.
    if (_container == nil)
    {
        _container = [[NSMutableArray alloc] initWithCapacity: capacity];
    }

    for (NSUInteger idx = 0; idx < capacity; idx++)
    {
        [self _retainArgument:idx];
    }
}

- (BOOL)argumentsRetained
{
    return _retainedArgs;
}

- (id)target
{
    id t = nil;
    [self getArgument:&t atIndex:0];
    return t;
}

- (void)setTarget:(id)target
{
    [self setArgument:&target atIndex:0];
}

- (SEL)selector
{
    SEL sel;
    [self getArgument:&sel atIndex:1];
    return sel;
}

- (void)setSelector:(SEL)selector
{
    [self setArgument:&selector atIndex:1];
}

- (void)getReturnValue:(void *)retLoc
{
    [self getArgument:retLoc atIndex:-1];
}

- (void)setReturnValue:(void *)retLoc
{
    [self setArgument:retLoc atIndex:-1];
}

- (void)getArgument:(void *)argumentLocation atIndex:(NSInteger)idx
{
    // idx initially goes like this:
    // -1: return value
    // 0: self
    // 1: _cmd
    // 2+: arguments
    // Thus we add 1 to get an index into _frame.
    idx++;

    if (idx > [_signature numberOfArguments] || idx < 0)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:nil userInfo:nil];
    }

    NSMethodType *argInfo = [_signature _argInfo:idx];
    void **arg = [self _idxToArg:idx];

#if defined(__x86_64__)
    if (idx > 0)
    {
        __NSSysVLoadArgument(_frame, argInfo->offset, argInfo->size, argumentLocation);
        return;
    }
#endif
    memcpy(argumentLocation, arg, argInfo->size);
}

- (void)setArgument:(void *)argumentLocation atIndex:(NSInteger)idx
{
    // idx initially goes like this:
    // -1: return value
    // 0: self
    // 1: _cmd
    // 2+: arguments
    // Thus we add 1 to get an index into _frame.
    idx++;

    if (idx > [_signature numberOfArguments] || idx < 0)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:nil userInfo:nil];
    }

    NSMethodType *argInfo = [_signature _argInfo:idx];
    void **arg = [self _idxToArg:idx];

#if defined(__x86_64__)
    if (idx > 0)
    {
        __NSSysVStoreArgument(_frame, argInfo->offset, argInfo->size, argumentLocation);
    }
    else
#endif
    memcpy(arg, argumentLocation, argInfo->size);

#if defined(__arm64__)
    // Register slots (x0-x7 and d0-d7) are 8 bytes wide; stack slots of small types are packed.
    if (idx > 0 && argInfo->offset < 0x80)
    {
        __NSExtendNarrowInteger(arg, argInfo->type);
    }
#elif defined(__x86_64__) || defined(__i386__)
    // Every argument occupies a whole word or more here, and callers widen narrow integers.
    if (idx > 0)
    {
        __NSExtendNarrowInteger(arg, argInfo->type);
    }
#endif

    if (_retainedArgs)
    {
        [self _retainArgument:idx];
    }
}

static BOOL isBlock(id object)
{
    static Class NSBlockClass = Nil;
    static dispatch_once_t once = 0L;
    dispatch_once(&once, ^{
        // __NSGlobalBlock -> NSBlock
        NSBlockClass = class_getSuperclass(class_getSuperclass(object_getClass(^{})));
    });

    for (
        Class class = object_getClass(object);
        class != Nil;
        class = class_getSuperclass(class)
    )
    {
        if (class == NSBlockClass)
        {
            return YES;
        }
    }

    return NO;
}

- (void) _invokeUsingIMP: (IMP) imp withFrame: (void *) frame
{
    if ([self target] == nil)
    {
        return;
    }

#if defined(__arm64__)
    const char *returnType = stripQualifiersAndComments([_signature methodReturnType]);
    // An indirect result is written by the callee through x8 (_retdata), so the trampoline stores nothing.
    char rettype = [_signature _stret] ? _C_VOID : returnType[0];
    __invoke__(imp, _retdata, frame, [_signature frameLength], rettype, __NSARM64DoubleHFACount(returnType));
#elif defined(__x86_64__)
    const char *returnType = stripQualifiersAndComments([_signature methodReturnType]);
    uint64_t regs[SYSV_RETURN_REGS_SIZE / sizeof(uint64_t)] = { 0 };
    // __invoke__ takes the result of a long double, or of a struct holding only one, from st(0).
    char rettype = __NSSysVReturnsInX87(returnType) ? _C_LNG_DBL : returnType[0];
    __invoke__(imp, regs, frame, [_signature frameLength], rettype, 0);

    // A MEMORY-class result was written through the hidden pointer in the frame; any other
    // result is rebuilt from the registers that carried it.
    if (![_signature _stret] && returnType[0] != _C_VOID)
    {
        __NSSysVReturnFromRegisters(regs, returnType, [_signature methodReturnLength], _retdata);
    }
#else
    // __invoke__ takes the result of a float, double or long double, or of a struct holding
    // only a float or double, from st(0).
    char rettype = __NSI386X87ResultType([_signature methodReturnType]);
    if (rettype == 0)
    {
        rettype = stripQualifiersAndComments([_signature methodReturnType])[0];
    }

    if ([_signature _stret])
    {
        char dummy[RET_SIZE_ARGS];
        __invoke__(imp, &dummy, frame, [_signature frameLength], rettype, 0);
    }
    else
    {
        __invoke__(imp, _retdata, frame, [_signature frameLength], rettype, 0);
    }
#endif

    if (_retainedArgs)
    {
        // Retain the return value.
        [self _retainArgument:0];
    }
}

- (void) invokeUsingIMP: (IMP) imp
{
    [self _invokeUsingIMP: imp withFrame: _frame];
}

- (void)invoke
{
    id target = [self target];
    if (target == nil)
    {
        return;
    }

    IMP imp;
    if (isBlock([self target]))
    {
        struct Block_layout *block_layout = (struct Block_layout *) target;
        imp = (IMP)block_layout->invoke;
    }
    #if !defined(__arm64__)
        else if ([_signature _stret])
        {
            imp = (IMP)&objc_msgSend_stret;
        }
    #endif
    #if defined(__x86_64__)
        else if (__NSSysVReturnsInX87([_signature methodReturnType]))
        {
            // A message to nil must leave the x87 stack balanced for a long double result.
            imp = (IMP)&objc_msgSend_fpret;
        }
    #elif defined(__i386__)
        else if (__NSI386X87ResultType([_signature methodReturnType]) != 0)
        {
            imp = (IMP)&objc_msgSend_fpret;
        }
    #endif
    else
    {
        imp = &objc_msgSend;
    }

    [self _invokeUsingIMP: imp withFrame: _frame];
}

- (void) invokeWithTarget: (id) target
{
    [self setTarget: target];
    [self invoke];
}

- (void) invokeSuper
{
    id target = [self target];
    if (target == nil)
    {
        return;
    }

    unsigned char *frameCopy = malloc([_signature frameLength]);
    memcpy(frameCopy, _frame, [_signature frameLength]);

    struct objc_super super = {
        .receiver = target,
#ifdef __OBJC2__
        .super_class
#else
        .class
#endif
            = class_getSuperclass([target class])
    };
    NSMethodType *argType = [_signature _argInfo: 1];
    *(struct objc_super **) (frameCopy + argType->offset) = &super;

    #if !defined(__arm64__)
        IMP imp = [_signature _stret] ? &objc_msgSendSuper_stret : &objc_msgSendSuper;
    #else
        IMP imp = &objc_msgSendSuper;
    #endif
    [self _invokeUsingIMP: imp withFrame: frameCopy];

    free(frameCopy);
}

- (NSString *) debugDescription
{
    CFMutableStringRef description = CFStringCreateMutable(NULL, 0);
    CFStringAppend(description, (CFStringRef) [self description]);

    for (NSInteger index = -1; index < (NSInteger) [_signature numberOfArguments]; index++)
    {
        CFStringAppend(description, CFSTR("\n"));

        switch (index)
        {
        case -1:
            CFStringAppend(description, CFSTR("return value"));
            break;
        case 0:
            CFStringAppend(description, CFSTR("target"));
            break;
        case 1:
            CFStringAppend(description, CFSTR("selector"));
            break;
        default:
            CFStringAppendFormat(description, NULL, CFSTR("argument %ld"), (long) index);
            break;
        }
        CFStringAppend(description, CFSTR(": "));

        NSMethodType *argInfo = [_signature _argInfo: index + 1];
        CFStringAppendFormat(description, NULL, CFSTR("{%s} "), argInfo->type);

        char type = stripQualifiersAndComments(argInfo->type)[0];
        switch (type)
        {
        case _C_VOID:
            CFStringAppend(description, CFSTR("void"));
            break;
        case _C_CLASS:
            {
                Class class;
                [self getArgument: &class atIndex: index];
                if (class == Nil)
                {
                    CFStringAppend(description, CFSTR("Nil"));
                }
                else
                {
                    CFStringAppendFormat(description, NULL, CFSTR("%s"), class_getName(class));
                }
                break;
            }
        case _C_SEL:
            {
                SEL selector;
                [self getArgument: &selector atIndex: index];
                if (!selector)
                {
                    CFStringAppend(description, CFSTR("null"));
                }
                else
                {
                    CFStringAppendFormat(description, NULL, CFSTR("%s"), sel_getName(selector));
                }
                break;
            }

#define HANDLE(_c_type, type, format) \
        case _c_type: \
            { \
                type value; \
                [self getArgument: &value atIndex: index]; \
                CFStringAppendFormat(description, NULL, format, value); \
                break; \
            }

        HANDLE(_C_CHR, char, CFSTR("%c"));
        HANDLE(_C_UCHR, unsigned char, CFSTR("%u"));
        HANDLE(_C_BOOL, _Bool, CFSTR("%d"));
        HANDLE(_C_SHT, short, CFSTR("%d"));
        HANDLE(_C_USHT, unsigned short, CFSTR("%u"));
        HANDLE(_C_INT, int, CFSTR("%d"));
        HANDLE(_C_UINT, unsigned int, CFSTR("%u"));
        HANDLE(_C_LNG, long, CFSTR("%ld"));
        HANDLE(_C_ULNG, unsigned long, CFSTR("%lu"));
        HANDLE(_C_LNG_LNG, long long, CFSTR("%lld"));
        HANDLE(_C_ULNG_LNG, unsigned long long, CFSTR("%llu"));
        HANDLE(_C_FLT, float, CFSTR("%f"));
        HANDLE(_C_DBL, double, CFSTR("%f"));
        HANDLE(_C_CHARPTR, const char *, CFSTR("%s"));
        HANDLE(_C_ID, id, CFSTR("%p"));
        HANDLE(_C_PTR, void *, CFSTR("%p"));

#undef HANDLE

        default:
            {
                void *value = calloc(1, argInfo->size ?: 1);
                [self getArgument: value atIndex: index];
                CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, value, argInfo->size, kCFAllocatorNull);
                CFStringAppend(description, (CFStringRef) [data description]);
                CFRelease(data);
                free(value);
                break;
            }
        }
    }

    CFAutorelease(description);
    return (NSString*)description;
}

@end
