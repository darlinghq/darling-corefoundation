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
    
    sub $0x10, %esp         // reserve space for args pointer, return value pointer, and return values
    and $-16, %esp          // align stack
    
    lea 8(%ebp), %eax       // load marg_list, skipping frame pointer and return address
    mov %eax, (%esp)        // pass marg_list as first argument

    lea 8(%esp), %eax       // load pointer to return value space on stack
    mov %eax, 4(%esp)       // pass pointer as second argument

    movl $0x0, 8(%esp)      // clear out return value space
    movl $0x0, 12(%esp)

    call ____forwarding___   // call through
    mov 4(%esp), %edx       // temporarily save return storage pointer

    mov %ebp, %esp          // restore stack
    pop %ebp                // pop stack frame
    
    cmp $0, %eax            // check for forwarding completion
    je LSuccess             // return to caller if done

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
LSuccess:
    mov (%edx), %eax        // load return value registers from return storage
    mov 4(%edx), %edx
    ret                     // return
    
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

__CF_forwarding_prep_0:
__CF_forwarding_prep_1:
    .cfi_startproc
    .cfi_personality 155, ___objc_personality_v0
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

    movq   %rsp, %rdi
    leaq   0xc0(%rsp), %rsi
    call   ____forwarding___ // call through

    cmpq   $0, %rax          // check for forwarding completion
    jne    Lfail

    // if it's nil, we're done
    // now, load the return value from the on-stack storage
    // and jump back to our caller

    // here's how we get the return values (see NSInvoke-x86.S)
    movq   0xc0(%rsp), %rax
    movq   0xc8(%rsp), %rdx
    movapd 0xd0(%rsp), %xmm0
    movapd 0xe0(%rsp), %xmm1

    movq   %rbp, %rsp
    pop    %rbp
    // .cfi_def_cfa rsp, 8
    ret

Lfail:
    // if we got a non-nil value, it's our forwarding target
    movq   %rax, %rdi
    movq   0x80(%rsp), %rax
    movapd 0xa0(%rsp), %xmm7
    movapd 0x90(%rsp), %xmm6
    movapd 0x80(%rsp), %xmm5
    movapd 0x70(%rsp), %xmm4
    movapd 0x60(%rsp), %xmm3
    movapd 0x50(%rsp), %xmm2
    movapd 0x40(%rsp), %xmm1
    movapd 0x30(%rsp), %xmm0
    movq   0x28(%rsp), %r9
    movq   0x20(%rsp), %r8
    movq   0x18(%rsp), %rcx
    movq   0x10(%rsp), %rdx
    movq   8(%rsp), %rsi
    // movq   (%rsp), %rdi // self overwritten

    movq   %rbp, %rsp
    pop    %rbp
    // .cfi_def_cfa rsp, 8

    jmp    _objc_msgSend // restart message send

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

__CF_forwarding_prep_0:
__CF_forwarding_prep_1:
    // Save frame and link register
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Allocate space for register save area (128) + return value (32)
    sub sp, sp, #160

    // Save integer register arguments at sp+0
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]

    // Save floating-point register arguments at sp+64
    stp d0, d1, [sp, #64]
    stp d2, d3, [sp, #80]
    stp d4, d5, [sp, #96]
    stp d6, d7, [sp, #112]

    // Call ____forwarding___(marg_list, return_stret_addr)
    mov x0, sp             // marg_list
    add x1, sp, #128       // return value storage
    bl  ____forwarding___

    cbnz x0, Lfail_arm64   // non-nil means we have a forwarding target

    // Load return values from on-stack storage
    ldr x0, [sp, #128]
    ldr d0, [sp, #128]

    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

Lfail_arm64:
    // x0 is the forwarding target (new self)
    // Restore all other args and restart message send
    mov x9, x0             // save forwarding target

    ldp d0, d1, [sp, #64]
    ldp d2, d3, [sp, #80]
    ldp d4, d5, [sp, #96]
    ldp d6, d7, [sp, #112]

    // Restore integer args (x0 = new target, skip original x0)
    ldr x1, [sp, #8]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]

    mov x0, x9             // new self

    mov sp, x29
    ldp x29, x30, [sp], #16

    b   _objc_msgSend      // restart message send with new target

.globl __CF_forwarding_prep_b
.p2align 2

__CF_forwarding_prep_b:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    sub sp, sp, #128

    // Save integer register arguments
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]

    // Save floating-point register arguments
    stp d0, d1, [sp, #64]
    stp d2, d3, [sp, #80]
    stp d4, d5, [sp, #96]
    stp d6, d7, [sp, #112]

    mov x0, sp
    bl  ___block_forwarding__

    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

#else
#error Missing forwarding prep handlers for this arch
#endif
