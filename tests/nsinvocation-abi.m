// Copyright (C) 2026 Lubos Dolezel
// Build against the candidate CoreFoundation and run under Darling; see nsinvocation-abi.md.
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>
#include <string.h>

static int pass, total;

static void check(const char *label, int ok) {
    total++;
    pass += ok;
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
}

typedef struct { int a, b; } Small;                 // 8 bytes, in one register
typedef struct { long a, b; } Pair;                 // 16 bytes
typedef struct { double a, b, c, d; } Quad;         // homogeneous aggregate of four doubles
typedef struct { long a, b, c, d, e; } Big;         // 40 bytes, passed and returned indirectly

@interface Target : NSObject
- (signed char)negChar:(signed char)c;
- (short)addShort:(short)a to:(short)b;
- (long long)sumInts:(int)a :(int)b :(long)c :(long long)d;
- (float)halfFloat:(float)f;
- (double)mulDouble:(double)a by:(double)b;
- (Small)swapSmall:(Small)s;
- (Pair)addPair:(Pair)p to:(Pair)q;
- (Quad)scaleQuad:(Quad)q by:(double)f;
- (Big)bumpBig:(Big)b;
- (long)manyArgs:(long)a1 :(long)a2 :(long)a3 :(long)a4 :(long)a5 :(long)a6 :(long)a7 :(long)a8 :(long)a9 :(long)a10;
- (double)manyDoubles:(double)a1 :(double)a2 :(double)a3 :(double)a4 :(double)a5 :(double)a6 :(double)a7 :(double)a8 :(double)a9 :(double)a10;
@end

@implementation Target
- (signed char)negChar:(signed char)c { return -c; }
- (short)addShort:(short)a to:(short)b { return a + b; }
- (long long)sumInts:(int)a :(int)b :(long)c :(long long)d { return a + b + c + d; }
- (float)halfFloat:(float)f { return f / 2; }
- (double)mulDouble:(double)a by:(double)b { return a * b; }
- (Small)swapSmall:(Small)s { Small r = { s.b, s.a }; return r; }
- (Pair)addPair:(Pair)p to:(Pair)q { Pair r = { p.a + q.a, p.b + q.b }; return r; }
- (Quad)scaleQuad:(Quad)q by:(double)f { Quad r = { q.a * f, q.b * f, q.c * f, q.d * f }; return r; }
- (Big)bumpBig:(Big)b { Big r = { b.a + 1, b.b + 1, b.c + 1, b.d + 1, b.e + 1 }; return r; }
- (long)manyArgs:(long)a1 :(long)a2 :(long)a3 :(long)a4 :(long)a5 :(long)a6 :(long)a7 :(long)a8 :(long)a9 :(long)a10 {
    return a1 + 2*a2 + 3*a3 + 4*a4 + 5*a5 + 6*a6 + 7*a7 + 8*a8 + 9*a9 + 10*a10;
}
- (double)manyDoubles:(double)a1 :(double)a2 :(double)a3 :(double)a4 :(double)a5 :(double)a6 :(double)a7 :(double)a8 :(double)a9 :(double)a10 {
    return a1 + 2*a2 + 3*a3 + 4*a4 + 5*a5 + 6*a6 + 7*a7 + 8*a8 + 9*a9 + 10*a10;
}
@end

static NSInvocation *makeInv(id t, SEL sel) {
    NSMethodSignature *sig = [t methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:t];
    [inv setSelector:sel];
    return inv;
}

