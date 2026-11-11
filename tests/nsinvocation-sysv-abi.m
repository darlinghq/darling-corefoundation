// Copyright (C) 2026 Lubos Dolezel
// Build against the candidate CoreFoundation and run under Darling; see nsinvocation-sysv-abi.md.
// Covers NSInvocation and message forwarding with floating-point, struct and stack arguments
// and results as the System V AMD64 ABI (x86_64) and the i386 cdecl convention pass them.
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>
#include <string.h>

static int pass, total;

static void report(const char *label, int ok) {
    total++;
    pass += ok;
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
}

typedef struct { int a, b; } Ints2;                     // 8 bytes: one INTEGER eightbyte (eax:edx on i386)
typedef struct { long a, b; } Pair;                     // 16 bytes, rax:rdx
typedef struct { double a, b; } Doubles2;               // xmm0:xmm1
typedef struct { float a, b, c; } Floats3;              // 12 bytes, two SSE eightbytes
typedef struct { float a, b, c, d; } Floats4;           // 16 bytes, two SSE eightbytes
typedef struct { long a; double b; } IntDouble;         // rax:xmm0
typedef struct { double a; long b; } DoubleInt;         // xmm0:rax
typedef struct { char a, b, c; } Chars3;                // 3 bytes: hidden pointer on i386
typedef struct { double a, b, c; } Doubles3;            // 24 bytes: MEMORY
typedef struct { long a, b, c, d, e; } Big;             // 40 bytes: MEMORY

@interface Target : NSObject
- (double)mixInt:(int)a float:(float)f double:(double)d longLong:(long long)l;
- (float)scaleFloat:(float)f by:(float)k;
- (double)addDouble:(double)a to:(double)b;
- (long double)longDouble:(long double)x plus:(double)y;
- (Ints2)swapInts:(Ints2)s;
- (Pair)addPair:(Pair)p to:(Pair)q;
- (Doubles2)scaleDoubles:(Doubles2)p by:(double)k;
- (Floats3)bumpFloats3:(Floats3)f;
- (Floats4)scaleFloats4:(Floats4)f by:(float)k;
- (IntDouble)bumpIntDouble:(IntDouble)v;
- (DoubleInt)bumpDoubleInt:(DoubleInt)v;
- (Chars3)bumpChars3:(Chars3)c;
- (Doubles3)addDoubles3:(Doubles3)p to:(Doubles3)q withLong:(long)l;
- (Big)bumpBig:(Big)b;
- (long)eightInts:(int)a :(char)b :(short)c :(long)d :(int)e :(long)f :(unsigned char)g :(long)h;
- (double)tenDoubles:(double)a :(double)b :(double)c :(double)d :(double)e :(double)f :(double)g :(double)h :(double)i :(double)j;
- (Doubles2)manyRegisters:(long)a :(long)b :(long)c :(long)d :(Pair)p :(Doubles2)q;
- (long)stackPair:(long)a :(long)b :(long)c :(long)d :(Pair)p :(Pair)q;
- (double)fiveDoublePairs:(Doubles2)a :(Doubles2)b :(Doubles2)c :(Doubles2)d :(Doubles2)e;
- (IntDouble)lateIntDouble:(long)a :(long)b :(long)c :(long)d :(long)e :(IntDouble)v;
@end

