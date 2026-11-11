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
typedef struct { long a, b, c; } Tri;               // 24 bytes, passed by reference
typedef struct { long a; double b; long c; double d; long e; } Mix;   // 40 bytes, not a homogeneous aggregate
typedef struct { long double x; } LDS;              // long double is double on arm64: an aggregate of one double
typedef struct { double v[4]; } ArrQ;               // homogeneous aggregate through an array
typedef struct { double v[2]; } ArrP;               // homogeneous aggregate through an array
typedef struct { long v[3]; } ArrL;                 // 24 bytes through an array
typedef struct { double a, b, c, d, e; } Pent;      // five doubles: not a homogeneous aggregate

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
- (Tri)tri:(Tri)t add:(Tri)u;
- (Mix)mix:(Mix)m;
- (LDS)lds:(LDS)x;
- (ArrQ)arrQ:(ArrQ)x;
- (ArrP)arrP:(ArrP)x;
- (ArrL)arrL:(ArrL)x;
- (Pent)pent:(Pent)x;
- (long)triThenLong:(Tri)t :(long)z;
- (long)spill:(long)a :(long)b :(long)c :(long)d :(long)e :(long)f tri:(Tri)t tail:(long)z;
- (double)hfaSpill:(double)a :(double)b :(double)c :(double)d :(double)e :(double)f :(double)g quad:(Quad)q tail:(double)z;
- (Tri)clobber:(Tri)t;
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
- (Tri)tri:(Tri)t add:(Tri)u { return (Tri){ t.a + u.a, t.b + u.b, t.c + u.c }; }
- (Mix)mix:(Mix)m { return (Mix){ m.a + 1, m.b + 1, m.c + 1, m.d + 1, m.e + 1 }; }
- (LDS)lds:(LDS)x { return (LDS){ x.x + 1 }; }
- (ArrQ)arrQ:(ArrQ)x { return (ArrQ){ { x.v[0] + 1, x.v[1] + 1, x.v[2] + 1, x.v[3] + 1 } }; }
- (ArrP)arrP:(ArrP)x { return (ArrP){ { x.v[0] + 1, x.v[1] + 1 } }; }
- (ArrL)arrL:(ArrL)x { return (ArrL){ { x.v[0] + 1, x.v[1] + 1, x.v[2] + 1 } }; }
- (Pent)pent:(Pent)x { return (Pent){ x.a + 1, x.b + 1, x.c + 1, x.d + 1, x.e + 1 }; }
- (long)triThenLong:(Tri)t :(long)z { return t.a + 10 * t.b + 100 * t.c + 1000 * z; }
- (long)spill:(long)a :(long)b :(long)c :(long)d :(long)e :(long)f tri:(Tri)t tail:(long)z {
    return a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*t.a + 8*t.b + 9*t.c + 10*z; }
- (double)hfaSpill:(double)a :(double)b :(double)c :(double)d :(double)e :(double)f :(double)g quad:(Quad)q tail:(double)z {
    return a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*q.a + 9*q.b + 10*q.c + 11*q.d + 12*z; }
