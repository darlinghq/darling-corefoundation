
.text
.align 4, 0x90
.globl ___invoke__
___invoke__:

# void __invoke__(void (*msgSend)(...),
#                 void *retdata,
#                 marg_list args,
#                 size_t frame_length,
#                 const char *return_type)

#ifdef __i386__

    # Save retdata, scratch register, and return address.
  push %ebp  # Prologue
  mov %esp, %ebp
  push %edi
  push %esi
  push %edx
  push %ebx

  mov 12+8(%ebp), %eax #$eax = frame_length
  mov 8+8(%ebp), %edx #$edx = args

  mov %esp, %ebx
  subl %eax, %esp  #push the stack down
  andl $-16, %esp  #and align

Lpush:
  movl -4(%eax,%edx), %edi
  movl %edi, -4(%esp,%eax)
  sub $4, %eax
  test %eax, %eax
  jne Lpush

  mov 0+8(%ebp), %edi #$edi = msgSend
  calll *%edi
  
  mov 4+8(%ebp), %esi #$esi = retdata

  mov %eax, (%esi) # copy the result (probably) into *retdata
  
  #next, check to see if we need to put something else (ie something from
  #the x87 registers or a 64-bit value) into *retdata instead. 

  mov 8+16(%ebp), %eax #$eax == return_type
  mov (%eax), %al
  cmpb $0x71, %al # if (returnType[0] == 'q') // int64_t
  je Lsixtyfourret
  cmpb $0x51, %al # if (returnType[0] == 'Q') // uint64_t
  je Lsixtyfourret
  cmpb $0x44, %al # if (returnType[0] == 'D') // long double
  je Llongdoubleret
  cmpb $0x64, %al # if (returnType[0] == 'd') // double
  je Ldoubleret
  cmpb $0x66, %al  # if (returnType[0] == 'f') // float
  jne Ldone
  fstps (%esi) # this is how to get things out of x87.
  # fstp pops and stores a certain length (determined by the suffix - 
  # s for float, l for double, t for long double - just go with it)
  # in the location given (in this case *$esi)
  jmp Ldone #then jump to to cleanup and return
Lsixtyfourret:
  # just store edx too
  mov %edx, 4(%esi)
  jmp Ldone
Ldoubleret:
  fstpl (%esi)
  jmp Ldone
Llongdoubleret:
  fstpt (%esi)

Ldone:
  mov %ebx, %esp # restore stack!
  pop %ebx
  pop %edx
  pop %esi
  pop %edi
  mov %ebp, %esp  # Epilogue
  pop %ebp
  ret

#elif defined(__x86_64__)

  .cfi_startproc
  .cfi_personality 155, ___objc_personality_v0
  push %rbp # Prologue
  .cfi_def_cfa_offset 16
  .cfi_offset %rbp, -16
  movq %rsp, %rbp
  .cfi_def_cfa_register rbp
  push %rdi
  .cfi_offset %rdi, -24
  push %rsi
  .cfi_offset %rsi, -32
  push %r8
  .cfi_offset %r8, -40
  movq %rdx, %rsi

  subq %rcx, %rsp # Push the stack down
  andq $-16, %rsp  #and align

  # Shift stack contents (frame_length/8) times,
  # 8 bytes at a time
  # TODO: More efficient than the Lpush loop
  # in i386 assembly above
  movq %rsp, %rdi
  shrq $3, %rcx # frame_length /= 8
  cld
  rep movsq

  # Copy args into registers
  movq 0xb0(%rsp), %rax
  movapd 0xa0(%rsp), %xmm7
  movapd 0x90(%rsp), %xmm6
  movapd 0x80(%rsp), %xmm5
  movapd 0x70(%rsp), %xmm4
  movapd 0x60(%rsp), %xmm3
  movapd 0x50(%rsp), %xmm2
  movapd 0x40(%rsp), %xmm1
  movapd 0x30(%rsp), %xmm0

  movq 0x28(%rsp), %r9
  movq 0x20(%rsp), %r8
  movq 0x18(%rsp), %rcx
  movq 0x10(%rsp), %rdx
  movq 8(%rsp), %rsi
  movq (%rsp), %rdi

  addq $224, %rsp
  movq -8(%rbp), %r10 # call objc_msgSend
  callq *%r10

  movq -16(%rbp), %rsi # return value
  movq -24(%rbp), %rcx
  cmpb $0x44, %cl # if (returnType[0] == 'D') // long double
  je Llongdoubleret

  # double
  movapd %xmm1, 32(%rsi)
  movapd %xmm0, 16(%rsi)

  # int128
  movq %rdx, 8(%rsi)
  movq %rax, (%rsi)

  jmp Ldone
