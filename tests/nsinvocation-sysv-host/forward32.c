// Copyright (C) 2026 Lubos Dolezel
// Host test of the i386 forwarding trampolines (__CF_forwarding_prep_0/_1): calls them as if they
// were methods the runtime could not find, with a stand-in for ____forwarding___ that decodes the
// saved frame, invokes the real implementation and hands back its result the way NSForwarding.m
// does (eax:edx, an x87 value and flag word, or the hidden pointer).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned long NSUInteger; typedef int BOOL;
typedef struct { size_t offset[16]; NSUInteger size[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; } Layout;
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n);
void ___invoke__(void *send, void *retdata, void *args, size_t len, char rettype, unsigned hfa);
char __NSI386X87ResultType(const char *type);
void __NSExtendNarrowInteger(void *value, const char *type);
void CF_forwarding_prep_0(void);
void CF_forwarding_prep_1(void);

static const char *g_ret; static const char **g_types; static unsigned g_n; static void *g_fn; static void *g_target;
static int g_restart_calls;

void *forwarding_stub(uintptr_t *args, void *storage, void *indirect)
{
    if (g_target) { return g_target; }
    Layout l; harness_layout(&l, g_ret, g_types, g_n);
    unsigned selfIndex = indirect != NULL ? 1 : 0;
    // The hidden pointer, when there is one, is the first word of the frame, as in NSMethodSignature.
    if ((l.stret != 0) != (indirect != NULL)) { printf("FAIL stret entry does not match the signature\n"); exit(1); }
    (void)selfIndex;
    unsigned char *frame = calloc(1, l.frameLength + 64);
    memcpy(frame, args, l.frameLength);
    unsigned char *retbuf = calloc(1, 256);
    unsigned char scratch[80];
    if (l.stret) { memcpy(frame, &(void *){ retbuf }, 4); }
    char x87 = __NSI386X87ResultType(g_ret);
    ___invoke__(g_fn, l.stret ? (void *)scratch : (void *)retbuf, frame, l.frameLength, x87 ? x87 : g_ret[0], 0);
    if (l.stret) {
        memcpy(indirect, retbuf, l.retsize);
    } else {
        unsigned char *st = storage;
        memcpy(st, retbuf, l.retsize);
        __NSExtendNarrowInteger(st, g_ret);
        *(uint32_t *)(st + 32) = x87 == 'f' ? 1 : x87 == 'd' ? 2 : x87 == 'D' ? 3 : 0;
    }
    free(frame); free(retbuf);
    return NULL;
}

double objc_msgSend(void *self, void *sel, double d, int c) { g_restart_calls++; return (self == (void *)0x77 && sel == (void *)0x1234 && d == 2.5 && c == 40) ? 1.0 : -1.0; }
typedef struct { int a, b, c; } I3;
I3 objc_msgSend_stret(void *self, void *sel) { g_restart_calls++; return (I3){ (int)(intptr_t)self, (int)(intptr_t)sel, 3 }; }

typedef struct { int a, b; } Ints2;
typedef struct { char a, b, c; } C3;
typedef struct { double a, b; } D2;
typedef struct { float f; } F1;

static float f_float(void *a, void *b, float x) { return x * 2; }
static double f_double(void *a, void *b, double x) { return x * 2; }
static long double f_ldbl(void *a, void *b, long double x) { return x + 1; }
static long long f_q(void *a, void *b, long long x) { return x * 2; }
static char f_chr(void *a, void *b, char c) { return c - 5; }
static short f_short(void *a, void *b, short c) { return c - 5; }
static Ints2 f_ints2(void *a, void *b, Ints2 p) { return (Ints2){ p.b, p.a }; }
static C3 f_c3(void *a, void *b, C3 p) { return (C3){ p.a + 1, p.b + 1, p.c + 1 }; }
static D2 f_d2(void *a, void *b, D2 p, int k) { return (D2){ p.a + k, p.b + k }; }
static F1 f_f1(void *a, void *b, F1 p) { return (F1){ p.f * 3 }; }
static int f_stack(void *a, void *b, int c, int d, int e, int f, int g) { return c + d + e + f + g; }
static void f_void(void *a, void *b) { }

