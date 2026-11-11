#import <objc/message.h>

#import <Block_private.h>

@class NSMethodSignature;

// Needs to be at least as large as:
// - 4 ints (for r0-r3)
// - 2 longs (for rdx/rax) and two doubles (for xmm0/xmm1)
// - long double
// So, max(16, 16 + 16, 80)
#define RET_SIZE_ARGS 80

// hfaCount (arm64 only): number of double members returned in d0-d3, 0 if the result is not such an aggregate.
void __invoke__(void *send, void *retdata, marg_list args, size_t len, char rettype, unsigned hfaCount);

#if defined(__x86_64__)
// x86_64 frame layout shared by __invoke__, the forwarding trampolines and NSMethodSignature:
// rdi, rsi, rdx, rcx, r8, r9 at 0x00, xmm0-xmm7 at 0x30 (16 bytes each), %al at 0xb0, and the
// caller's stack arguments from 0xe0.
#define SYSV_SSE_AREA 0x30

// Registers carrying a result: rax, rdx, low halves of xmm0 and xmm1, then a nonzero word if
// the result is a long double in st(0), which __invoke__ stores at the start instead.
#define SYSV_RETURN_REGS_SIZE 64

// A register argument split across two eightbytes in different register files has the frame
// offset of its second eightbyte in the upper 32 bits of its NSMethodType offset.
void __NSSysVStoreArgument(void *frame, size_t offset, NSUInteger size, const void *value);
void __NSSysVLoadArgument(const void *frame, size_t offset, NSUInteger size, void *value);
BOOL __NSSysVReturnsInX87(const char *type);
void __NSSysVReturnFromRegisters(const void *regs, const char *type, NSUInteger size, void *value);
void __NSSysVReturnToRegisters(const void *value, const char *type, NSUInteger size, void *regs);
#endif

// Sign- or zero-extends a char, short or BOOL in a 4-byte slot to 32 bits.
void __NSExtendNarrowInteger(void *value, const char *type);

#if defined(__arm64__)
unsigned __NSARM64DoubleHFACount(const char *type);
#endif

#if defined(__i386__)
// i386: whether a struct or union result is written through a hidden pointer, and the type
// ('f', 'd' or 'D') of a result returned in st(0), if any.
BOOL __NSI386ResultInMemory(const char *type, NSUInteger size);
char __NSI386X87ResultType(const char *type);
#endif

extern void _CF_forwarding_prep_0();
extern void _CF_forwarding_prep_1();

@interface NSInvocation (Internal)
+ (instancetype)_invocationWithMethodSignature: (NSMethodSignature*)signature frame: (void*)frame;
- (instancetype)_initWithMethodSignature: (NSMethodSignature*)signature frame: (void*)frame;
- (void) invokeSuper;
- (void) invokeUsingIMP: (IMP) imp;
- (void **) _idxToArg: (NSUInteger) idx;
- (void) _addAttachedObject: (id) object;
@end