- (Tri)clobber:(Tri)t { Tri r = t; t.a = 0; t.b = 0; t.c = 0; return r; }
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
        int a = -1, b = 2; long c = 1L << 40; long long d = 5;
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3];
        [inv setArgument:&c atIndex:4]; [inv setArgument:&d atIndex:5]; [inv invoke];
        long long r = 0; [inv getReturnValue:&r];
        check("mixed integer widths", r == (1LL << 40) + 6);
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
        // Structs of more than 16 bytes that are not aggregates of doubles are passed as a pointer
        // to a copy (the invocation still sees the struct by value) and returned through x8.
        Tri a = { 1, 2, 3 }, b = { 10, 20, 30 };
        SEL s = @selector(tri:add:); NSInvocation *inv = makeInv(t, s);
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3];
        Tri back; [inv getArgument:&back atIndex:2];
        check("getArgument returns the 24-byte struct that was set", back.a == 1 && back.b == 2 && back.c == 3);
        [inv invoke];
        Tri r; [inv getReturnValue:&r];
        check("24-byte struct arguments and result", r.a == 11 && r.b == 22 && r.c == 33);
        Forwarder *f = [[Forwarder alloc] initWithTarget:t];
        r = [(id)f tri:a add:b];
        check("forwarding 24-byte struct arguments and result", r.a == 11 && r.b == 22 && r.c == 33);
        long z = [(id)f triThenLong:a :7];
        check("forwarding a reference argument followed by a long", z == 1 + 20 + 300 + 7000);
        z = [(id)f spill:1 :2 :3 :4 :5 :6 tri:a tail:99];
        check("forwarding a reference argument in a stack slot", z == 1 + 4 + 9 + 16 + 25 + 36 + 7 + 16 + 27 + 990);
        inv = makeInv(t, @selector(spill::::::tri:tail:));
        long v[6] = { 1, 2, 3, 4, 5, 6 }, tail = 99;
        for (int i = 0; i < 6; i++) [inv setArgument:&v[i] atIndex:2 + i];
        [inv setArgument:&a atIndex:8]; [inv setArgument:&tail atIndex:9]; [inv invoke];
        [inv getReturnValue:&z];
        check("invoking with a reference argument in a stack slot", z == 1 + 4 + 9 + 16 + 25 + 36 + 7 + 16 + 27 + 990);
        [f release];
    }
    {
        Mix m = { 1, 2.5, 3, 4.5, 5 };
        SEL s = @selector(mix:); NSInvocation *inv = makeInv(t, s);
        [inv setArgument:&m atIndex:2]; [inv invoke];
        Mix r; [inv getReturnValue:&r];
        check("40-byte mixed struct", r.a == 2 && r.b == 3.5 && r.c == 4 && r.d == 5.5 && r.e == 6);
        Forwarder *f = [[Forwarder alloc] initWithTarget:t];
        r = [(id)f mix:m];
        check("forwarding a 40-byte mixed struct", r.a == 2 && r.b == 3.5 && r.c == 4 && r.d == 5.5 && r.e == 6);
        [f release];
    }
    {
        Forwarder *f = [[Forwarder alloc] initWithTarget:t];
        LDS x = { 2.5L };
        SEL s = @selector(lds:); NSInvocation *inv = makeInv(t, s);
        [inv setArgument:&x atIndex:2]; [inv invoke];
        LDS r; [inv getReturnValue:&r];
        check("struct holding a long double", r.x == 3.5L);
        r = [(id)f lds:x];
        check("forwarding a struct holding a long double", r.x == 3.5L);
        ArrQ q = { { 1, 2, 3, 4 } };
        inv = makeInv(t, @selector(arrQ:)); [inv setArgument:&q atIndex:2]; [inv invoke];
        ArrQ rq; [inv getReturnValue:&rq];
        check("double[4] in a struct", rq.v[0] == 2 && rq.v[1] == 3 && rq.v[2] == 4 && rq.v[3] == 5);
        rq = [(id)f arrQ:q];
        check("forwarding double[4] in a struct", rq.v[0] == 2 && rq.v[3] == 5);
        ArrP p = { { 1, 2 } };
        inv = makeInv(t, @selector(arrP:)); [inv setArgument:&p atIndex:2]; [inv invoke];
        ArrP rp; [inv getReturnValue:&rp];
        check("double[2] in a struct", rp.v[0] == 2 && rp.v[1] == 3);
        rp = [(id)f arrP:p];
        check("forwarding double[2] in a struct", rp.v[0] == 2 && rp.v[1] == 3);
        ArrL l = { { 1, 2, 3 } };
        inv = makeInv(t, @selector(arrL:)); [inv setArgument:&l atIndex:2]; [inv invoke];
        ArrL rl; [inv getReturnValue:&rl];
        check("long[3] in a struct", rl.v[0] == 2 && rl.v[1] == 3 && rl.v[2] == 4);
        rl = [(id)f arrL:l];
        check("forwarding long[3] in a struct", rl.v[0] == 2 && rl.v[2] == 4);
        Pent e = { 1, 2, 3, 4, 5 };
        inv = makeInv(t, @selector(pent:)); [inv setArgument:&e atIndex:2]; [inv invoke];
        Pent re; [inv getReturnValue:&re];
        check("five doubles in a struct", re.a == 2 && re.e == 6);
        re = [(id)f pent:e];
        check("forwarding five doubles in a struct", re.a == 2 && re.e == 6);
        [f release];
    }
    {
        // A homogeneous aggregate that no longer fits in the d registers goes to the stack whole.
        Quad q = { 1, 2, 3, 4 };
        double want = 1 + 4 + 9 + 16 + 25 + 36 + 49 + 8 * 1 + 9 * 2 + 10 * 3 + 11 * 4 + 12 * 5;
        NSInvocation *inv = makeInv(t, @selector(hfaSpill:::::::quad:tail:));
        double v[7] = { 1, 2, 3, 4, 5, 6, 7 }, tail = 5;
        for (int i = 0; i < 7; i++) [inv setArgument:&v[i] atIndex:2 + i];
        [inv setArgument:&q atIndex:9]; [inv setArgument:&tail atIndex:10]; [inv invoke];
        double r; [inv getReturnValue:&r];
        check("homogeneous aggregate on the stack", r == want);
        Forwarder *f = [[Forwarder alloc] initWithTarget:t];
        check("forwarding a homogeneous aggregate on the stack", [(id)f hfaSpill:1 :2 :3 :4 :5 :6 :7 quad:q tail:5] == want);
        [f release];
    }
#if defined(__arm64__)
    {
        // The callee gets the invocation's own copy of the struct, as on macOS arm64: a parameter it
        // modifies stays modified in the invocation.
        Tri a = { 1, 2, 3 };
        NSInvocation *inv = makeInv(t, @selector(clobber:));
        [inv setArgument:&a atIndex:2]; [inv invoke]; [inv invoke];
        Tri r, back; [inv getReturnValue:&r]; [inv getArgument:&back atIndex:2];
        check("callee changing a reference parameter changes the stored argument", r.a == 0 && back.a == 0 && back.b == 0 && back.c == 0);
    }
#endif
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
