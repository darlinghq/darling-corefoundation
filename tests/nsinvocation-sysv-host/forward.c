// Copyright (C) 2026 Lubos Dolezel
// Host test of the x86_64 forwarding trampolines (__CF_forwarding_prep_0/_1): calls them as
// if they were methods that the runtime could not find, with a stand-in for ____forwarding___
// that decodes the saved registers, invokes the real implementation and returns its result.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned long NSUInteger; typedef int BOOL;
typedef struct { size_t offset[16]; NSUInteger size[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; } Layout;
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n);
void ___invoke__(void *send, void *retdata, void *args, size_t len, char rettype, unsigned hfa);
void __NSSysVStoreArgument(void *frame, size_t offset, NSUInteger size, const void *value);
void __NSSysVLoadArgument(const void *frame, size_t offset, NSUInteger size, void *value);
void __NSSysVReturnFromRegisters(const void *regs, const char *type, NSUInteger size, void *value);
void __NSSysVReturnToRegisters(const void *value, const char *type, NSUInteger size, void *regs);
BOOL __NSSysVReturnsInX87(const char *type);
void CF_forwarding_prep_0(void);
void CF_forwarding_prep_1(void);

static const char *g_ret; static const char **g_types; static unsigned g_n; static void *g_fn; static void *g_target;
static int g_restart_calls;

// Plays the part of ____forwarding___: decodes the saved frame with the signature,
// invokes g_fn with the decoded values, and hands the result back in return form.
void *forwarding_stub(void *args, void *storage, void *indirect)
{
    unsigned char *block = args;
    if (g_target) { return g_target; }
    Layout l; harness_layout(&l, g_ret, g_types, g_n);
    unsigned char *frame = calloc(1, l.frameLength + 64);
    unsigned gpbase = l.stret ? 1 : 0;
    unsigned char *retbuf = calloc(1, 256);
    if (l.stret) { memcpy(frame, &(void *){ retbuf }, 8); }
    memcpy(frame + gpbase * 8, block + gpbase * 8, 16);   // the two leading longs
    for (unsigned i = 0; i < g_n; i++) {
        unsigned char tmp[256];
        __NSSysVLoadArgument(block, l.offset[i], l.size[i], tmp);
        __NSSysVStoreArgument(frame, l.offset[i], l.size[i], tmp);
    }
    uint64_t regs[8] = { 0 };
    int x87 = __NSSysVReturnsInX87(g_ret);
    ___invoke__(g_fn, regs, frame, l.frameLength, x87 ? 0x44 : g_ret[0], 0);
    if (l.stret) {
        memcpy(indirect, retbuf, l.retsize);
    } else {
        unsigned char value[16] = { 0 };
        __NSSysVReturnFromRegisters(regs, g_ret, l.retsize, value);
        __NSSysVReturnToRegisters(value, g_ret, l.retsize, storage);
    }
    free(frame); free(retbuf);
    return NULL;
}

// restart targets
double objc_msgSend(void *self, long sel, double d, long c, long e) { g_restart_calls++; return (self == (void *)0x77 && sel == 0x1234 && d == 2.5 && c == 40 && e == 50) ? 1.0 : -1.0; }
typedef struct { long a, b, c; } L3;
L3 objc_msgSend_stret(void *self, long sel) { g_restart_calls++; L3 r = { (long)self, sel, 3 }; return r; }

typedef struct { int a, b; } SI2;
typedef struct { long a, b; } L2;
typedef struct { double a, b; } D2;
typedef struct { float a, b, c; } F3;
typedef struct { long a; double b; } LD;
typedef struct { double a; long b; } DL;
typedef struct { long double x; } LDS;
typedef struct { double a, b, c; } D3;

static L2 f_l2(long a, long b, L2 p, L2 q) { return (L2){ p.a + q.a + a, p.b + q.b + b }; }
static D2 f_d2(long a, long b, D2 p, double k) { return (D2){ p.a * k + a, p.b * k + b }; }
static F3 f_f3(long a, long b, F3 p) { return (F3){ p.a + 1, p.b + 2, p.c + 3 }; }
static LD f_ld(long a, long b, LD p) { return (LD){ p.a + a, p.b + 0.5 }; }
static DL f_dl(long a, long b, DL p) { return (DL){ p.a + 0.25, p.b + b }; }
static D3 f_d3(long a, long b, D3 p, long c, long d, long e, double x) { return (D3){ p.a + a, p.b + b + x, p.c + c + d + e }; }
static LDS f_lds(long a, long b, LDS p) { return (LDS){ p.x + a }; }
static long double f_ldbl(long a, long b, long double x, double y) { return x * 2 + y + a; }
static double f_dbl(long a, long b, double x, float y) { return x + y + a + b; }
static float f_flt(long a, long b, float x) { return x * 2 + a; }
static char f_chr(long a, long b, char c) { return c + 1; }
static long f_stack(long a, long b, long c, long d, long e, long f, long g, long h) { return a + b + c + d + e + f + g + h; }
static void f_void(long a, long b) { }

