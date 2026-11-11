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

#if defined(__arm64__)
unsigned __NSARM64DoubleHFACount(const char *type);
void __NSARM64ExtendToInt(void *value, const char *type);
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