@implementation Target
- (double)mixInt:(int)a float:(float)f double:(double)d longLong:(long long)l { return a + f + d + l; }
- (float)scaleFloat:(float)f by:(float)k { return f * k; }
- (double)addDouble:(double)a to:(double)b { return a + b; }
- (long double)longDouble:(long double)x plus:(double)y { return x * 2 + y; }
- (Ints2)swapInts:(Ints2)s { Ints2 r = { s.b, s.a }; return r; }
- (Pair)addPair:(Pair)p to:(Pair)q { Pair r = { p.a + q.a, p.b + q.b }; return r; }
- (Doubles2)scaleDoubles:(Doubles2)p by:(double)k { Doubles2 r = { p.a * k, p.b * k }; return r; }
- (Floats3)bumpFloats3:(Floats3)f { Floats3 r = { f.a + 1, f.b + 2, f.c + 3 }; return r; }
- (Floats4)scaleFloats4:(Floats4)f by:(float)k { Floats4 r = { f.a * k, f.b * k, f.c * k, f.d * k }; return r; }
- (IntDouble)bumpIntDouble:(IntDouble)v { IntDouble r = { v.a + 1, v.b + 0.5 }; return r; }
- (DoubleInt)bumpDoubleInt:(DoubleInt)v { DoubleInt r = { v.a + 0.25, v.b + 7 }; return r; }
- (Chars3)bumpChars3:(Chars3)c { Chars3 r = { c.a + 1, c.b + 1, c.c + 1 }; return r; }
- (Doubles3)addDoubles3:(Doubles3)p to:(Doubles3)q withLong:(long)l { Doubles3 r = { p.a + q.a, p.b + q.b, p.c + q.c + l }; return r; }
- (Big)bumpBig:(Big)b { Big r = { b.a + 1, b.b + 1, b.c + 1, b.d + 1, b.e + 1 }; return r; }
- (long)eightInts:(int)a :(char)b :(short)c :(long)d :(int)e :(long)f :(unsigned char)g :(long)h {
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h;
}
- (double)tenDoubles:(double)a :(double)b :(double)c :(double)d :(double)e :(double)f :(double)g :(double)h :(double)i :(double)j {
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h + 9 * i + 10 * j;
}
- (Doubles2)manyRegisters:(long)a :(long)b :(long)c :(long)d :(Pair)p :(Doubles2)q { Doubles2 r = { q.a + p.a, q.b + p.b + a + b + c + d }; return r; }
- (long)stackPair:(long)a :(long)b :(long)c :(long)d :(Pair)p :(Pair)q { return p.a + q.b + a + d; }
- (double)fiveDoublePairs:(Doubles2)a :(Doubles2)b :(Doubles2)c :(Doubles2)d :(Doubles2)e { return a.a + b.b + c.a + d.b + e.a + e.b; }
- (IntDouble)lateIntDouble:(long)a :(long)b :(long)c :(long)d :(long)e :(IntDouble)v { IntDouble r = { v.a + e, v.b }; return r; }
@end

static NSInvocation *makeInv(id t, SEL sel) {
    NSMethodSignature *sig = [t methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:t];
    [inv setSelector:sel];
    return inv;
}

