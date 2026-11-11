// Copyright (C) 2026 Lubos Dolezel
// Host test of the System V AMD64 argument and result placement used by NSMethodSignature
// and NSInvocation: lays out a call with nsinvocation-sysv-host.sh's extracted copy of that
// code, runs it through the real __invoke__ trampoline, and compares with a direct C call.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned long NSUInteger; typedef int BOOL;
#define SYSV_RETURN_REGS_SIZE 64
void ___invoke__(void *send, void *retdata, void *args, size_t len, char rettype, unsigned hfa);
void __NSExtendNarrowInteger(void *value, const char *type);
void __NSSysVStoreArgument(void *frame, size_t offset, NSUInteger size, const void *value);
BOOL __NSSysVReturnsInX87(const char *type);
void __NSSysVReturnFromRegisters(const void *regs, const char *type, NSUInteger size, void *value);
const char *__NSGetSizeAndAlignment(const char *decl, NSUInteger *size, NSUInteger *alignment, BOOL h);
// exposed from lib.c via wrappers
typedef struct { size_t offset[16]; NSUInteger size[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; } Layout;
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n);

static int fails, total;
static void report(const char *name, int ok) { total++; if (!ok) { fails++; printf("FAIL %s\n", name); } else printf("ok   %s\n", name); }

typedef struct { int a, b; } SI2;
typedef struct { long a, b; } L2;
typedef struct { double a, b; } D2;
typedef struct { float a, b, c; } F3;
typedef struct { float a, b, c, d; } F4;
typedef struct { long a; double b; } LD;
typedef struct { double a; long b; } DL;
typedef struct { char c; float f; } CF;
typedef struct { double a, b, c; } D3;
typedef struct { long a, b, c; } L3;
typedef struct { float f; } F1;
typedef struct { double d; } D1;
typedef struct { char a, b, c; } C3;
typedef struct { float a; int b; } FI;
typedef struct { int x; struct { float y; float z; } in; } Nest;
typedef union { double d; long l; } UDL;
typedef struct { float v[3]; } FA3;
typedef struct { long double x; } LDS;

// generic invocation: values given as pointers matching the type list
static void invoke(void *fn, const char *ret, const char **types, const void **vals, unsigned n, void *out)
{
    Layout l; harness_layout(&l, ret, types, n);
    unsigned char *frame = calloc(1, l.frameLength + 64);
    unsigned char *retbuf = calloc(1, 256);
    // two integer stand-ins occupy the next integer registers after the hidden pointer
    // (the harness callee functions take two leading longs)
    long lead[2] = { 0x1111, 0x2222 };
    unsigned gpbase = l.stret ? 1 : 0;
    if (l.stret) { void *p = retbuf; memcpy(frame, &p, 8); }
    memcpy(frame + gpbase * 8, lead, 16);
    for (unsigned i = 0; i < n; i++) __NSSysVStoreArgument(frame, l.offset[i], l.size[i], vals[i]);
    uint64_t regs[8] = { 0 };
    ___invoke__(fn, regs, frame, l.frameLength, __NSSysVReturnsInX87(ret) ? 0x44 : ret[0], 0);
    if (!l.stret) __NSSysVReturnFromRegisters(regs, ret, l.retsize, retbuf);
    memcpy(out, retbuf, l.retsize);
    free(frame); free(retbuf);
}
#define IS(name, cond) report(name, cond)

