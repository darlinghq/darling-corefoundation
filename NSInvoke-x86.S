
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

#elif defined(__x86_64__) // Now the x86-64 version

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
#elif defined(__arm64__) || defined(__aarch64__)

// ARM64 __invoke__
// x0 = msgSend function pointer
// x1 = retdata pointer
// x2 = args (marg_list)
// x3 = frame_length
// x4 = return_type
//
// marg_list layout for ARM64:
//   bytes 0-63:   x0-x7 integer/pointer register args (8 * 8 bytes)
//   bytes 64-127: d0-d7 floating-point register args (8 * 8 bytes)
//   bytes 128+:   stack-passed arguments

  stp x29, x30, [sp, #-16]!
  mov x29, sp
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!

  mov x19, x0    // x19 = msgSend function pointer
  mov x20, x1    // x20 = retdata pointer
  mov x21, x4    // x21 = return_type
  mov x22, x2    // x22 = args pointer (saved so we can load x2 as argument)

  // Copy stack arguments if frame_length > 128
  cmp x3, #128
  b.le Lno_stack_args_arm64

  sub x9, x3, #128     // number of stack arg bytes
  // Align stack allocation to 16 bytes
  add x9, x9, #15
  and x9, x9, #-16
  sub sp, sp, x9

  // Copy stack args
  add x10, x22, #128   // source = args + 128
  mov x11, sp           // dest = sp
  sub x12, x3, #128    // remaining bytes
Lcopy_loop_arm64:
  ldr x13, [x10], #8
  str x13, [x11], #8
  subs x12, x12, #8
  b.gt Lcopy_loop_arm64

Lno_stack_args_arm64:
  // Load floating-point register arguments from args
  ldp d0, d1, [x22, #64]
  ldp d2, d3, [x22, #80]
  ldp d4, d5, [x22, #96]
  ldp d6, d7, [x22, #112]

  // Load integer register arguments from args
  // Load x2 from its slot since x22 holds the args pointer
  ldp x6, x7, [x22, #48]
  ldp x4, x5, [x22, #32]
  ldr x3, [x22, #24]
  ldr x2, [x22, #16]
  ldr x1, [x22, #8]
  ldr x0, [x22, #0]

  // Call the function
  blr x19

  // Store return value based on return type
  ldrb w9, [x21]

  // Always store integer return value
  str x0, [x20]
  str x1, [x20, #8]

  // Check for float/double return types
  cmp w9, #0x66        // 'f' = float
  b.eq Lfloatret_arm64
  cmp w9, #0x64        // 'd' = double
  b.eq Ldoubleret_arm64
  cmp w9, #0x44        // 'D' = long double (== double on ARM64)
  b.eq Ldoubleret_arm64
  b Ldone_arm64

Lfloatret_arm64:
  str s0, [x20]
  b Ldone_arm64

Ldoubleret_arm64:
  str d0, [x20]

Ldone_arm64:
  mov sp, x29
  ldp x21, x22, [sp, #-32]
  ldp x19, x20, [sp, #-16]
  ldp x29, x30, [sp], #16
  ret

#else
#error Unsupported architecture for NSInvoke
#endif