// Forwards everything to a Target through forwardInvocation:.
@interface Forwarder : NSObject { Target *t; }
- (id)initWithTarget:(Target *)target;
@end
@implementation Forwarder
- (id)initWithTarget:(Target *)target { if ((self = [super init])) t = target; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [t methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)inv { [inv invokeWithTarget:t]; }
@end

// Redirects everything with -forwardingTargetForSelector:, which restarts the message send.
@interface Redirector : NSObject { Target *t; }
- (id)initWithTarget:(Target *)target;
@end
@implementation Redirector
- (id)initWithTarget:(Target *)target { if ((self = [super init])) t = target; return self; }
- (id)forwardingTargetForSelector:(SEL)sel { return t; }
@end

#define INVOKE_RET(var, inv) do { [inv invoke]; [inv getReturnValue:&var]; } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    Target *t = [Target new];

    // Direct invocation through NSInvocation.
    {
        SEL s = @selector(mixInt:float:double:longLong:); NSInvocation *inv = makeInv(t, s);
        int a = 1; float f = 2.5f; double d = 4.25; long long l = 1LL << 40;
        [inv setArgument:&a atIndex:2]; [inv setArgument:&f atIndex:3]; [inv setArgument:&d atIndex:4]; [inv setArgument:&l atIndex:5];
        double r = 0; INVOKE_RET(r, inv);
        report("int, float, double and long long arguments", r == 1 + 2.5 + 4.25 + (double)(1LL << 40));
    }
    {
        SEL s = @selector(scaleFloat:by:); NSInvocation *inv = makeInv(t, s);
        float f = 3, k = 1.5f; [inv setArgument:&f atIndex:2]; [inv setArgument:&k atIndex:3];
        float r = 0; INVOKE_RET(r, inv);
        report("float arguments and result", r == 4.5f);
    }
    {
        SEL s = @selector(addDouble:to:); NSInvocation *inv = makeInv(t, s);
        double a = 1.25, b = 2.5; [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3];
        double r = 0; INVOKE_RET(r, inv);
        report("double arguments and result", r == 3.75);
    }
    {
        SEL s = @selector(longDouble:plus:); NSInvocation *inv = makeInv(t, s);
        long double x = 1.5L; double y = 0.25; [inv setArgument:&x atIndex:2]; [inv setArgument:&y atIndex:3];
        long double r = 0; INVOKE_RET(r, inv);
        report("long double argument and result", r == 3.25L);
    }
    {
        SEL s = @selector(swapInts:); NSInvocation *inv = makeInv(t, s);
        Ints2 a = { 1, 2 }; [inv setArgument:&a atIndex:2];
        Ints2 r = { 0, 0 }; INVOKE_RET(r, inv);
        report("8-byte struct argument and result", r.a == 2 && r.b == 1);
    }
    {
        SEL s = @selector(addPair:to:); NSInvocation *inv = makeInv(t, s);
        Pair a = { 1, 2 }, b = { 10, 20 }; [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3];
        Pair r = { 0, 0 }; INVOKE_RET(r, inv);
        report("16-byte integer struct arguments and result", r.a == 11 && r.b == 22);
    }
    {
        SEL s = @selector(scaleDoubles:by:); NSInvocation *inv = makeInv(t, s);
        Doubles2 p = { 1.5, 2.5 }; double k = 2; [inv setArgument:&p atIndex:2]; [inv setArgument:&k atIndex:3];
        Doubles2 r = { 0, 0 }; INVOKE_RET(r, inv);
        report("two-double struct argument and result", r.a == 3 && r.b == 5);
    }
    {
        SEL s = @selector(bumpFloats3:); NSInvocation *inv = makeInv(t, s);
        Floats3 f = { 1, 2, 3 }; [inv setArgument:&f atIndex:2];
        Floats3 r = { 0, 0, 0 }; INVOKE_RET(r, inv);
        report("three-float struct argument and result", r.a == 2 && r.b == 4 && r.c == 6);
    }
    {
        SEL s = @selector(scaleFloats4:by:); NSInvocation *inv = makeInv(t, s);
        Floats4 f = { 1, 2, 3, 4 }; float k = 3; [inv setArgument:&f atIndex:2]; [inv setArgument:&k atIndex:3];
        Floats4 r = { 0, 0, 0, 0 }; INVOKE_RET(r, inv);
        report("four-float struct and a float argument", r.a == 3 && r.b == 6 && r.c == 9 && r.d == 12);
    }
    {
        SEL s = @selector(bumpIntDouble:); NSInvocation *inv = makeInv(t, s);
        IntDouble v = { 5, 1.25 }; [inv setArgument:&v atIndex:2];
        IntDouble r = { 0, 0 }; INVOKE_RET(r, inv);
        report("integer and double struct argument and result", r.a == 6 && r.b == 1.75);
    }
    {
        SEL s = @selector(bumpDoubleInt:); NSInvocation *inv = makeInv(t, s);
        DoubleInt v = { 1.5, 5 }; [inv setArgument:&v atIndex:2];
        DoubleInt r = { 0, 0 }; INVOKE_RET(r, inv);
        report("double and integer struct argument and result", r.a == 1.75 && r.b == 12);
    }
    {
        SEL s = @selector(bumpChars3:); NSInvocation *inv = makeInv(t, s);
        Chars3 c = { 1, 2, 3 }; [inv setArgument:&c atIndex:2];
        Chars3 r = { 0, 0, 0 }; INVOKE_RET(r, inv);
        report("3-byte struct argument and result", r.a == 2 && r.b == 3 && r.c == 4);
    }
    {
        SEL s = @selector(addDoubles3:to:withLong:); NSInvocation *inv = makeInv(t, s);
        Doubles3 p = { 1, 2, 3 }, q = { 10, 20, 30 }; long l = 100;
        [inv setArgument:&p atIndex:2]; [inv setArgument:&q atIndex:3]; [inv setArgument:&l atIndex:4];
        Doubles3 r; memset(&r, 0, sizeof r); INVOKE_RET(r, inv);
        report("24-byte struct arguments and result (memory)", r.a == 11 && r.b == 22 && r.c == 133);
    }
    {
        SEL s = @selector(bumpBig:); NSInvocation *inv = makeInv(t, s);
        Big b = { 1, 2, 3, 4, 5 }; [inv setArgument:&b atIndex:2];
        Big r; memset(&r, 0, sizeof r); INVOKE_RET(r, inv);
        report("40-byte struct argument and result (memory)", r.a == 2 && r.b == 3 && r.c == 4 && r.d == 5 && r.e == 6);
    }
    {
        SEL s = @selector(eightInts::::::::); NSInvocation *inv = makeInv(t, s);
        int a = 1; char b = 2; short c = 3; long d = 4; int e = 5; long f = 6; unsigned char g = 7; long h = 8;
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3]; [inv setArgument:&c atIndex:4]; [inv setArgument:&d atIndex:5];
        [inv setArgument:&e atIndex:6]; [inv setArgument:&f atIndex:7]; [inv setArgument:&g atIndex:8]; [inv setArgument:&h atIndex:9];
        long r = 0; INVOKE_RET(r, inv);
        report("eight integers of mixed widths (stack slots are one word each)", r == 1 + 4 + 9 + 16 + 25 + 36 + 49 + 64);
    }
    {
        SEL s = @selector(tenDoubles::::::::::); NSInvocation *inv = makeInv(t, s);
        double v[10]; double want = 0;
        for (int i = 0; i < 10; i++) { v[i] = i + 1; want += (double)(i + 1) * (i + 1); [inv setArgument:&v[i] atIndex:2 + i]; }
        double r = 0; INVOKE_RET(r, inv);
        report("ten double arguments (two on the stack)", r == want);
    }
    {
        SEL s = @selector(manyRegisters::::::); NSInvocation *inv = makeInv(t, s);
        long a = 1, b = 2, c = 3, d = 4; Pair p = { 100, 200 }; Doubles2 q = { 0.5, 1.5 };
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3]; [inv setArgument:&c atIndex:4]; [inv setArgument:&d atIndex:5];
        [inv setArgument:&p atIndex:6]; [inv setArgument:&q atIndex:7];
        Doubles2 r = { 0, 0 }; INVOKE_RET(r, inv);
        report("integer struct that does not fit in the remaining registers", r.a == 100.5 && r.b == 211.5);
    }
    {
        SEL s = @selector(stackPair::::::); NSInvocation *inv = makeInv(t, s);
        long a = 1, b = 2, c = 3, d = 4; Pair p = { 100, 200 }, q = { 300, 400 };
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3]; [inv setArgument:&c atIndex:4]; [inv setArgument:&d atIndex:5];
        [inv setArgument:&p atIndex:6]; [inv setArgument:&q atIndex:7];
        long r = 0; INVOKE_RET(r, inv);
        report("integer structs passed on the stack", r == 100 + 400 + 1 + 4);
    }
    {
        SEL s = @selector(fiveDoublePairs:::::); NSInvocation *inv = makeInv(t, s);
        Doubles2 p[5] = { {1, 2}, {3, 4}, {5, 6}, {7, 8}, {9, 10} };
        for (int i = 0; i < 5; i++) [inv setArgument:&p[i] atIndex:2 + i];
        double r = 0; INVOKE_RET(r, inv);
        report("five double pairs (the last pair goes to the stack)", r == 1 + 4 + 5 + 8 + 9 + 10);
    }
    {
        SEL s = @selector(lateIntDouble::::::); NSInvocation *inv = makeInv(t, s);
        long v[5] = { 1, 2, 3, 4, 5 }; IntDouble x = { 10, 2.5 };
        for (int i = 0; i < 5; i++) [inv setArgument:&v[i] atIndex:2 + i];
        [inv setArgument:&x atIndex:7];
        IntDouble r = { 0, 0 }; INVOKE_RET(r, inv);
        report("mixed-class struct when too few integer registers remain", r.a == 15 && r.b == 2.5);
    }

    // The same through message forwarding: -forwardInvocation: and -forwardingTargetForSelector:.
    {
        Forwarder *f = [[Forwarder alloc] initWithTarget:t];
        report("forwarding: int, float, double and long long", [(id)f mixInt:1 float:2.5f double:4.25 longLong:2] == 9.75);
        report("forwarding: float result", [(id)f scaleFloat:3 by:1.5f] == 4.5f);
        report("forwarding: double result", [(id)f addDouble:1.25 to:2.5] == 3.75);
        report("forwarding: long double result", [(id)f longDouble:1.5L plus:0.25] == 3.25L);
        Ints2 i2 = [(id)f swapInts:(Ints2){ 1, 2 }];
        report("forwarding: 8-byte struct", i2.a == 2 && i2.b == 1);
        Pair pr = [(id)f addPair:(Pair){ 1, 2 } to:(Pair){ 10, 20 }];
        report("forwarding: 16-byte integer struct", pr.a == 11 && pr.b == 22);
        Doubles2 d2 = [(id)f scaleDoubles:(Doubles2){ 1.5, 2.5 } by:2];
        report("forwarding: two-double struct", d2.a == 3 && d2.b == 5);
        Floats3 f3 = [(id)f bumpFloats3:(Floats3){ 1, 2, 3 }];
        report("forwarding: three-float struct", f3.a == 2 && f3.b == 4 && f3.c == 6);
        Floats4 f4 = [(id)f scaleFloats4:(Floats4){ 1, 2, 3, 4 } by:3];
        report("forwarding: four-float struct", f4.a == 3 && f4.b == 6 && f4.c == 9 && f4.d == 12);
        IntDouble id1 = [(id)f bumpIntDouble:(IntDouble){ 5, 1.25 }];
        report("forwarding: integer and double struct", id1.a == 6 && id1.b == 1.75);
        DoubleInt di = [(id)f bumpDoubleInt:(DoubleInt){ 1.5, 5 }];
        report("forwarding: double and integer struct", di.a == 1.75 && di.b == 12);
        Chars3 c3 = [(id)f bumpChars3:(Chars3){ 1, 2, 3 }];
        report("forwarding: 3-byte struct", c3.a == 2 && c3.b == 3 && c3.c == 4);
        Doubles3 d3 = [(id)f addDoubles3:(Doubles3){ 1, 2, 3 } to:(Doubles3){ 10, 20, 30 } withLong:100];
        report("forwarding: 24-byte struct result", d3.a == 11 && d3.b == 22 && d3.c == 133);
        Big b = [(id)f bumpBig:(Big){ 1, 2, 3, 4, 5 }];
        report("forwarding: 40-byte struct result", b.a == 2 && b.e == 6);
        report("forwarding: stack arguments of mixed widths", [(id)f eightInts:1 :2 :3 :4 :5 :6 :7 :8] == 204);
        report("forwarding: ten doubles", [(id)f tenDoubles:1 :2 :3 :4 :5 :6 :7 :8 :9 :10] == 385);
        Doubles2 mr = [(id)f manyRegisters:1 :2 :3 :4 :(Pair){ 100, 200 } :(Doubles2){ 0.5, 1.5 }];
        report("forwarding: struct that spills to the stack whole", mr.a == 100.5 && mr.b == 211.5);
        report("forwarding: five double pairs", [(id)f fiveDoublePairs:(Doubles2){ 1, 2 } :(Doubles2){ 3, 4 } :(Doubles2){ 5, 6 } :(Doubles2){ 7, 8 } :(Doubles2){ 9, 10 }] == 37);
        [f release];
    }
    {
        Redirector *r = [[Redirector alloc] initWithTarget:t];
        report("forwarding target: double result", [(id)r addDouble:1.25 to:2.5] == 3.75);
        Doubles2 d2 = [(id)r scaleDoubles:(Doubles2){ 1.5, 2.5 } by:2];
        report("forwarding target: two-double struct", d2.a == 3 && d2.b == 5);
        Big b = [(id)r bumpBig:(Big){ 1, 2, 3, 4, 5 }];
        report("forwarding target: 40-byte struct result", b.a == 2 && b.e == 6);
        Doubles3 d3 = [(id)r addDoubles3:(Doubles3){ 1, 2, 3 } to:(Doubles3){ 10, 20, 30 } withLong:100];
        report("forwarding target: 24-byte struct result", d3.a == 11 && d3.b == 22 && d3.c == 133);
        report("forwarding target: long double result", [(id)r longDouble:1.5L plus:0.25] == 3.25L);
        [r release];
    }

    printf("%d/%d passed\n", pass, total);
    [pool drain];
    return pass == total ? 0 : 1;
}