static L2 f_l2(long a, long b, L2 p, L2 q) { (void)a; (void)b; return (L2){ p.a + q.a, p.b + q.b }; }
static D2 f_d2(long a, long b, D2 p, double k) { return (D2){ p.a * k + a - 0x1111, p.b * k + b - 0x2222 }; }
static F3 f_f3(long a, long b, F3 p) { return (F3){ p.a + 1, p.b + 2, p.c + 3 }; }
static F4 f_f4(long a, long b, F4 p, float k) { return (F4){ p.a * k, p.b * k, p.c * k, p.d * k }; }
static LD f_ld(long a, long b, LD p) { return (LD){ p.a + 1, p.b + 0.5 }; }
static DL f_dl(long a, long b, DL p) { return (DL){ p.a + 0.25, p.b + 7 }; }
static CF f_cf(long a, long b, CF p) { return (CF){ p.c + 1, p.f * 2 }; }
static D3 f_d3(long a, long b, D3 p, D3 q) { return (D3){ p.a + q.a, p.b + q.b, p.c + q.c }; }
static L3 f_l3(long a, long b, L3 p) { return (L3){ p.a + 1, p.b + 2, p.c + 3 }; }
static F1 f_f1(long a, long b, F1 p) { return (F1){ p.f * 3 }; }
static D1 f_d1(long a, long b, D1 p) { return (D1){ p.d * 3 }; }
static C3 f_c3(long a, long b, C3 p) { return (C3){ p.a + 1, p.b + 1, p.c + 1 }; }
static FI f_fi(long a, long b, FI p) { return (FI){ p.a + 1, p.b + 1 }; }
static Nest f_nest(long a, long b, Nest p) { return (Nest){ p.x + 1, { p.in.y * 2, p.in.z * 3 } }; }
static UDL f_udl(long a, long b, UDL p) { UDL r; r.d = p.d * 2; return r; }
static FA3 f_fa3(long a, long b, FA3 p) { return (FA3){ { p.v[0] + 1, p.v[1] + 1, p.v[2] + 1 } }; }
static LDS f_lds(long a, long b, LDS p) { return (LDS){ p.x + 1 }; }
static long double f_ldbl(long a, long b, long double x, double y) { return x * 2 + y; }
static float f_float(long a, long b, float x, double y, float z) { return x + (float)y + z; }
static double f_manyd(long a, long b, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9, double d10) {
    return d1 + 2*d2 + 3*d3 + 4*d4 + 5*d5 + 6*d6 + 7*d7 + 8*d8 + 9*d9 + 10*d10; }
static long f_manyi(long a, long b, int i3, char i4, short i5, long i6, int i7, long i8, unsigned char i9, long i10) {
    return i3 + 2*i4 + 3*i5 + 4*i6 + 5*i7 + 6*i8 + 7*i9 + 8*i10; }
static D2 f_regexhaust(long a, long b, long c, long d, long e, L2 x, D2 y) { return (D2){ y.a + x.a, y.b + x.b + c + d + e }; }
static long f_spill_struct(long a, long b, long c, long d, long e, L2 x, L2 y) { return x.a + y.b + e + c; }
static double f_spill_dstruct(long a, long b, D2 p1, D2 p2, D2 p3, D2 p4, D2 p5) { return p1.a + p2.b + p3.a + p4.b + p5.a + p5.b; }
static LD f_mixmany(long a, long b, long c, long d, long e, long f, LD x) { return (LD){ x.a + f, x.b }; }

