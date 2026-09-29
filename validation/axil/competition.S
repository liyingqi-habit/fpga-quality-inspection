// Test firmware: a held LW/SW fault races an externally driven machine IRQ.
.section .text.start,"ax"
.option norvc
.global _start, fault_pc, younger_pc, resume, resume_end, handler
#ifndef SYNC_KIND
#define SYNC_KIND -1
#endif
.global armed, fetch_jump
_start:
  j main
.org 0x80
handler:
  csrr t0,mcause
  sw t0,0(s11)
  csrr t0,mepc
  sw t0,4(s11)
  csrr t0,mtval
  sw t0,8(s11)
  csrr t0,mstatus
  li t1,0x1888
  and t0,t0,t1
  sw t0,12(s11)
  csrr t0,mip
  li t1,(1 << SOURCE)
  and t0,t0,t1
  sw t0,16(s11)
  sw s5,20(s11)
  sw s6,24(s11)
  sw s7,28(s11)
  sw s4,32(s11)
  addi s11,s11,36
  csrr t0,mcause
  bltz t0,irq_handler
  addi s4,s4,1
  la t0,resume
  csrw mepc,t0
  mret
irq_handler:
  li t0,0x10000030
  sw zero,0(t0)
irq_clear_wait:
  csrr t0,mip
  li t1,(1 << SOURCE)
  and t0,t0,t1
  bnez t0,irq_clear_wait
  addi s4,s4,2
  mret
.org 0x200
main:
  csrci mstatus,8
  la t0,handler
  csrw mtvec,t0
  li s11,0x80004000
  li s4,0
  li s5,0xdeadbeef
  li s6,0
  li s7,0x13579bdf
  li s0,0x10000000
#if SYNC_KIND == 5
  li s0,0x80000202
#elif SYNC_KIND == 6
  li s0,0x20000000
#endif
#if MASKED
  csrw mie,zero
#else
  li t0,(1 << SOURCE)
  csrw mie,t0
#endif
  csrsi mstatus,8
armed:
  nop
  nop
fetch_jump:
#if SYNC_KIND == 6
  jalr zero,0(s0)
#endif
fault_pc:
#if SYNC_KIND == 0
  ecall
#elif SYNC_KIND == 1
  ebreak
#elif SYNC_KIND == 2
  .word 0
#elif SYNC_KIND == 3
  lw s5,1(s0)
#elif SYNC_KIND == 4
  sw s5,2(s0)
#elif SYNC_KIND == 5
  jalr s5,0(s0)
#elif SYNC_KIND == 6
  nop // Unreachable fall-through of the fetch-fault jump.
#elif WRITE
  sw s5,0(s0)
#else
  lw s5,0(s0)
#endif
younger_pc:
  addi s6,s6,1
resume:
#if MASKED
  li t0,1
#else
  li t0,3
#endif
  bne s4,t0,resume
  csrci mstatus,8
resume_end:
  sw s4,0(s11)
  sw s6,4(s11)
  sw s5,8(s11)
  li t0,0x10000024
  sw s4,0(t0)
done:
  j done
