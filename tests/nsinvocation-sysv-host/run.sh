#!/bin/sh
# Copyright (C) 2026 Lubos Dolezel
# Builds and runs the x86_64 System V ABI host tests (invoke.c, forward.c) on a Linux x86_64 host.
# The code under test is extracted from the CoreFoundation sources at build time:
# the classification helpers from NSMethodSignature.m, __NSGetSizeAndAlignment from
# NSObjCRuntime.m, and the x86_64 parts of NSInvoke-x86.S and CFForwardingPrep.S.
# Usage: run.sh [scratch-dir]   (run from anywhere; needs clang and python3)
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../.." && pwd)
out=${1:-$(mktemp -d)}
mkdir -p "$out"
python3 - "$src" "$out" <<'PY'
import sys
src, out = sys.argv[1] + '/', sys.argv[2] + '/'
ms = open(src + 'NSMethodSignature.m').read()
a = ms.index('#if defined(__x86_64__)\n// System V AMD64')
b = ms.index('#endif\n\n@implementation NSMethodSignature')
classify = ms[a + len('#if defined(__x86_64__)\n'):b]
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
#define SYSV_SSE_AREA 0x30
#define SYSV_RETURN_REGS_SIZE 64
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
typedef struct { size_t offset[16]; NSUInteger size[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; } Layout;
// Lays out a call the way initWithObjCTypes: does; two integer registers stand in for self and _cmd.
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n)
{
    unsigned gp = 0, sse = 0; l->frameLength = 0xe0; l->stret = 0;
    NSUInteger sz = 0, al = 0;
    __NSGetSizeAndAlignment(ret, &sz, &al, NO);
    l->retsize = sz;
    SysVClassification rc = sysvClassify(ret, sz);
    if (rc.memory && !rc.x87) { l->stret = 1; gp++; }
    gp += 2;
    l->count = n;
    for (unsigned i = 0; i < n; i++) {
        NSUInteger s = 0, a = 0;
        __NSGetSizeAndAlignment(args[i], &s, &a, NO);
        SysVClassification c = sysvClassify(args[i], s);
        l->offset[i] = sysvPlaceArgument(&c, s, a, &gp, &sse, &l->frameLength);
        l->size[i] = s;
    }
}
'''
open(out + 'lib.c', 'w').write(pre + gs + classify + harness)
asm = open(src + 'NSInvoke-x86.S').read()
body = asm[asm.index('#elif defined(__x86_64__)') + len('#elif defined(__x86_64__) // Now the x86-64 version'):asm.index('#elif defined(__arm64__)')]
body = body.replace('.cfi_personality 155, ___objc_personality_v0', '')
open(out + 'inv.S', 'w').write('.text\n.globl ___invoke__\n.align 4\n___invoke__:\n' + body)
prep = open(src + 'CFForwardingPrep.S').read()
body = prep[prep.index('#elif __x86_64__') + len('#elif __x86_64__'):prep.index('.globl __CF_forwarding_prep_b\n.align 4, 0x90\n\n__CF_forwarding_prep_b:\n    .cfi_startproc')]
body = body.replace('.section __TEXT,__text,regular,pure_instructions', '.text').replace('.cfi_personality 155, ___objc_personality_v0', '')
body = body.replace('_objc_msgSend_stret', 'objc_msgSend_stret').replace('_objc_msgSend', 'objc_msgSend').replace('____forwarding___', 'forwarding_stub')
body = body.replace('__CF_forwarding_prep_', 'CF_forwarding_prep_')
open(out + 'prep.S', 'w').write(body)
PY
cd "$out"
clang -w -c lib.c -o lib.o
clang -w -c -x assembler-with-cpp inv.S -o inv.o
clang -w -c -x assembler-with-cpp prep.S -o prep.o
clang -w -O0 -o invoke "$here/invoke.c" lib.o inv.o
clang -w -O0 -no-pie -o forward "$here/forward.c" lib.o inv.o prep.o
./invoke
./forward
