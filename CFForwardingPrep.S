/**************************************
 * The marg_list's layout is:
 * d0   <-- args
 * d1
 * d2   |  increasing address
 * d3   v
 * d4
 * d5
 * d6
 * d7
 * a1
 * a2
 * a3
 * a4
 * stack args...
 * 
 * typedef struct objc_sendv_margs {
 *    int  a[4];
 *    int  stackArgs[...];
 * };
 *
 **************************************/
#if __arm__

#include <arm/arch.h>

#if defined(__DYNAMIC__)
#define MI_EXTERN(var) \
    .non_lazy_symbol_pointer                        ;\
L ## var ## __non_lazy_ptr:                         ;\
    .indirect_symbol var                            ;\
    .long 0
#else
#define MI_EXTERN(var) \
    .globl var
#endif

MI_EXTERN(___forwarding___)

.globl __CF_forwarding_prep_0
.align 2
.fnstart

__CF_forwarding_prep_0:      // top of stack is used as marg_list
    stmfd sp!, {r0-r3}      // push args to marg_list
    stmfd sp!, {fp, lr}     // setup stack frame: sp -= 8, marg_list @ sp+8
    .save {fp, lr}
    .setfp fp, sp, #4
    add fp, sp, #4
    .pad #8
    sub sp, sp, #8          // pad the stack: sp -= 8, marg_list @ sp+16
    add r1, sp, #16         // use marg_list as return strage pointer
    add r0, sp, #16         // load marg_list
    bl ____forwarding___     // call through
    sub sp, fp, #4          // restore stack
    ldmfd sp!, {fp, lr}     // destroy stack frame
    cmp r0, #0              // check for forwarding completion
    bne LContinue           // circle back around if we're not done or failed
    ldmfd sp!, {r0-r3}      // load return value registers from marg_list
    bx lr                   // return

LContinue:
    str r0, [sp]            // failed or redirect; save new target in marg_list
    ldmfd sp!, {r0-r3}      // restore arg registers from marg_list
    b objc_msgSend          // restart message send

.fnend

.globl __CF_forwarding_prep_1
.align 2
.fnstart

__CF_forwarding_prep_1:      // top of stack is used as marg_list
    stmfd sp!, {r0-r3}      // push stret pointer and args to marg_list
    stmfd sp!, {fp, lr}     // setup stack frame
    .save {fp, lr}
    .setfp fp, sp, #4
    add fp, sp, #4
    .pad #8
    sub sp, sp, #8          // pad the stack
    add r1, r0, #0          // load stret pointer as return storage pointer
    add r0, sp, #20         // load marg_list, skipping the stret pointer
    bl ____forwarding___     // call through
    sub sp, fp, #4          // restore stack
    ldmfd sp!, {fp, lr}     // destroy stack frame
    cmp r0, #0              // check for forwarding completion
    bne LStretContinue      // circle back around if we're not done or failed
    ldmfd sp!, {r0-r3}      // load return value registers and stret pointer from marg_list
    bx lr                   // return

