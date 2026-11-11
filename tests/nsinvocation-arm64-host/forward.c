// Copyright (C) 2026 Lubos Dolezel
// Host test of the arm64 forwarding trampoline (__CF_forwarding_prep_0): calls it as if it
// were a method the runtime could not find, with a stand-in for ____forwarding___ that decodes
// the saved registers the way NSForwarding.m does (dereferencing by-reference structs),
// invokes the real implementation through __invoke__ and returns its result.
#include "common.h"
void _CF_forwarding_prep_0(void);

static const char *g_ret; static const char **g_types; static unsigned g_n; static void *g_fn;
static void *g_target;

void *forwarding_stub(void *args, void *storage, void *indirect)
{
    unsigned char *block = args;
    if (g_target) { return g_target; }
    Layout l; harness_layout(&l, g_ret, g_types, g_n);
    unsigned char *tmp[16]; const void *vals[16];
    for (unsigned i = 0; i < g_n; i++) {
        // A struct passed by reference: the saved slot holds the address of the caller's copy.
        vals[i] = l.byref[i] ? *(void **)(block + l.offset[i]) : block + l.offset[i];
    }
    Frame f; frame_build(&f, &l, vals, (long[]){ *(long *)block, *(long *)(block + 8) });
    unsigned char *retbuf = calloc(1, 256);
    __invoke__(g_fn, retbuf, f.frame, l.frameLength, l.stret ? 'v' : g_ret[0], l.retHFA);
    if (l.stret) memcpy(indirect, retbuf, l.retsize); else memcpy(storage, retbuf, 32);
    free(f.frame); free(f.copies); free(retbuf);
    return NULL;
}

long objc_msgSend(void *self, long sel, double d, long c) { return (self == (void *)0x77 && sel == 0x1234 && d == 2.5 && c == 40) ? 1 : -1; }

static L2 f_l2(long a, long b, L2 p, L2 q) { return (L2){ p.a + q.a + a, p.b + q.b + b }; }
static Tri f_tri(long a, long b, Tri p, Tri q) { return (Tri){ p.a + q.a + a, p.b + q.b + b, p.c + q.c }; }
static Quad f_quad(long a, long b, Quad p) { return (Quad){ p.a * 2 + a, p.b * 2, p.c * 2, p.d * 2 }; }
static Mix f_mix(long a, long b, Mix p) { return (Mix){ p.a + 1, p.b + 1, p.c + 1, p.d + 1, p.e + 1 }; }
static LDS f_lds(long a, long b, LDS p) { return (LDS){ p.x + a }; }
static ArrQ f_arrq(long a, long b, ArrQ p) { return (ArrQ){ { p.v[0] + 1, p.v[1] + 1, p.v[2] + 1, p.v[3] + 1 } }; }
static ArrP f_arrp(long a, long b, ArrP p) { return (ArrP){ { p.v[0] + 1, p.v[1] + 1 } }; }
static Pent f_pent(long a, long b, Pent p) { return (Pent){ p.a + 1, p.b + 1, p.c + 1, p.d + 1, p.e + 1 }; }
static long f_tri_long(long a, long b, Tri t, long z) { return t.a + 10 * t.b + 100 * t.c + 1000 * z; }
static long f_spill(long a, long b, long c, long d, long e, long f, long g, long h, Tri t, long z) { return c + 2*d + 3*e + 4*f + 5*g + 6*h + 7*t.a + 8*t.b + 9*t.c + 10*z; }
static double f_hfa_spill(long a, long b, double d1, double d2, double d3, double d4, double d5, double d6, double d7, Quad q, double z) {
    return d1 + 2*d2 + 3*d3 + 4*d4 + 5*d5 + 6*d6 + 7*d7 + 8*q.a + 9*q.b + 10*q.c + 11*q.d + 12*z; }
static double f_fp_spill_ref(long a, long b, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9, Tri t) {
    return d1 + d9 + 100 * t.a + 1000 * t.b + 10000 * t.c; }

#define SETUP(fn, ret, ...) do { static const char *tt[] = { __VA_ARGS__ }; g_fn = (void *)fn; g_ret = ret; g_types = tt; g_n = sizeof(tt) / sizeof(tt[0]); g_target = NULL; } while (0)

