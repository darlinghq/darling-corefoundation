// Copyright (C) 2026 Lubos Dolezel
// Shared pieces of the arm64 host tests: layout and frame building as -[NSInvocation invoke]
// does it, on top of the helpers extracted into lib.c by run.sh.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned long NSUInteger; typedef int BOOL;
typedef struct { size_t offset[16]; NSUInteger size[16]; int byref[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; unsigned retHFA; } Layout;
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n);
void __invoke__(void *send, void *retdata, void *args, size_t len, char rettype, unsigned hfa);
unsigned __NSARM64DoubleHFACount(const char *type);
int __NSARM64PassedByReference(const char *type, NSUInteger size);

static int fails, total;
static void report(const char *name, int ok) { total++; if (!ok) { fails++; printf("FAIL %s\n", name); } else printf("ok   %s\n", name); }
#define IS(name, cond) report(name, cond)

typedef struct { long a, b; } L2;
typedef struct { double a, b; } D2;
typedef struct { long a, b, c; } Tri;
typedef struct { double a, b, c, d; } Quad;
typedef struct { long a; double b; long c; double d; long e; } Mix;
typedef struct { long double x; } LDS;
typedef struct { double v[4]; } ArrQ;
typedef struct { double v[2]; } ArrP;
typedef struct { long v[3]; } ArrL;
typedef struct { double a, b, c, d, e; } Pent;
typedef struct { struct { double x, y; } p; struct { double w, h; } s; } Rect;   // nested, four doubles
typedef union { double d; long l; } UDL;
typedef struct { char tag; Tri t; } Padded;                                       // 32 bytes with padding

// The frame as __invoke__ receives it: register area, stack area, and caller-made copies of
// by-reference structs (kept in copies, which the caller owns).
typedef struct { unsigned char *frame; unsigned char *copies; Layout l; } Frame;

static void frame_build(Frame *f, const Layout *l, const void **vals, const long *lead)
{
    f->l = *l;
    f->frame = calloc(1, l->frameLength + 64);
    f->copies = calloc(1, 16 * 64);
    memcpy(f->frame, lead, 16);   // self and _cmd stand-ins in x0, x1
    for (unsigned i = 0; i < l->count; i++) {
        if (l->byref[i]) {
            void *copy = f->copies + i * 64;
            memcpy(copy, vals[i], l->size[i]);
            *(void **)(f->frame + l->offset[i]) = copy;
        } else {
            memcpy(f->frame + l->offset[i], vals[i], l->size[i]);
        }
    }
}
