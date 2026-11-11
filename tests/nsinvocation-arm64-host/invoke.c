// Copyright (C) 2026 Lubos Dolezel
// Host test of the arm64 argument and result placement used by NSMethodSignature and
// NSInvocation: lays out a call with run.sh's extracted copy of that code, runs it through
// the real __invoke__ trampoline, and compares with the result of a direct C call.
#include "common.h"

static void invoke(void *fn, const char *ret, const char **types, const void **vals, unsigned n, void *out)
{
    Layout l; harness_layout(&l, ret, types, n);
    long lead[2] = { 0x1111, 0x2222 };
    Frame f; frame_build(&f, &l, vals, lead);
    unsigned char *retbuf = calloc(1, 256);
    __invoke__(fn, retbuf, f.frame, l.frameLength, l.stret ? 'v' : ret[0], l.retHFA);
    memcpy(out, retbuf, l.retsize);
    free(f.frame); free(f.copies); free(retbuf);
}

static L2 f_l2(long a, long b, L2 p, L2 q) { return (L2){ p.a + q.a, p.b + q.b }; }
static D2 f_d2(long a, long b, D2 p, double k) { return (D2){ p.a * k, p.b * k }; }
static Tri f_tri(long a, long b, Tri p, Tri q) { return (Tri){ p.a + q.a + a - 0x1111, p.b + q.b + b - 0x2222, p.c + q.c }; }
static Quad f_quad(long a, long b, Quad p) { return (Quad){ p.a * 2, p.b * 2, p.c * 2, p.d * 2 }; }
static Mix f_mix(long a, long b, Mix p) { return (Mix){ p.a + 1, p.b + 1, p.c + 1, p.d + 1, p.e + 1 }; }
static LDS f_lds(long a, long b, LDS p) { return (LDS){ p.x + 1 }; }
static ArrQ f_arrq(long a, long b, ArrQ p) { return (ArrQ){ { p.v[0] + 1, p.v[1] + 1, p.v[2] + 1, p.v[3] + 1 } }; }
static ArrP f_arrp(long a, long b, ArrP p) { return (ArrP){ { p.v[0] + 1, p.v[1] + 1 } }; }
static ArrL f_arrl(long a, long b, ArrL p) { return (ArrL){ { p.v[0] + 1, p.v[1] + 1, p.v[2] + 1 } }; }
static Pent f_pent(long a, long b, Pent p) { return (Pent){ p.a + 1, p.b + 1, p.c + 1, p.d + 1, p.e + 1 }; }
static Rect f_rect(long a, long b, Rect p) { return (Rect){ { p.p.x + 1, p.p.y + 1 }, { p.s.w * 2, p.s.h * 2 } }; }
static UDL f_udl(long a, long b, UDL p) { UDL r; r.d = p.d * 2; return r; }
static Padded f_padded(long a, long b, Padded p) { return (Padded){ p.tag + 1, { p.t.a + 1, p.t.b + 1, p.t.c + 1 } }; }
static long f_tri_long(long a, long b, Tri t, long z) { return t.a + 10 * t.b + 100 * t.c + 1000 * z; }
static long f_spill(long a, long b, long c, long d, long e, long f, long g, long h, Tri t, long z) { return c + 2*d + 3*e + 4*f + 5*g + 6*h + 7*t.a + 8*t.b + 9*t.c + 10*z; }
static long f_spill_many(long a, long b, long c, long d, long e, long f, long g, Tri t, Tri u, long z) { return c + g + t.a + 10 * t.c + 100 * u.a + 1000 * u.c + 10000 * z; }
static double f_hfa_spill(long a, long b, double d1, double d2, double d3, double d4, double d5, double d6, double d7, Quad q, double z) {
    return d1 + 2*d2 + 3*d3 + 4*d4 + 5*d5 + 6*d6 + 7*d7 + 8*q.a + 9*q.b + 10*q.c + 11*q.d + 12*z; }
static double f_fp_spill_ref(long a, long b, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9, Tri t) {
    return d1 + d9 + 100 * t.a + 1000 * t.b + 10000 * t.c; }
static double f_fp_spill_d2(long a, long b, double d1, double d2, double d3, double d4, double d5, double d6, double d7, D2 p, double z) {
    return d1 + d7 + 10 * p.a + 100 * p.b + 1000 * z; }
static Tri f_stret_stack(long a, long b, long c, long d, long e, long f, long g, long h) { return (Tri){ a + c + e, g + h, 9 }; }