int main(void)
{
    {   L2 p = {1, 2}, q = {10, 20}, r; const char *t[] = { "{L2=qq}", "{L2=qq}" }; const void *v[] = { &p, &q };
        invoke(f_l2, "{L2=qq}", t, v, 2, &r); IS("16-byte INTEGER struct", r.a == 11 && r.b == 22); }
    {   D2 p = {1.5, 2.5}, r; double k = 2; const char *t[] = { "{D2=dd}", "d" }; const void *v[] = { &p, &k };
        invoke(f_d2, "{D2=dd}", t, v, 2, &r); IS("two doubles in xmm0/xmm1", r.a == 3.0 + 0x2222 - 0x2222 + (0x1111 - 0x1111) && r.b == 5.0); }
    {   F3 p = {1, 2, 3}, r; const char *t[] = { "{F3=fff}" }; const void *v[] = { &p };
        invoke(f_f3, "{F3=fff}", t, v, 1, &r); IS("three floats (12 bytes, two SSE eightbytes)", r.a == 2 && r.b == 4 && r.c == 6); }
    {   F4 p = {1, 2, 3, 4}, r; float k = 3; const char *t[] = { "{F4=ffff}", "f" }; const void *v[] = { &p, &k };
        invoke(f_f4, "{F4=ffff}", t, v, 2, &r); IS("four floats and a float", r.a == 3 && r.b == 6 && r.c == 9 && r.d == 12); }
    {   LD p = {5, 1.25}, r; const char *t[] = { "{LD=qd}" }; const void *v[] = { &p };
        invoke(f_ld, "{LD=qd}", t, v, 1, &r); IS("INTEGER then SSE", r.a == 6 && r.b == 1.75); }
    {   DL p = {1.5, 5}, r; const char *t[] = { "{DL=dq}" }; const void *v[] = { &p };
        invoke(f_dl, "{DL=dq}", t, v, 1, &r); IS("SSE then INTEGER", r.a == 1.75 && r.b == 12); }
    {   CF p = {3, 2.5f}, r; const char *t[] = { "{CF=cf}" }; const void *v[] = { &p };
        invoke(f_cf, "{CF=cf}", t, v, 1, &r); IS("char+float (one INTEGER eightbyte)", r.c == 4 && r.f == 5.0f); }
    {   D3 p = {1, 2, 3}, q = {10, 20, 30}, r; const char *t[] = { "{D3=ddd}", "{D3=ddd}" }; const void *v[] = { &p, &q };
        invoke(f_d3, "{D3=ddd}", t, v, 2, &r); IS("24-byte struct args and sret result", r.a == 11 && r.b == 22 && r.c == 33); }
    {   L3 p = {1, 2, 3}, r; const char *t[] = { "{L3=qqq}" }; const void *v[] = { &p };
        invoke(f_l3, "{L3=qqq}", t, v, 1, &r); IS("24-byte INTEGER struct sret", r.a == 2 && r.b == 4 && r.c == 6); }
    {   F1 p = {1.5f}, r; const char *t[] = { "{F1=f}" }; const void *v[] = { &p };
        invoke(f_f1, "{F1=f}", t, v, 1, &r); IS("single-float struct", r.f == 4.5f); }
    {   D1 p = {1.5}, r; const char *t[] = { "{D1=d}" }; const void *v[] = { &p };
        invoke(f_d1, "{D1=d}", t, v, 1, &r); IS("single-double struct", r.d == 4.5); }
    {   C3 p = {1, 2, 3}, r; const char *t[] = { "{C3=ccc}" }; const void *v[] = { &p };
        invoke(f_c3, "{C3=ccc}", t, v, 1, &r); IS("3-byte struct", r.a == 2 && r.b == 3 && r.c == 4); }
    {   FI p = {1.5f, 3}, r; const char *t[] = { "{FI=fi}" }; const void *v[] = { &p };
        invoke(f_fi, "{FI=fi}", t, v, 1, &r); IS("float+int in one eightbyte is INTEGER", r.a == 2.5f && r.b == 4); }
    {   Nest p = {1, {2, 3}}, r; const char *t[] = { "{Nest=i{?=ff}}" }; const void *v[] = { &p };
        invoke(f_nest, "{Nest=i{?=ff}}", t, v, 1, &r); IS("nested struct (INTEGER, SSE)", r.x == 2 && r.in.y == 4 && r.in.z == 9); }
    {   UDL p; p.d = 2.5; UDL r; const char *t[] = { "(UDL=dq)" }; const void *v[] = { &p };
        invoke(f_udl, "(UDL=dq)", t, v, 1, &r); IS("union of double and long (INTEGER)", r.d == 5.0); }
    {   FA3 p = {{1, 2, 3}}, r; const char *t[] = { "{FA3=[3f]}" }; const void *v[] = { &p };
        invoke(f_fa3, "{FA3=[3f]}", t, v, 1, &r); IS("float array member", r.v[0] == 2 && r.v[1] == 3 && r.v[2] == 4); }
    {   LDS p = {2.5L}, r; const char *t[] = { "{LDS=D}" }; const void *v[] = { &p };
        invoke(f_lds, "{LDS=D}", t, v, 1, &r); IS("struct with long double (memory)", r.x == 3.5L); }
    {   long double x = 1.5L, r; double y = 0.25; const char *t[] = { "D", "d" }; const void *v[] = { &x, &y };
        invoke(f_ldbl, "D", t, v, 2, &r); IS("long double argument and x87 result", r == 3.25L); }
    {   float x = 1, z = 4, r; double y = 2; const char *t[] = { "f", "d", "f" }; const void *v[] = { &x, &y, &z };
        invoke(f_float, "f", t, v, 3, &r); IS("float and double mix", r == 7.0f); }
    {   double d[10], r, want = 0; const void *v[10]; const char *t[10];
        for (int i = 0; i < 10; i++) { d[i] = i + 1; want += (i + 1) * (double)(i + 1); v[i] = &d[i]; t[i] = "d"; }
        invoke(f_manyd, "d", t, v, 10, &r); IS("ten doubles (two on the stack)", r == want); }
    {   int i3 = 3; char i4 = 4; short i5 = 5; long i6 = 6; int i7 = 7; long i8 = 8; unsigned char i9 = 9; long i10 = 10, r;
        const char *t[] = { "i", "c", "s", "q", "i", "q", "C", "q" }; const void *v[] = { &i3, &i4, &i5, &i6, &i7, &i8, &i9, &i10 };
        invoke(f_manyi, "q", t, v, 8, &r); IS("eight integers of different widths (stack slots are 8 bytes)", r == 3 + 8 + 15 + 24 + 35 + 48 + 63 + 80); }
    {   L2 x = {1, 2}; D2 y = {0.5, 1.5}, r; long c = 100, d = 200, e = 300;
        const char *t[] = { "q", "q", "q", "{L2=qq}", "{D2=dd}" }; const void *v[] = { &c, &d, &e, &x, &y };
        invoke(f_regexhaust, "{D2=dd}", t, v, 5, &r); IS("struct that no longer fits in registers goes to the stack whole", r.a == 1.5 && r.b == 3.5 + 600); }
    {   L2 x = {1, 2}, y = {10, 20}; long c = 100, d = 200, e = 300, r;
        const char *t[] = { "q", "q", "q", "{L2=qq}", "{L2=qq}" }; const void *v[] = { &c, &d, &e, &x, &y };
        invoke(f_spill_struct, "q", t, v, 5, &r); IS("two INTEGER structs spilling", r == 1 + 20 + 300 + 100); }
    {   D2 p[5] = { {1,2}, {3,4}, {5,6}, {7,8}, {9,10} }; double r; const char *t[5]; const void *v[5];
        for (int i = 0; i < 5; i++) { t[i] = "{D2=dd}"; v[i] = &p[i]; }
        invoke(f_spill_dstruct, "d", t, v, 5, &r); IS("five double pairs (last spills to the stack)", r == 1 + 4 + 5 + 8 + 9 + 10); }
    {   LD x = {5, 2.5}, r; long c = 1, d = 2, e = 3, f = 4; const char *t[] = { "q", "q", "q", "q", "{LD=qd}" }; const void *v[] = { &c, &d, &e, &f, &x };
        invoke(f_mixmany, "{LD=qd}", t, v, 5, &r); IS("INTEGER,SSE struct when only one integer register is left (stack)", r.a == 9 && r.b == 2.5); }
    {   // Frame lengths NSMethodSignature reports on macOS x86_64 (observed under Rosetta, see MAC-EVIDENCE.md);
        // the two leading integer registers stand in for self and _cmd.
        struct { const char *ret; const char *arg; unsigned count; NSUInteger frame; const char *name; } cases[] = {
            { "{?=qqq}", "q", 0, 224, "hidden result pointer adds nothing to the frame" },
            { "{?=qqq}", "q", 5, 240, "stack arguments after a hidden result pointer" },
            { "d", "d", 10, 240, "ten doubles, two on the stack" },
            { "v", "q", 7, 248, "seven integers, three on the stack" },
            { "v", "{?=qq}", 3, 240, "third integer pair on the stack" },
            { "v", "{?=dd}", 5, 240, "fifth double pair on the stack" },
            { "v", "c", 4, 224, "narrow integers stay in registers" },
        };
        for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
            const char *t[16]; for (unsigned k = 0; k < cases[i].count; k++) t[k] = cases[i].arg;
            Layout l; harness_layout(&l, cases[i].ret, t, cases[i].count);
            report(cases[i].name, l.frameLength == cases[i].frame);
        }
    }
    {   unsigned char slot[8] = { 0xff, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa }; __NSExtendNarrowInteger(slot, "c");
        report("signed char argument widened to 32 bits", *(int32_t *)slot == -1); }
    {   unsigned char slot[8] = { 0x01, 0x01, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa }; __NSExtendNarrowInteger(slot, "B");
        report("BOOL argument widened to 32 bits", *(uint32_t *)slot == 1); }
    printf("%d/%d\n", total - fails, total);
    return fails != 0;
}