Llongdoubleret:
  fstpt (%rsi)
Ldone:
  movq %rbp, %rsp # Epilogue
  pop %rbp
  // .cfi_def_cfa rsp, 8
  ret
  .cfi_endproc

#elif __arm64__
; typedef void* marg_list;
; void __invoke__(
;     void (*msgSend)(...),    // x0 
;     void *retdata,           // x1
;     marg_list args,          // x2
;     size_t frame_length,     // x3
;     const char *return_type  // x4
; )

; Prologue
  stp   fp, lr, [sp, #-16]
  mov   fp, sp

; ┌──── stack ───┐
; ├ msgSend      ┤ <-- fp
; ├ retdata      ┤ <-- fp+8
; ├ args         ┤ <-- fp+16
; ├ frame_length ┤ <-- fp+24
; ├ return_type  ┤ <-- fp+32
; ├ sp_offset    ┤ <-- fp+40
; └──────────────┘

; Push all arguments to stack
  stp   x0, x1, [sp, #-16]!
  stp   x2, x3, [sp, #-32]!
  str   x4, [sp, #16]

; Copy args into registers
;   To better understand how the values in `args` is structured, it's
;   recommended to look at Darling's implementation of NSMethodSignature.
;
;  regs
; ┌────┐ [-- GP --]
; ├ x0 ┤ <-- 0
; ├ x1 ┤ <-- 8
; ├ x2 ┤ <-- 16
; ├ x3 ┤ <-- 24
; ├ x4 ┤ <-- 32
; ├ x5 ┤ <-- 40
; ├ x6 ┤ <-- 48
; ├ x7 ┤ <-- 56
; ├ x8 ┤ <-- 64
; ├────┤ [-- FP --]
; ├ v0 ┤ <-- 72
; ├ v1 ┤ <-- 88
; ├ v2 ┤ <-- 104
; ├ v3 ┤ <-- 120
; ├ v4 ┤ <-- 136
; ├ v5 ┤ <-- 152
; ├ v6 ┤ <-- 168
; ├ v7 ┤ <-- 184
; ├────┤ [ -- stack --]
; ├????┤ <-- 200+??
; └────┘
#define ARGS_STACK_OFFSET 200

; Copy GP registers
  ldr x9, [fp, #16]      ; x9 = args
  ldp x0, x1, [x9], #16
  ldp x2, x3, [x9], #16
  ldp x4, x5, [x9], #16
  ldp x6, x7, [x9], #16
  ldr x8, [fp], #8
; Copy FP regsiters
  ld1 {v0.16b}, [x9], #16
  ld1 {v1.16b}, [x9], #16
  ld1 {v2.16b}, [x9], #16
  ld1 {v3.16b}, [x9], #16
  ld1 {v4.16b}, [x9], #16
  ld1 {v5.16b}, [x9], #16
  ld1 {v6.16b}, [x9], #16
  ld1 {v7.16b}, [x9], #16

; Copy (stack) args to stack (TODO: Optimize code)
  ldp x9, x11, [fp, #16]          ; x9 = args; x11 = frame_length
  add x9, x9, #ARGS_STACK_OFFSET  ; const void* input_array = args + register_offset
  mov x10, sp                     ; void* output_array = sp
  sub x11, x3, #ARGS_STACK_OFFSET ; counter = frame_length - register_offset

one_byte_copy:
  ldrb    w12, [x9], #1   ; char temp = *(input_array++);
  subs    x11, x11, #1    ; counter--;
  strb    w12, [x10], #1  ; *(output_array++) = temp;
  b.ne    one_byte_copy

  ; Align the stack and store the offset 
  and x10, x10, #-16  ; output_array &= -16
  sub x11, sp, x10    ; sp_offset = sp - output_array
  str x11, [fp, #40]
  ; Update SP
  mov sp, x10         ; sp = output_array

; Call objc_msgSend
  ldr x9, [fp]
  blr x9

; Store return values
  ldr x9, [fp, #8]      ; x9 = retdata
; Store GP return values
  str x0, [x9], #8
  str x1, [x9], #8
; Store FP return values
  st1 {v0.16b}, [x9], #16

; Remove stack allocation of args
  ldr x10, [fp, #16]    ; x10 = sp_offset
  add sp, sp, x10
; Restore atack allocation of arguments
  add sp, sp, #48

; Epilogue
  ldp   fp, lr, [sp, #16]
  ret

#else
#error "Missing NSInvoke assembly implementation for arch"
#endif