// A proxy that forwards everything to a Target, passing through forwardInvocation:.
@interface Forwarder : NSObject { Target *t; }
- (id)initWithTarget:(Target *)target;
@end
@implementation Forwarder
- (id)initWithTarget:(Target *)target { if ((self = [super init])) t = target; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [t methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)inv { [inv invokeWithTarget:t]; }
@end

// forwardInvocation: sends to super, which has no implementation for the selector.
@interface SuperSender : NSObject
- (void)unimplemented;
@end
@implementation SuperSender
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    if (sel == @selector(unimplemented)) return [NSMethodSignature signatureWithObjCTypes:"v@:"];
    return [super methodSignatureForSelector:sel];
}
- (void)forwardInvocation:(NSInvocation *)inv { [super forwardInvocation:inv]; }
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    Target *t = [Target new];

    {
        SEL s = @selector(negChar:); NSInvocation *inv = makeInv(t, s);
        signed char c = -7; [inv setArgument:&c atIndex:2]; [inv invoke];
        signed char r = 0; [inv getReturnValue:&r];
        check("char argument and return", r == 7);
    }
    {
        SEL s = @selector(addShort:to:); NSInvocation *inv = makeInv(t, s);
        short a = -300, b = 100; [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3]; [inv invoke];
        short r = 0; [inv getReturnValue:&r];
        check("short arguments and return", r == -200);
    }
    {
        SEL s = @selector(sumInts::::); NSInvocation *inv = makeInv(t, s);
        int a = -1, b = 2; long c = sizeof(long) == 8 ? 1L << 40 : 1L << 30; long long d = 5;
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3];
        [inv setArgument:&c atIndex:4]; [inv setArgument:&d atIndex:5]; [inv invoke];
        long long r = 0; [inv getReturnValue:&r];
        check("mixed integer widths", r == (long long)c + 6);
    }
    {
        SEL s = @selector(halfFloat:); NSInvocation *inv = makeInv(t, s);
        float f = 5.0f; [inv setArgument:&f atIndex:2]; [inv invoke];
        float r = 0; [inv getReturnValue:&r];
        check("float argument and return", r == 2.5f);
    }
    {
        SEL s = @selector(mulDouble:by:); NSInvocation *inv = makeInv(t, s);
        double a = 1.5, b = 4; [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3]; [inv invoke];
        double r = 0; [inv getReturnValue:&r];
        check("double arguments and return", r == 6.0);
    }
    {
        SEL s = @selector(swapSmall:); NSInvocation *inv = makeInv(t, s);
        Small a = { 1, 2 }; [inv setArgument:&a atIndex:2]; [inv invoke];
        Small r = { 0, 0 }; [inv getReturnValue:&r];
        check("8-byte struct argument and return", r.a == 2 && r.b == 1);
    }
    {
        SEL s = @selector(addPair:to:); NSInvocation *inv = makeInv(t, s);
        Pair a = { 1, 2 }, b = { 10, 20 };
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3]; [inv invoke];
        Pair r = { 0, 0 }; [inv getReturnValue:&r];
        check("16-byte struct arguments and return", r.a == 11 && r.b == 22);
    }
    {
        SEL s = @selector(scaleQuad:by:); NSInvocation *inv = makeInv(t, s);
        Quad q = { 1, 2, 3, 4 }; double f = 2;
        [inv setArgument:&q atIndex:2]; [inv setArgument:&f atIndex:3]; [inv invoke];
        Quad r = { 0, 0, 0, 0 }; [inv getReturnValue:&r];
        check("four-double struct argument and return", r.a == 2 && r.b == 4 && r.c == 6 && r.d == 8);
    }
    {
        SEL s = @selector(bumpBig:); NSInvocation *inv = makeInv(t, s);
        Big b = { 1, 2, 3, 4, 5 }; [inv setArgument:&b atIndex:2]; [inv invoke];
        Big r; memset(&r, 0, sizeof r); [inv getReturnValue:&r];
        check("40-byte struct argument and return", r.a == 2 && r.b == 3 && r.c == 4 && r.d == 5 && r.e == 6);
    }
    {
        SEL s = @selector(manyArgs::::::::::); NSInvocation *inv = makeInv(t, s);
        long v[10]; long want = 0;
        for (int i = 0; i < 10; i++) { v[i] = i + 1; want += (long)(i + 1) * (i + 1); [inv setArgument:&v[i] atIndex:2 + i]; }
        [inv invoke];
        long r = 0; [inv getReturnValue:&r];
        check("ten integer arguments (stack arguments)", r == want);
    }
    {
        SEL s = @selector(manyDoubles::::::::::); NSInvocation *inv = makeInv(t, s);
        double v[10]; double want = 0;
        for (int i = 0; i < 10; i++) { v[i] = i + 1; want += (double)(i + 1) * (i + 1); [inv setArgument:&v[i] atIndex:2 + i]; }
        [inv invoke];
        double r = 0; [inv getReturnValue:&r];
        check("ten double arguments (stack arguments)", r == want);
    }
    {
        Forwarder *f = [[Forwarder alloc] initWithTarget:t];
        Quad q = { 1, 2, 3, 4 };
        Quad r = [(id)f scaleQuad:q by:3];
        check("forwarding returns a four-double struct", r.a == 3 && r.b == 6 && r.c == 9 && r.d == 12);
        Big b = { 1, 2, 3, 4, 5 };
        Big rb = [(id)f bumpBig:b];
        check("forwarding returns a 40-byte struct", rb.a == 2 && rb.e == 6);
        check("forwarding returns a float", [(id)f halfFloat:3.0f] == 1.5f);
        check("forwarding returns a narrow integer", [(id)f negChar:5] == -5);
        check("forwarding passes stack arguments", [(id)f manyArgs:1 :2 :3 :4 :5 :6 :7 :8 :9 :10] == 385);
        [f release];
    }
    {
        // A default forwardInvocation: reached through a super send raises
        // instead of recursing.
        SuperSender *o = [SuperSender new];
        int raised = 0;
        @try { [o unimplemented]; }
        @catch (NSException *e) { raised = [[e name] isEqualToString:NSInvalidArgumentException]; }
        check("super forwardInvocation: raises NSInvalidArgumentException", raised);
        [o release];
    }

    printf("%d/%d passed\n", pass, total);
    [pool drain];
    return pass == total ? 0 : 1;
}
