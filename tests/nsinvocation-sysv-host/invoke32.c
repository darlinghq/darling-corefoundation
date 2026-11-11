// Copyright (C) 2026 Lubos Dolezel
// Host test of the i386 result and argument placement used by NSMethodSignature and NSInvocation:
// lays out a call with run.sh's extracted copy of that code, runs it through the real __invoke__
// trampoline (32-bit build), and compares with a direct C call compiled with -freg-struct-return,
// which returns small structs in registers as the Darwin i386 ABI does.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned long NSUInteger; typedef int BOOL;
typedef struct { size_t offset[16]; NSUInteger size[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; } Layout;
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n);
void ___invoke__(void *send, void *retdata, void *args, size_t len, char rettype, unsigned hfa);
BOOL __NSI386ResultInMemory(const char *type, NSUInteger size);
char __NSI386X87ResultType(const char *type);
void __NSExtendNarrowInteger(void *value, const char *type);

static int fails, total;
static void report(const char *name, int ok) { total++; if (!ok) { fails++; printf("FAIL %s\n", name); } else printf("ok   %s\n", name); }

static void invoke(void *fn, const char *ret, const char **types, const void **vals, unsigned n, void *out)
{
    Layout l; harness_layout(&l, ret, types, n);
    unsigned char *frame = calloc(1, l.frameLength + 64);
    unsigned char *retbuf = calloc(1, 256);
    unsigned base = 0;
    if (l.stret) { void *p = retbuf; memcpy(frame, &p, 4); base = 4; }
    uint32_t lead[2] = { 0x1111, 0x2222 };
    memcpy(frame + base, lead, 8);
    for (unsigned i = 0; i < n; i++) memcpy(frame + l.offset[i], vals[i], l.size[i]);
    char x87 = __NSI386X87ResultType(ret);
    // As NSInvocation does for a hidden-pointer result, __invoke__ gets scratch space of its own.
    unsigned char scratch[80];
    ___invoke__(fn, l.stret ? (void *)scratch : (void *)retbuf, frame, l.frameLength, x87 ? x87 : ret[0], 0);
    memcpy(out, retbuf, l.retsize);
    free(frame); free(retbuf);
}

typedef struct { int a, b; } Ints2;
typedef struct { char a, b, c; } C3;
typedef struct { char a, b; } C2;
typedef struct { float a, b, c; } F3;
typedef struct { double a, b; } D2;
typedef struct { float f; } F1;
typedef struct { double d; } D1;
typedef struct { float f[1]; } FA1;
typedef struct { struct { float f; } in; } NestF;
typedef struct { char c; char d; short s; } CSC;
typedef union { int i; char c; } UIC;
typedef union { double d; int i[3]; } UBig;
typedef struct { char a[3]; char b; } CArr;

static float f_float(void *a, void *b, float x, double y) { return x + (float)y; }
static double f_double(void *a, void *b, double x, char c) { return x * 2 + c; }
static long double f_ldbl(void *a, void *b, long double x) { return x + 1; }
static long long f_q(void *a, void *b, long long x, int y) { return x * 2 + y; }
static Ints2 f_ints2(void *a, void *b, Ints2 p, int k) { return (Ints2){ p.b + k, p.a }; }
static C3 f_c3(void *a, void *b, C3 p) { return (C3){ p.a + 1, p.b + 1, p.c + 1 }; }
static C2 f_c2(void *a, void *b, C2 p) { return (C2){ p.a + 1, p.b + 1 }; }
static F3 f_f3(void *a, void *b, F3 p) { return (F3){ p.a + 1, p.b + 2, p.c + 3 }; }
static D2 f_d2(void *a, void *b, D2 p, D2 q) { return (D2){ p.a + q.a, p.b + q.b }; }
static F1 f_f1(void *a, void *b, F1 p) { return (F1){ p.f * 3 }; }
static D1 f_d1(void *a, void *b, D1 p) { return (D1){ p.d * 3 }; }
static FA1 f_fa1(void *a, void *b, FA1 p) { return (FA1){ { p.f[0] * 3 } }; }
static NestF f_nest(void *a, void *b, NestF p) { return (NestF){ { p.in.f * 3 } }; }
static CSC f_csc(void *a, void *b, CSC p) { return (CSC){ p.c + 1, p.d + 1, p.s + 1 }; }
static UIC f_uic(void *a, void *b, UIC p) { UIC r; r.i = p.i + 1; return r; }
static UBig f_ubig(void *a, void *b, UBig p) { UBig r = p; r.d += 1; return r; }
static CArr f_carr(void *a, void *b, CArr p) { return (CArr){ { p.a[0] + 1, p.a[1] + 1, p.a[2] + 1 }, p.b + 1 }; }
static int f_stack(void *a, void *b, int c, short d, char e, long long f, int g, double h) { return c + 2 * d + 3 * e + 4 * (int)f + 5 * g + 6 * (int)h; }

