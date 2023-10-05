
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

#else
#error "Missing NSInvoke assembly implementation for arch"
#endif