LStretContinue:
    str r0, [sp, #4]        // failed or redirect; save new target in marg_list
    ldmfd sp!, {r0-r3}      // restore arg registers and stret pointer from marg_list
    b objc_msgSend_stret    // restart message send
    
.fnend

#error TODO: Implement __CF_forwarding_prep_b for ARM

#elif __i386__

.text
.global  __CF_forwarding_prep_0
.align   4, 0x90

__CF_forwarding_prep_0:
    // All arguments are stack-based on i386
    // Using EAX as a scratch register
    push %ebp
    mov %esp, %ebp          // create a stack frame
    
    sub $0x50, %esp         // reserve space for the two arguments and 0x30 bytes of return storage
    and $-16, %esp          // align stack
    
    lea 8(%ebp), %eax       // load marg_list, skipping frame pointer and return address
    mov %eax, (%esp)        // pass marg_list as first argument

    lea 0x10(%esp), %eax    // load pointer to return value space on stack
    mov %eax, 4(%esp)       // pass pointer as second argument

    // clear out return value space: eax:edx at 0x00, room for an x87 value, a flag word at 0x20
    movl $0x0, 0x10(%esp)
    movl $0x0, 0x14(%esp)
    movl $0x0, 0x18(%esp)
    movl $0x0, 0x1c(%esp)
    movl $0x0, 0x20(%esp)
    movl $0x0, 0x24(%esp)
    movl $0x0, 0x28(%esp)
    movl $0x0, 0x2c(%esp)
    movl $0x0, 0x30(%esp)

    call ____forwarding___   // call through

    cmp $0, %eax            // check for forwarding completion
    jne LRestart            // forwarding target returned: restart the send

    // Load the return value registers from return storage. Float, double and long double
    // results are returned in st(0); the flag word says which one, if any.
    mov 0x30(%esp), %ecx
    cmp $1, %ecx
    je LRetFloat
    cmp $2, %ecx
    je LRetDouble
    cmp $3, %ecx
    je LRetLongDouble
    mov 0x10(%esp), %eax
    mov 0x14(%esp), %edx
    jmp LSuccess
LRetFloat:
    flds 0x10(%esp)
    jmp LSuccess
LRetDouble:
    fldl 0x10(%esp)
    jmp LSuccess
LRetLongDouble:
    fldt 0x10(%esp)
LSuccess:
    mov %ebp, %esp          // restore stack
    pop %ebp                // pop stack frame
    ret                     // return

LRestart:
    mov %ebp, %esp          // restore stack
    pop %ebp                // pop stack frame

    // Overwriting the caller's stack frame like this is not great, but there's
    //  no easy place to save off the old value; the next-best solution would
    //  be to call through a VERY slow path of __invoking__, at which point
    //  there's no use in having a fast path in the first place. This is not an
    //  issue on ARM or 64-bit Intel, and this SHOULD be safe for all cases.
    // If this causes an issue, it will manifest as subsequent messages to an
    //  object that implements -forwardingTargetForSelector: being sent to the
    //  forwarding target directly instead of going to the original object. This
    //  would have to be caused by the compiler not reloading the object pointer
    //  onto the stack for subsequent message sends to the same target.
    mov %eax, 4(%esp)       // overwrite original "self" value
    jmp _objc_msgSend        // restart message send
    
.text
.global  __CF_forwarding_prep_1
.align   2, 0x90

__CF_forwarding_prep_1:
    push %ebp
    mov %esp, %ebp          // create a stack frame

    sub $0x8, %esp          // reserve space for args pointer and return value
    and $-16, %esp          // align stack

    lea 12(%ebp), %eax      // load marg_list, skipping frame pointer, return address, and stret pointer
    mov %eax, (%esp)        // pass marg_list as first argument

    mov 8(%ebp), %eax       // load stret pointer
    mov %eax, 4(%esp)       // pass as second argument

    call ____forwarding___   // call through

    mov %ebp, %esp          // restore stack
    pop %ebp                // pop stack frame

    cmp $0, %eax            // check for forwarding completion
    je LStretSuccess        // return to caller if done

    mov %eax, 8(%esp)       // overwrite original "self" value (see long comment above)
    jmp _objc_msgSend_stret  // restart message send
LStretSuccess:
    ret $4                  // return value in stret pointer; return

.text
.global  __CF_forwarding_prep_b
.align   4, 0x90

// NOTE: i have not checked this implemention (it's kind of hacked together based on the other two `forwarding_prep`s)
//       i tried to test it, but blocks in general are broken on i386 at the moment (actually, the root issue is that setjmp is broken on i386)
__CF_forwarding_prep_b:
    push %ebp
    mov %esp, %ebp               // create a stack frame

    sub $0x04, %esp              // reserve space for args pointer
    and $-16, %esp               // align stack

    lea 8(%ebp), %eax            // load marg_list, skipping frame pointer and return address
    mov %eax, (%esp)             // pass marg_list as first argument

    call ___block_forwarding__   // call through

    mov %ebp, %esp               // restore stack
    pop %ebp                     // pop stack frame
    ret                          // return

#elif __x86_64__

.section __TEXT,__text,regular,pure_instructions
.globl __CF_forwarding_prep_0
.globl __CF_forwarding_prep_1
.align 4, 0x90

// Frame while forwarding (rsp-relative):
//   0x00  result registers for the caller: rax, rdx, xmm0, xmm1 (8 bytes each), then an x87 flag
//   0x40  the argument block (see NSInvocationInternal.h): rdi..r9 at 0x40, xmm0-7 at 0x70, %al at 0xf0
//   0x110 saved rbp, return address, then the caller's stack arguments, which therefore follow the
//         argument block at 0xe0 as NSMethodSignature expects
.macro SAVE_ARG_BLOCK
    movq   %rax, 0xf0(%rsp)
    movapd %xmm7, 0xe0(%rsp)
    movapd %xmm6, 0xd0(%rsp)
    movapd %xmm5, 0xc0(%rsp)
    movapd %xmm4, 0xb0(%rsp)
    movapd %xmm3, 0xa0(%rsp)
    movapd %xmm2, 0x90(%rsp)
    movapd %xmm1, 0x80(%rsp)
    movapd %xmm0, 0x70(%rsp)
    movq   %r9, 0x68(%rsp)
    movq   %r8, 0x60(%rsp)
    movq   %rcx, 0x58(%rsp)
    movq   %rdx, 0x50(%rsp)
    movq   %rsi, 0x48(%rsp)
    movq   %rdi, 0x40(%rsp)
.endm

// Reloads everything but rdi and rsi from the argument block.
.macro RESTORE_ARG_BLOCK
    movq   0xf0(%rsp), %rax
    movapd 0xe0(%rsp), %xmm7
    movapd 0xd0(%rsp), %xmm6
    movapd 0xc0(%rsp), %xmm5
    movapd 0xb0(%rsp), %xmm4
    movapd 0xa0(%rsp), %xmm3
    movapd 0x90(%rsp), %xmm2
    movapd 0x80(%rsp), %xmm1
    movapd 0x70(%rsp), %xmm0
    movq   0x68(%rsp), %r9
    movq   0x60(%rsp), %r8
    movq   0x58(%rsp), %rcx
    movq   0x50(%rsp), %rdx
.endm

__CF_forwarding_prep_0:
    .cfi_startproc
    .cfi_personality 155, ___objc_personality_v0
    push %rbp
    .cfi_def_cfa_offset 16
    .cfi_offset %rbp, -16
    movq %rsp, %rbp
    .cfi_def_cfa_register rbp

    subq   $0x110, %rsp
    SAVE_ARG_BLOCK

    // ____forwarding___(argument block, result registers, no hidden result pointer)
    leaq   0x40(%rsp), %rdi
    movq   %rsp, %rsi
    xorl   %edx, %edx
    call   ____forwarding___ // call through

    cmpq   $0, %rax          // check for forwarding completion
    jne    Lfail

    // if it's nil, we're done
    // now, load the return value from the on-stack storage
    // and jump back to our caller

    // here's how we get the return values (see NSInvoke-x86.S)
    movq   0x00(%rsp), %rax
    movq   0x08(%rsp), %rdx
    movsd  0x10(%rsp), %xmm0
    movsd  0x18(%rsp), %xmm1
    cmpq   $0, 0x20(%rsp)    // a long double result is returned in st(0)
    je     Lnox87
    fldt   0x00(%rsp)
Lnox87:

    movq   %rbp, %rsp
    pop    %rbp
    // .cfi_def_cfa rsp, 8
    ret

Lfail:
    // if we got a non-nil value, it's our forwarding target
    movq   %rax, %rdi
    RESTORE_ARG_BLOCK
    movq   0x48(%rsp), %rsi
    // movq   (%rsp), %rdi // self overwritten

    movq   %rbp, %rsp
    pop    %rbp
    // .cfi_def_cfa rsp, 8

    jmp    _objc_msgSend // restart message send

    .cfi_endproc

// Entered for messages whose result is returned through a hidden pointer: rdi holds the
// pointer, rsi the receiver and rdx the selector.
__CF_forwarding_prep_1:
    .cfi_startproc
    .cfi_personality 155, ___objc_personality_v0
    push %rbp
    .cfi_def_cfa_offset 16
    .cfi_offset %rbp, -16
    movq %rsp, %rbp
    .cfi_def_cfa_register rbp

    subq   $0x110, %rsp
    SAVE_ARG_BLOCK

    leaq   0x40(%rsp), %rdi
    movq   %rsp, %rsi
    movq   0x40(%rsp), %rdx  // the hidden result pointer
    call   ____forwarding___ // call through

    cmpq   $0, %rax
    jne    LfailStret

    // the result is already in the caller's memory; the hidden pointer comes back in rax
    movq   0x40(%rsp), %rax

    movq   %rbp, %rsp
    pop    %rbp
    ret

LfailStret:
    // the forwarding target replaces the receiver in rsi
    movq   %rax, %rsi
    RESTORE_ARG_BLOCK
    movq   0x40(%rsp), %rdi

    movq   %rbp, %rsp
    pop    %rbp

    jmp    _objc_msgSend_stret // restart message send

    .cfi_endproc

.globl __CF_forwarding_prep_b
.align 4, 0x90

__CF_forwarding_prep_b:
    .cfi_startproc
    .cfi_personality 155, ___objc_personality_v0 // not sure if this personality is correct for this function
    push %rbp
    .cfi_def_cfa_offset 16
    .cfi_offset %rbp, -16
    movq %rsp, %rbp
    .cfi_def_cfa_register rbp

    // Copy args from regs into a stack var
    subq   $0xd0, %rsp
    movq   %rax, 0xb0(%rsp)
    movapd %xmm7, 0xa0(%rsp)
    movapd %xmm6, 0x90(%rsp)
    movapd %xmm5, 0x80(%rsp)
    movapd %xmm4, 0x70(%rsp)
    movapd %xmm3, 0x60(%rsp)
    movapd %xmm2, 0x50(%rsp)
    movapd %xmm1, 0x40(%rsp)
    movapd %xmm0, 0x30(%rsp)
    movq   %r9, 0x28(%rsp)
    movq   %r8, 0x20(%rsp)
    movq   %rcx, 0x18(%rsp)
    movq   %rdx, 0x10(%rsp)
    movq   %rsi, 8(%rsp)
    movq   %rdi, (%rsp)

    // call into the actual forwarder
    movq   %rsp, %rdi
    call   ___block_forwarding__

    movq   %rbp, %rsp
    pop    %rbp
    ret

    .cfi_endproc

#elif defined(__arm64__) || defined(__aarch64__)

.section __TEXT,__text,regular,pure_instructions
.globl __CF_forwarding_prep_0
.globl __CF_forwarding_prep_1
.p2align 2

// The marg_list (x0-x7 at 0, d0-d7 at 64) is saved directly below the caller's
// stack arguments, so they follow at marg_list + 128 as NSMethodSignature lays them out.
.macro SAVE_MARG_LIST
    sub sp, sp, #128
    .cfi_def_cfa_offset 128
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp d0, d1, [sp, #64]
    stp d2, d3, [sp, #80]
    stp d4, d5, [sp, #96]
    stp d6, d7, [sp, #112]
    stp x29, x30, [sp, #-16]!
    .cfi_def_cfa_offset 144
    mov x29, sp
    .cfi_def_cfa w29, 144
    .cfi_offset w30, -136
    .cfi_offset w29, -144
.endm

__CF_forwarding_prep_0:
__CF_forwarding_prep_1:
    .cfi_startproc
    SAVE_MARG_LIST

    // 32 bytes of return value storage (x0/x1 or d0-d3), then the caller's indirect result location
    sub sp, sp, #48
    stp xzr, xzr, [sp]
    stp xzr, xzr, [sp, #16]
    str x8, [sp, #32]

    // ____forwarding___(marg_list, return value storage, indirect result location)
    add x0, x29, #16
    mov x1, sp
    mov x2, x8
    bl  ____forwarding___

    cbnz x0, Lfail_arm64   // non-nil means we have a forwarding target

    ldp x0, x1, [sp]
    ldp d0, d1, [sp]
    ldp d2, d3, [sp, #16]

    mov sp, x29
    ldp x29, x30, [sp], #16
    add sp, sp, #128
    ret

Lfail_arm64:
    // x0 is the forwarding target (new self); restore the other arguments and resend
    mov x9, x0
    ldr x8, [sp, #32]
    add x10, x29, #16

    ldp d0, d1, [x10, #64]
    ldp d2, d3, [x10, #80]
    ldp d4, d5, [x10, #96]
    ldp d6, d7, [x10, #112]

    ldr x1, [x10, #8]
    ldp x2, x3, [x10, #16]
    ldp x4, x5, [x10, #32]
    ldp x6, x7, [x10, #48]

    mov x0, x9

    mov sp, x29
    ldp x29, x30, [sp], #16
    add sp, sp, #128

    b   _objc_msgSend
    .cfi_endproc

.globl __CF_forwarding_prep_b
.p2align 2

__CF_forwarding_prep_b:
    .cfi_startproc
    SAVE_MARG_LIST

    add x0, x29, #16
    bl  ___block_forwarding__

    mov sp, x29
    ldp x29, x30, [sp], #16
    add sp, sp, #128
    ret
    .cfi_endproc

#else
#error Missing forwarding prep handlers for this arch
#endif