int main(void)
{
    { SETUP(f_l2, "{L2=qq}", "{L2=qq}", "{L2=qq}");
      L2 r = ((L2 (*)(long, long, L2, L2))_CF_forwarding_prep_0)(5, 6, (L2){1, 2}, (L2){10, 20});
      IS("forwarding: 16-byte structs in x2-x5", r.a == 16 && r.b == 28); }
    { SETUP(f_tri, "{Tri=qqq}", "{Tri=qqq}", "{Tri=qqq}");
      Tri r = ((Tri (*)(long, long, Tri, Tri))_CF_forwarding_prep_0)(5, 6, (Tri){1, 2, 3}, (Tri){10, 20, 30});
      IS("forwarding: 24-byte structs by reference, result through x8", r.a == 16 && r.b == 28 && r.c == 33); }
    { SETUP(f_quad, "{Quad=dddd}", "{Quad=dddd}");
      Quad r = ((Quad (*)(long, long, Quad))_CF_forwarding_prep_0)(5, 6, (Quad){1, 2, 3, 4});
      IS("forwarding: four-double HFA argument and result", r.a == 7 && r.b == 4 && r.c == 6 && r.d == 8); }
    { SETUP(f_mix, "{Mix=qdqdq}", "{Mix=qdqdq}");
      Mix r = ((Mix (*)(long, long, Mix))_CF_forwarding_prep_0)(5, 6, (Mix){1, 2.5, 3, 4.5, 5});
      IS("forwarding: 40-byte mixed struct", r.a == 2 && r.b == 3.5 && r.c == 4 && r.d == 5.5 && r.e == 6); }
    { SETUP(f_lds, "{LDS=D}", "{LDS=D}");
      LDS r = ((LDS (*)(long, long, LDS))_CF_forwarding_prep_0)(5, 6, (LDS){2.5L});
      IS("forwarding: struct with long double", r.x == 7.5L); }
    { SETUP(f_arrq, "{ArrQ=[4d]}", "{ArrQ=[4d]}");
      ArrQ r = ((ArrQ (*)(long, long, ArrQ))_CF_forwarding_prep_0)(5, 6, (ArrQ){{1, 2, 3, 4}});
      IS("forwarding: double[4] in a struct", r.v[0] == 2 && r.v[3] == 5); }
    { SETUP(f_arrp, "{ArrP=[2d]}", "{ArrP=[2d]}");
      ArrP r = ((ArrP (*)(long, long, ArrP))_CF_forwarding_prep_0)(5, 6, (ArrP){{1, 2}});
      IS("forwarding: double[2] in a struct", r.v[0] == 2 && r.v[1] == 3); }
    { SETUP(f_pent, "{Pent=ddddd}", "{Pent=ddddd}");
      Pent r = ((Pent (*)(long, long, Pent))_CF_forwarding_prep_0)(5, 6, (Pent){1, 2, 3, 4, 5});
      IS("forwarding: five doubles", r.a == 2 && r.e == 6); }
    { SETUP(f_tri_long, "q", "{Tri=qqq}", "q");
      long r = ((long (*)(long, long, Tri, long))_CF_forwarding_prep_0)(5, 6, (Tri){1, 2, 3}, 7);
      IS("forwarding: reference argument then long", r == 1 + 20 + 300 + 7000); }
    { SETUP(f_spill, "q", "q", "q", "q", "q", "q", "q", "{Tri=qqq}", "q");
      long r = ((long (*)(long, long, long, long, long, long, long, long, Tri, long))_CF_forwarding_prep_0)(1, 2, 3, 4, 5, 6, 7, 8, (Tri){1, 2, 3}, 99);
      IS("forwarding: reference argument in a stack slot", r == 3 + 8 + 15 + 24 + 35 + 48 + 7 + 16 + 27 + 990); }
    { SETUP(f_hfa_spill, "d", "d", "d", "d", "d", "d", "d", "d", "{Quad=dddd}", "d");
      double r = ((double (*)(long, long, double, double, double, double, double, double, double, Quad, double))_CF_forwarding_prep_0)(1, 2, 1, 2, 3, 4, 5, 6, 7, (Quad){1, 2, 3, 4}, 5);
      IS("forwarding: HFA on the stack", r == 1 + 4 + 9 + 16 + 25 + 36 + 49 + 8 + 18 + 30 + 44 + 60); }
    { SETUP(f_fp_spill_ref, "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "{Tri=qqq}");
      double r = ((double (*)(long, long, double, double, double, double, double, double, double, double, double, Tri))_CF_forwarding_prep_0)(1, 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, (Tri){1, 2, 3});
      IS("forwarding: reference argument with d registers exhausted", r == 1 + 9 + 100 + 2000 + 30000); }
    { g_target = (void *)0x77;
      long r = ((long (*)(void *, long, double, long))_CF_forwarding_prep_0)((void *)0x55, 0x1234, 2.5, 40);
      g_target = NULL; IS("forwarding: restart with the new target keeps the other arguments", r == 1); }
    printf("%d/%d\n", total - fails, total);
    return fails != 0;
}