static int fails, total;
static void report(const char *n, int ok) { total++; if (!ok) { fails++; printf("FAIL %s\n", n); } else printf("ok   %s\n", n); }

#define SETUP(RET, ...) static const char *types_[] = { __VA_ARGS__ }; g_ret = RET; g_types = types_; g_n = sizeof(types_) / sizeof(types_[0]); g_target = NULL
int main(void)
{
    { SETUP("{L2=qq}", "{L2=qq}", "{L2=qq}"); g_fn = f_l2; L2 (*f)(long, long, L2, L2) = (void *)CF_forwarding_prep_0;
      L2 r = f(1, 2, (L2){10, 20}, (L2){100, 200}); report("fwd INTEGER pair", r.a == 111 && r.b == 222); }
    { SETUP("{D2=dd}", "{D2=dd}", "d"); g_fn = f_d2; D2 (*f)(long, long, D2, double) = (void *)CF_forwarding_prep_0;
      D2 r = f(1, 2, (D2){1.5, 2.5}, 2.0); report("fwd double pair", r.a == 4.0 && r.b == 7.0); }
    { SETUP("{F3=fff}", "{F3=fff}"); g_fn = f_f3; F3 (*f)(long, long, F3) = (void *)CF_forwarding_prep_0;
      F3 r = f(1, 2, (F3){1, 2, 3}); report("fwd float triple", r.a == 2 && r.b == 4 && r.c == 6); }
    { SETUP("{LD=qd}", "{LD=qd}"); g_fn = f_ld; LD (*f)(long, long, LD) = (void *)CF_forwarding_prep_0;
      LD r = f(5, 2, (LD){10, 1.0}); report("fwd INTEGER,SSE", r.a == 15 && r.b == 1.5); }
    { SETUP("{DL=dq}", "{DL=dq}"); g_fn = f_dl; DL (*f)(long, long, DL) = (void *)CF_forwarding_prep_0;
      DL r = f(5, 2, (DL){1.0, 10}); report("fwd SSE,INTEGER", r.a == 1.25 && r.b == 12); }
    { SETUP("{D3=ddd}", "{D3=ddd}", "q", "q", "q", "d"); g_fn = f_d3; D3 (*f)(long, long, D3, long, long, long, double) = (void *)CF_forwarding_prep_1;
      D3 r = f(1, 2, (D3){1, 2, 3}, 10, 20, 30, 0.5); report("fwd stret (24 bytes) with stack-free args", r.a == 2 && r.b == 4.5 && r.c == 63); }
    { SETUP("{LDS=D}", "{LDS=D}"); g_fn = f_lds; LDS (*f)(long, long, LDS) = (void *)CF_forwarding_prep_0;
      LDS r = f(1, 2, (LDS){2.5L}); report("fwd struct holding a long double (st0)", r.x == 3.5L); }
    { SETUP("D", "D", "d"); g_fn = f_ldbl; long double (*f)(long, long, long double, double) = (void *)CF_forwarding_prep_0;
      long double r = f(1, 2, 1.5L, 0.25); report("fwd long double", r == 4.25L); }
    { SETUP("d", "d", "f"); g_fn = f_dbl; double (*f)(long, long, double, float) = (void *)CF_forwarding_prep_0;
      double r = f(1, 2, 1.5, 0.5f); report("fwd double", r == 5.0); }
    { SETUP("f", "f"); g_fn = f_flt; float (*f)(long, long, float) = (void *)CF_forwarding_prep_0;
      float r = f(1, 2, 1.5f); report("fwd float", r == 4.0f); }
    { SETUP("c", "c"); g_fn = f_chr; char (*f)(long, long, char) = (void *)CF_forwarding_prep_0;
      char r = f(1, 2, 7); report("fwd char", r == 8); }
    { SETUP("q", "q", "q", "q", "q", "q", "q"); g_fn = f_stack; long (*f)(long, long, long, long, long, long, long, long) = (void *)CF_forwarding_prep_0;
      long r = f(1, 2, 3, 4, 5, 6, 7, 8); report("fwd stack arguments", r == 36); }
    { SETUP("v"); g_n = 0; g_fn = f_void; void (*f)(long, long) = (void *)CF_forwarding_prep_0; f(1, 2); report("fwd void", 1); }
    { SETUP("d"); g_n = 0; g_target = (void *)0x77; double (*f)(void *, long, double, long, long) = (void *)CF_forwarding_prep_0;
      double r = f((void *)0x11, 0x1234, 2.5, 40, 50); report("restart with a forwarding target (registers restored)", r == 1.0 && g_restart_calls == 1); }
    { SETUP("{L3=qqq}"); g_n = 0; g_target = (void *)0x55; L3 (*f)(L3 *, void *, long) = (void *)CF_forwarding_prep_1;
      L3 r = ((L3 (*)(void *, long))CF_forwarding_prep_1)((void *)0x11, 99); report("restart stret with a forwarding target", r.a == 0x55 && r.b == 99 && r.c == 3); }
    printf("%d/%d\n", total - fails, total);
    return fails != 0;
}
