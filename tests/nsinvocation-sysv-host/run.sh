#!/bin/sh
# Copyright (C) 2026 Lubos Dolezel
# Builds and runs the x86_64 System V ABI host tests (invoke.c, forward.c), and the i386 ones
# (invoke32.c, forward32.c) when 32-bit code can be built, on a Linux x86_64 host.
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
def between(text, start, end):
    a = text.index(start) + len(start)
    return text[a:text.index(end, a)]
extend = between(ms, '// The arm64, x86_64 and i386 ABIs', '#if defined(__x86_64__)\n// System V AMD64')
extend = '// The arm64, x86_64 and i386 ABIs' + extend
classify = between(ms, '#if defined(__x86_64__)\n// System V AMD64', '#endif\n\n#if defined(__i386__)')
classify = '// System V AMD64' + classify
i386 = between(ms, '#if defined(__i386__)\n// i386 (Darwin) results', '#endif\n\n@implementation NSMethodSignature')
i386 = '// i386 (Darwin) results' + i386
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
harness32 = '''
typedef struct { size_t offset[16]; NSUInteger size[16]; unsigned count; NSUInteger frameLength; int stret; NSUInteger retsize; } Layout;
// Lays out a call the way initWithObjCTypes: does on i386; two words stand in for self and _cmd.
void harness_layout(Layout *l, const char *ret, const char **args, unsigned n)
{
    l->frameLength = 0;
    NSUInteger sz = 0, al = 0;
    __NSGetSizeAndAlignment(ret, &sz, &al, NO);
    l->retsize = sz;
    l->stret = __NSI386ResultInMemory(ret, sz);
    if (l->stret) l->frameLength += 4;
    l->frameLength += 8;
    l->count = n;
    for (unsigned i = 0; i < n; i++) {
        NSUInteger s = 0, a = 0;
        __NSGetSizeAndAlignment(args[i], &s, &a, NO);
        NSUInteger fa = MAX(a, sizeof(int));
        NSUInteger fs = ALIGN_TO(s, fa);
        l->offset[i] = l->frameLength;
        l->size[i] = s;
        l->frameLength += fs;
    }
}
'''
open(out + 'lib.c', 'w').write(pre + gs + extend + classify + harness)
open(out + 'lib32.c', 'w').write(pre + gs + extend + i386 + harness32)
asm = open(src + 'NSInvoke-x86.S').read()
body = asm[asm.index('#elif defined(__x86_64__)') + len('#elif defined(__x86_64__) // Now the x86-64 version'):asm.index('#elif defined(__arm64__)')]
body = body.replace('.cfi_personality 155, ___objc_personality_v0', '')
open(out + 'inv.S', 'w').write('.text\n.globl ___invoke__\n.align 4\n___invoke__:\n' + body)
body32 = asm[asm.index('#ifdef __i386__') + len('#ifdef __i386__'):asm.index('#elif defined(__x86_64__)')]
open(out + 'inv32.S', 'w').write('.text\n.globl ___invoke__\n.align 4\n___invoke__:\n' + body32)
prep = open(src + 'CFForwardingPrep.S').read()
body = prep[prep.index('#elif __x86_64__') + len('#elif __x86_64__'):prep.index('.globl __CF_forwarding_prep_b\n.align 4, 0x90\n\n__CF_forwarding_prep_b:\n    .cfi_startproc')]
body = body.replace('.section __TEXT,__text,regular,pure_instructions', '.text').replace('.cfi_personality 155, ___objc_personality_v0', '')
body = body.replace('_objc_msgSend_stret', 'objc_msgSend_stret').replace('_objc_msgSend', 'objc_msgSend').replace('____forwarding___', 'forwarding_stub')
body = body.replace('__CF_forwarding_prep_', 'CF_forwarding_prep_')
open(out + 'prep.S', 'w').write(body)
body32 = prep[prep.index('#elif __i386__') + len('#elif __i386__'):prep.index('.text\n.global  __CF_forwarding_prep_b')]
body32 = body32.replace('_objc_msgSend_stret', 'objc_msgSend_stret').replace('_objc_msgSend', 'objc_msgSend').replace('____forwarding___', 'forwarding_stub')
body32 = body32.replace('__CF_forwarding_prep_', 'CF_forwarding_prep_')
open(out + 'prep32.S', 'w').write(body32)
PY
cd "$out"
clang -w -c lib.c -o lib.o
clang -w -c -x assembler-with-cpp inv.S -o inv.o
clang -w -c -x assembler-with-cpp prep.S -o prep.o
clang -w -O0 -o invoke "$here/invoke.c" lib.o inv.o
clang -w -O0 -no-pie -o forward "$here/forward.c" lib.o inv.o prep.o
./invoke
./forward
# i386, when the host can build 32-bit programs (return small structs in registers as Darwin does)
if echo 'int main(void){return 0;}' | clang -m32 -x c - -o m32probe 2>/dev/null; then
    clang -m32 -w -c lib32.c -o lib32.o
    clang -m32 -w -c -x assembler-with-cpp inv32.S -o inv32.o
    clang -m32 -w -c -x assembler-with-cpp prep32.S -o prep32.o
    clang -m32 -w -O0 -freg-struct-return -o invoke32 "$here/invoke32.c" lib32.o inv32.o
    clang -m32 -w -O0 -freg-struct-return -no-pie -o forward32 "$here/forward32.c" lib32.o inv32.o prep32.o
    ./invoke32
    ./forward32
else
    echo "no 32-bit toolchain: skipping the i386 tests"
fi
