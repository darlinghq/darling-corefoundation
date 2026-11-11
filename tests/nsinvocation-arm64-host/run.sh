#!/bin/sh
# Copyright (C) 2026 Lubos Dolezel
# Builds and runs the arm64 host tests (invoke.c, forward.c) natively on an arm64 Darwin host
# (a Mac). The code under test is extracted from the CoreFoundation sources at build time:
# the argument classification and placement helpers from NSMethodSignature.m,
# __NSGetSizeAndAlignment from NSObjCRuntime.m, and the arm64 parts of NSInvoke-x86.S and
# CFForwardingPrep.S.
# Usage: run.sh [scratch-dir]   (needs clang and python3)
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../.." && pwd)
out=${1:-$(mktemp -d)}
mkdir -p "$out"
python3 - "$src" "$out" <<'PY'
import sys
src, out = sys.argv[1] + '/', sys.argv[2] + '/'
ms = open(src + 'NSMethodSignature.m').read()
start = ms.index('#if defined(__arm64__)\n// Flattens')
end = ms.index('#endif\n\n// The arm64, x86_64 and i386 ABIs')
helpers = ms[start + len('#if defined(__arm64__)\n'):end]
rt = open(src + 'NSObjCRuntime.m').read()
gs = rt[rt.index('const char *__NSGetSizeAndAlignment('):rt.index('const char *NSGetSizeAndAlignment(')]
gs = gs.replace('@throw [NSException exceptionWithName:NSInvalidArgumentException reason:nil userInfo:nil];', 'abort();')
consts = {'CHR': 'c', 'SHT': 's', 'INT': 'i', 'LNG': 'l', 'LNG_LNG': 'q', 'UCHR': 'C', 'USHT': 'S', 'UINT': 'I',
          'ULNG': 'L', 'ULNG_LNG': 'Q', 'BOOL': 'B', 'FLT': 'f', 'DBL': 'd', 'LNG_DBL': 'D', 'VOID': 'v',
          'CHARPTR': '*', 'ID': '@', 'CLASS': '#', 'SEL': ':', 'PTR': '^', 'UNDEF': '?', 'ARY_B': '[',
          'ARY_E': ']', 'STRUCT_B': '{', 'STRUCT_E': '}', 'UNION_B': '(', 'UNION_E': ')', 'BFLD': 'b'}
pre = '''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned long NSUInteger; typedef int BOOL; typedef void *Class; typedef void *SEL; typedef void *id;
#define YES 1
#define NO 0
#define MAX(a,b) ((a)>(b)?(a):(b))
#define MIN(a,b) ((a)<(b)?(a):(b))
#define ALIGN_TO(value, alignment) (((value) % (alignment)) ? ((value) + (alignment) - ((value) % (alignment))) : (value))
'''
for k, v in consts.items():
    pre += "#define _C_%s '%s'\n" % (k, v)
pre += '''static inline const char *stripQualifiersAndComments(const char *decl)
{
    static const char *q = "nNoOrRV\\"";
    while (*decl != 0 && strchr(q, *decl)) { if (*decl == '"') { decl++; while (*decl++ != '"'); } else decl++; }
    return decl;
}
const char *__NSGetSizeAndAlignment(const char *decl, NSUInteger *size, NSUInteger *alignment, BOOL stripSizeHints);
'''
harness = '''
typedef struct { size_t offset[16]; NSUInteger size[16]; int byref[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; unsigned retHFA; } Layout;
// Lays out a call the way initWithObjCTypes: does; two integer registers stand in for self and _cmd.
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n)
{
    unsigned short gp = 2, fp = 0; l->frameLength = 0x80;
    NSUInteger sz = 0, al = 0;
    __NSGetSizeAndAlignment(ret, &sz, &al, NO);
    l->retsize = sz;
    l->stret = __NSARM64PassedByReference(ret, sz);
    l->retHFA = __NSARM64DoubleHFACount(ret);
    l->count = n;
    for (unsigned i = 0; i < n; i++) {
        NSUInteger s = 0, a = 0;
        __NSGetSizeAndAlignment(args[i], &s, &a, NO);
        l->offset[i] = __NSARM64PlaceArgument(args[i], s, a, &gp, &fp, &l->frameLength);
        l->size[i] = s;
        l->byref[i] = __NSARM64PassedByReference(args[i], s);
    }
    l->frameLength = ALIGN_TO(l->frameLength, 8);
}
'''
open(out + 'lib.c', 'w').write(pre + gs + helpers + harness)
asm = open(src + 'NSInvoke-x86.S').read()
body = asm[asm.index('#elif defined(__arm64__) || defined(__aarch64__)') + len('#elif defined(__arm64__) || defined(__aarch64__)'):asm.index('#else\n#error Unsupported architecture')]
open(out + 'inv.S', 'w').write('.text\n.globl ___invoke__\n.p2align 2\n___invoke__:\n' + body)
prep = open(src + 'CFForwardingPrep.S').read()
first = prep.index('#elif defined(__arm64__) || defined(__aarch64__)')
body = prep[first + len('#elif defined(__arm64__) || defined(__aarch64__)'):prep.index('.globl __CF_forwarding_prep_b', first)]
body = body.replace('____forwarding___', '_forwarding_stub').replace('.section __TEXT,__text,regular,pure_instructions', '.text')
open(out + 'prep.S', 'w').write(body)
PY
cd "$out"
clang -w -c lib.c -o lib.o
clang -w -c -x assembler-with-cpp inv.S -o inv.o
clang -w -c -x assembler-with-cpp prep.S -o prep.o
clang -w -O0 -o invoke "$here/invoke.c" lib.o inv.o
clang -w -O0 -o forward "$here/forward.c" lib.o inv.o prep.o
./invoke
./forward