static int fails, total;
static void report(const char *n, int ok) { total++; if (!ok) { fails++; printf("FAIL %s\n", n); } else printf("ok   %s\n", n); }
#define SETUP(RET, ...) static const char *types_[] = { __VA_ARGS__ }; g_ret = RET; g_types = types_; g_n = sizeof(types_) / sizeof(types_[0]); g_target = NULL

int main(void)
{
    { SETUP("f", "f"); g_fn = f_float; float (*f)(void *, void *, float) = (void *)CF_forwarding_prep_0;
      float r = f(0, 0, 1.5f); report("fwd float in st(0)", r == 3.0f); }
    { SETUP("d", "d"); g_fn = f_double; double (*f)(void *, void *, double) = (void *)CF_forwarding_prep_0;
      double r = f(0, 0, 1.5); report("fwd double in st(0)", r == 3.0); }
    { SETUP("D", "D"); g_fn = f_ldbl; long double (*f)(void *, void *, long double) = (void *)CF_forwarding_prep_0;
      long double r = f(0, 0, 1.5L); report("fwd long double in st(0)", r == 2.5L); }
    { SETUP("q", "q"); g_fn = f_q; long long (*f)(void *, void *, long long) = (void *)CF_forwarding_prep_0;
      long long r = f(0, 0, 1LL << 40); report("fwd 64-bit integer", r == 1LL << 41); }
    { SETUP("c", "c"); g_fn = f_chr; char (*f)(void *, void *, char) = (void *)CF_forwarding_prep_0;
      char r = f(0, 0, 1); report("fwd signed char result", r == -4); }
    { SETUP("s", "s"); g_fn = f_short; short (*f)(void *, void *, short) = (void *)CF_forwarding_prep_0;
      short r = f(0, 0, 1); report("fwd short result", r == -4); }
    { SETUP("{Ints2=ii}", "{Ints2=ii}"); g_fn = f_ints2; Ints2 (*f)(void *, void *, Ints2) = (void *)CF_forwarding_prep_0;
      Ints2 r = f(0, 0, (Ints2){ 1, 2 }); report("fwd 8-byte struct in eax:edx", r.a == 2 && r.b == 1); }
    { SETUP("{F1=f}", "{F1=f}"); g_fn = f_f1; F1 (*f)(void *, void *, F1) = (void *)CF_forwarding_prep_0;
      F1 r = f(0, 0, (F1){ 1.5f }); report("fwd single-float struct in st(0)", r.f == 4.5f); }
    { SETUP("{C3=ccc}", "{C3=ccc}"); g_fn = f_c3; C3 (*f)(void *, void *, C3) = (void *)CF_forwarding_prep_1;
      C3 r = f(0, 0, (C3){ 1, 2, 3 }); report("fwd 3-byte struct through the hidden pointer (frame includes it)", r.a == 2 && r.b == 3 && r.c == 4); }
    { SETUP("{D2=dd}", "{D2=dd}", "i"); g_fn = f_d2; D2 (*f)(void *, void *, D2, int) = (void *)CF_forwarding_prep_1;
      D2 r = f(0, 0, (D2){ 1, 2 }, 10); report("fwd 16-byte struct through the hidden pointer", r.a == 11 && r.b == 12); }
    { SETUP("i", "i", "i", "i", "i", "i"); g_fn = f_stack; int (*f)(void *, void *, int, int, int, int, int) = (void *)CF_forwarding_prep_0;
      int r = f(0, 0, 1, 2, 3, 4, 5); report("fwd stack arguments", r == 15); }
    { SETUP("v"); g_n = 0; g_fn = f_void; void (*f)(void *, void *) = (void *)CF_forwarding_prep_0; f(0, 0); report("fwd void", 1); }
    { SETUP("d"); g_n = 0; g_target = (void *)0x77; double (*f)(void *, void *, double, int) = (void *)CF_forwarding_prep_0;
      double r = f((void *)0x11, (void *)0x1234, 2.5, 40); report("restart with a forwarding target", r == 1.0 && g_restart_calls == 1); }
    { SETUP("{I3=iii}"); g_n = 0; g_target = (void *)0x55;
      I3 r = ((I3 (*)(void *, void *))CF_forwarding_prep_1)((void *)0x11, (void *)99); report("restart stret with a forwarding target", r.a == 0x55 && r.b == 99 && r.c == 3); }
    printf("%d/%d\n", total - fails, total);
    return fails != 0;
}