int main(void)
{
    { float x = 1.5f, r; double y = 2.25; const char *t[] = { "f", "d" }; const void *v[] = { &x, &y };
      invoke(f_float, "f", t, v, 2, &r); report("float result in st(0)", r == 3.75f); }
    { double x = 1.5, r; char c = 7; const char *t[] = { "d", "c" }; const void *v[] = { &x, &c };
      invoke(f_double, "d", t, v, 2, &r); report("double result in st(0)", r == 10.0); }
    { long double x = 1.5L, r; const char *t[] = { "D" }; const void *v[] = { &x };
      invoke(f_ldbl, "D", t, v, 1, &r); report("long double result in st(0)", r == 2.5L); }
    { long long x = 1LL << 40, r; int y = 5; const char *t[] = { "q", "i" }; const void *v[] = { &x, &y };
      invoke(f_q, "q", t, v, 2, &r); report("64-bit integer result in eax:edx", r == (1LL << 41) + 5); }
    { Ints2 p = { 1, 2 }, r; int k = 10; const char *t[] = { "{Ints2=ii}", "i" }; const void *v[] = { &p, &k };
      invoke(f_ints2, "{Ints2=ii}", t, v, 2, &r); report("8-byte struct in eax:edx", r.a == 12 && r.b == 1); }
    { C2 p = { 1, 2 }, r; const char *t[] = { "{C2=cc}" }; const void *v[] = { &p };
      invoke(f_c2, "{C2=cc}", t, v, 1, &r); report("2-byte struct in eax", r.a == 2 && r.b == 3); }
    { C3 p = { 1, 2, 3 }, r; const char *t[] = { "{C3=ccc}" }; const void *v[] = { &p };
      invoke(f_c3, "{C3=ccc}", t, v, 1, &r); report("3-byte struct through a hidden pointer", r.a == 2 && r.b == 3 && r.c == 4); }
    { F3 p = { 1, 2, 3 }, r; const char *t[] = { "{F3=fff}" }; const void *v[] = { &p };
      invoke(f_f3, "{F3=fff}", t, v, 1, &r); report("12-byte struct through a hidden pointer", r.a == 2 && r.b == 4 && r.c == 6); }
    { D2 p = { 1, 2 }, q = { 10, 20 }, r; const char *t[] = { "{D2=dd}", "{D2=dd}" }; const void *v[] = { &p, &q };
      invoke(f_d2, "{D2=dd}", t, v, 2, &r); report("16-byte struct through a hidden pointer", r.a == 11 && r.b == 22); }
    { F1 p = { 1.5f }, r; const char *t[] = { "{F1=f}" }; const void *v[] = { &p };
      invoke(f_f1, "{F1=f}", t, v, 1, &r); report("single-float struct in st(0)", r.f == 4.5f); }
    { D1 p = { 1.5 }, r; const char *t[] = { "{D1=d}" }; const void *v[] = { &p };
      invoke(f_d1, "{D1=d}", t, v, 1, &r); report("single-double struct in st(0)", r.d == 4.5); }
    { FA1 p = { { 1.5f } }, r; const char *t[] = { "{FA1=[1f]}" }; const void *v[] = { &p };
      invoke(f_fa1, "{FA1=[1f]}", t, v, 1, &r); report("struct with a one-element float array in st(0)", r.f[0] == 4.5f); }
    { NestF p = { { 1.5f } }, r; const char *t[] = { "{NestF={?=f}}" }; const void *v[] = { &p };
      invoke(f_nest, "{NestF={?=f}}", t, v, 1, &r); report("nested single-float struct in st(0)", r.in.f == 4.5f); }
    { CSC p = { 1, 3, 2 }, r; const char *t[] = { "{CSC=ccs}" }; const void *v[] = { &p };
      invoke(f_csc, "{CSC=ccs}", t, v, 1, &r); report("4-byte struct of mixed members in eax", r.c == 2 && r.s == 3 && r.d == 4); }
    { UIC p; p.i = 41; UIC r; const char *t[] = { "(UIC=ic)" }; const void *v[] = { &p };
      invoke(f_uic, "(UIC=ic)", t, v, 1, &r); report("small union in eax", r.i == 42); }
    { UBig p; memset(&p, 0, sizeof p); p.d = 2.5; UBig r; const char *t[] = { "(UBig=d[3i])" }; const void *v[] = { &p };
      invoke(f_ubig, "(UBig=d[3i])", t, v, 1, &r); report("12-byte union through a hidden pointer", r.d == 3.5); }
    { CArr p = { { 1, 2, 3 }, 4 }, r; const char *t[] = { "{CArr=[3c]c}" }; const void *v[] = { &p };
      invoke(f_carr, "{CArr=[3c]c}", t, v, 1, &r); report("4-byte struct with a 3-byte array member through a hidden pointer", r.a[0] == 2 && r.a[2] == 4 && r.b == 5); }
    { int c = 1, g = 5; short d = 2; char e = 3; long long f = 4; double h = 6; int r;
      const char *t[] = { "i", "s", "c", "q", "i", "d" }; const void *v[] = { &c, &d, &e, &f, &g, &h };
      invoke(f_stack, "i", t, v, 6, &r); report("stack arguments of mixed widths", r == 1 + 4 + 9 + 16 + 25 + 36); }
    { unsigned char slot[4] = { 0xff, 0xaa, 0xaa, 0xaa }; __NSExtendNarrowInteger(slot, "c");
      report("signed char argument widened to 32 bits", *(int32_t *)slot == -1); }
    { unsigned char slot[4] = { 0xff, 0xaa, 0xaa, 0xaa }; __NSExtendNarrowInteger(slot, "C");
      report("unsigned char argument widened to 32 bits", *(uint32_t *)slot == 255); }
    { unsigned char slot[4] = { 0x00, 0x80, 0xaa, 0xaa }; __NSExtendNarrowInteger(slot, "s");
      report("short argument widened to 32 bits", *(int32_t *)slot == -32768); }
    report("empty struct is not a hidden-pointer result", !__NSI386ResultInMemory("{E=}", 0));
    printf("%d/%d\n", total - fails, total);
    return fails != 0;
}