int main(void)
{
    {   L2 p = {1, 2}, q = {10, 20}, r; const char *t[] = { "{L2=qq}", "{L2=qq}" }; const void *v[] = { &p, &q };
        invoke(f_l2, "{L2=qq}", t, v, 2, &r); IS("16-byte struct arguments and result in x0/x1", r.a == 11 && r.b == 22); }
    {   D2 p = {1.5, 2.5}, r; double k = 2; const char *t[] = { "{D2=dd}", "d" }; const void *v[] = { &p, &k };
        invoke(f_d2, "{D2=dd}", t, v, 2, &r); IS("two doubles in d0/d1", r.a == 3.0 && r.b == 5.0); }
    {   Tri p = {1, 2, 3}, q = {10, 20, 30}, r; const char *t[] = { "{Tri=qqq}", "{Tri=qqq}" }; const void *v[] = { &p, &q };
        invoke(f_tri, "{Tri=qqq}", t, v, 2, &r); IS("24-byte struct passed by reference, result through x8", r.a == 11 && r.b == 22 && r.c == 33); }
    {   Quad p = {1, 2, 3, 4}, r; const char *t[] = { "{Quad=dddd}" }; const void *v[] = { &p };
        invoke(f_quad, "{Quad=dddd}", t, v, 1, &r); IS("32-byte HFA in d0-d3, result in d0-d3", r.a == 2 && r.b == 4 && r.c == 6 && r.d == 8); }
    {   Mix p = {1, 2.5, 3, 4.5, 5}, r; const char *t[] = { "{Mix=qdqdq}" }; const void *v[] = { &p };
        invoke(f_mix, "{Mix=qdqdq}", t, v, 1, &r); IS("40-byte mixed struct by reference and through x8", r.a == 2 && r.b == 3.5 && r.c == 4 && r.d == 5.5 && r.e == 6); }
    {   LDS p = {2.5L}, r; const char *t[] = { "{LDS=D}" }; const void *v[] = { &p };
        invoke(f_lds, "{LDS=D}", t, v, 1, &r); IS("struct with a long double is an HFA (long double is double)", r.x == 3.5L); }
    {   ArrQ p = {{1, 2, 3, 4}}, r; const char *t[] = { "{ArrQ=[4d]}" }; const void *v[] = { &p };
        invoke(f_arrq, "{ArrQ=[4d]}", t, v, 1, &r); IS("double[4] in a struct is an HFA", r.v[0] == 2 && r.v[1] == 3 && r.v[2] == 4 && r.v[3] == 5); }
    {   ArrP p = {{1, 2}}, r; const char *t[] = { "{ArrP=[2d]}" }; const void *v[] = { &p };
        invoke(f_arrp, "{ArrP=[2d]}", t, v, 1, &r); IS("double[2] in a struct is an HFA, not two integer registers", r.v[0] == 2 && r.v[1] == 3); }
    {   ArrL p = {{1, 2, 3}}, r; const char *t[] = { "{ArrL=[3q]}" }; const void *v[] = { &p };
        invoke(f_arrl, "{ArrL=[3q]}", t, v, 1, &r); IS("long[3] in a struct by reference", r.v[0] == 2 && r.v[1] == 3 && r.v[2] == 4); }
    {   Pent p = {1, 2, 3, 4, 5}, r; const char *t[] = { "{Pent=ddddd}" }; const void *v[] = { &p };
        invoke(f_pent, "{Pent=ddddd}", t, v, 1, &r); IS("five doubles are not an HFA: by reference", r.a == 2 && r.e == 6); }
    {   Rect p = {{1, 2}, {3, 4}}, r; const char *t[] = { "{Rect=\"p\"{?=\"x\"d\"y\"d}\"s\"{?=\"w\"d\"h\"d}}" }; const void *v[] = { &p };
        invoke(f_rect, t[0], t, v, 1, &r); IS("nested structs of doubles with member names are an HFA", r.p.x == 2 && r.p.y == 3 && r.s.w == 6 && r.s.h == 8); }
    {   UDL p; p.d = 2.5; UDL r; const char *t[] = { "(UDL=dq)" }; const void *v[] = { &p };
        invoke(f_udl, "(UDL=dq)", t, v, 1, &r); IS("union of double and long (8 bytes, integer register)", r.d == 5.0); }
    {   Padded p = {1, {1, 2, 3}}, r; const char *t[] = { "{Padded=c{Tri=qqq}}" }; const void *v[] = { &p };
        invoke(f_padded, t[0], t, v, 1, &r); IS("32-byte struct with padding by reference", r.tag == 2 && r.t.a == 2 && r.t.b == 3 && r.t.c == 4); }
    {   Tri p = {1, 2, 3}; long z = 7, r; const char *t[] = { "{Tri=qqq}", "q" }; const void *v[] = { &p, &z };
        invoke(f_tri_long, "q", t, v, 2, &r); IS("reference argument takes one integer register, the next long follows", r == 1 + 20 + 300 + 7000); }
    {   Tri p = {1, 2, 3}; long c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, z = 99, r;
        const char *t[] = { "q", "q", "q", "q", "q", "q", "{Tri=qqq}", "q" }; const void *v[] = { &c, &d, &e, &f, &g, &h, &p, &z };
        invoke(f_spill, "q", t, v, 8, &r); IS("reference argument as an 8-byte stack slot once x0-x7 are used", r == 3 + 8 + 15 + 24 + 35 + 48 + 7 + 16 + 27 + 990); }
    {   Tri p = {1, 2, 3}, q = {4, 5, 6}; long c = 3, d = 4, e = 5, f = 6, g = 7, z = 99, r;
        const char *t[] = { "q", "q", "q", "q", "q", "{Tri=qqq}", "{Tri=qqq}", "q" }; const void *v[] = { &c, &d, &e, &f, &g, &p, &q, &z };
        invoke(f_spill_many, "q", t, v, 8, &r); IS("one reference argument in x7, the next on the stack", r == 3 + 7 + 1 + 30 + 400 + 6000 + 990000); }
    {   Quad q = {1, 2, 3, 4}; double d[7] = {1, 2, 3, 4, 5, 6, 7}, z = 5, r; const char *t[9]; const void *v[9];
        for (int i = 0; i < 7; i++) { t[i] = "d"; v[i] = &d[i]; } t[7] = "{Quad=dddd}"; v[7] = &q; t[8] = "d"; v[8] = &z;
        invoke(f_hfa_spill, "d", t, v, 9, &r);
        IS("HFA that does not fit in the remaining d registers goes to the stack whole", r == 1 + 4 + 9 + 16 + 25 + 36 + 49 + 8 + 18 + 30 + 44 + 60); }
    {   Tri p = {1, 2, 3}; double d[9] = {1, 2, 3, 4, 5, 6, 7, 8, 9}, r; const char *t[10]; const void *v[10];
        for (int i = 0; i < 9; i++) { t[i] = "d"; v[i] = &d[i]; } t[9] = "{Tri=qqq}"; v[9] = &p;
        invoke(f_fp_spill_ref, "d", t, v, 10, &r); IS("reference argument is unaffected by exhausted d registers", r == 1 + 9 + 100 + 2000 + 30000); }
    {   D2 p = {1, 2}; double d[7] = {1, 2, 3, 4, 5, 6, 7}, z = 8, r; const char *t[9]; const void *v[9];
        for (int i = 0; i < 7; i++) { t[i] = "d"; v[i] = &d[i]; } t[7] = "{D2=dd}"; v[7] = &p; t[8] = "d"; v[8] = &z;
        invoke(f_fp_spill_d2, "d", t, v, 9, &r); IS("two-double HFA with one d register left goes to the stack", r == 1 + 7 + 10 + 200 + 8000); }
    {   long v8[8] = {1, 2, 3, 4, 5, 6, 7, 8}, c = 3; Tri r; const char *t[6]; const void *v[6];
        for (int i = 0; i < 6; i++) { t[i] = "q"; v[i] = &v8[i + 2]; }
        invoke(f_stret_stack, "{Tri=qqq}", t, v, 6, &r); IS("x8 result with stack arguments", r.a == 0x1111 + 3 + 5 && r.b == 15 && r.c == 9); }
    {   // Layout: (type, count) -> frame length; x0-x7 at 0, d0-d7 at 0x40 and stack arguments from 0x80.
        struct { const char *ret; const char *arg; unsigned count; NSUInteger frame; const char *name; } cases[] = {
            { "{Tri=qqq}", "q", 0, 128, "a result through x8 adds nothing to the frame" },
            { "v", "{Tri=qqq}", 6, 128, "six by-reference arguments fit in x2-x7" },
            { "v", "{Tri=qqq}", 7, 136, "the seventh by-reference argument takes an 8-byte stack slot" },
            { "v", "{Quad=dddd}", 2, 128, "two four-double HFAs fit in d0-d7" },
            { "v", "{Quad=dddd}", 3, 160, "the third four-double HFA goes to the stack" },
            { "v", "{Mix=qdqdq}", 8, 144, "40-byte structs by reference, two in stack slots" },
        };
        for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
            const char *t[16]; for (unsigned k = 0; k < cases[i].count; k++) t[k] = cases[i].arg;
            Layout l; harness_layout(&l, cases[i].ret, t, cases[i].count);
            report(cases[i].name, l.frameLength == cases[i].frame);
        }
    }
    {   IS("double HFA count: double[4] member", __NSARM64DoubleHFACount("{A=[4d]}") == 4);
        IS("double HFA count: array of five is not an HFA", __NSARM64DoubleHFACount("{A=[5d]}") == 0);
        IS("double HFA count: mixed float and double is not one", __NSARM64DoubleHFACount("{A=fd}") == 0);
        IS("double HFA count: integer member is not one", __NSARM64DoubleHFACount("{A=dq}") == 0);
        IS("double HFA count: nested arrays", __NSARM64DoubleHFACount("{A=[2[2d]]}") == 4);
        IS("double HFA count: empty struct", __NSARM64DoubleHFACount("{A=}") == 0);
        IS("by reference: 16 bytes is not, 17 is", !__NSARM64PassedByReference("{A=qq}", 16) && __NSARM64PassedByReference("{A=qqc}", 24));
        IS("by reference: scalars never are", !__NSARM64PassedByReference("q", 8) && !__NSARM64PassedByReference("d", 8)); }
    printf("%d/%d\n", total - fails, total);
    return fails != 0;
}
