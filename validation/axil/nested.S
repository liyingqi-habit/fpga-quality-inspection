// Test-only two-level handler: s8/s9 reserve outer mepc/mstatus, not a general ABI.
.section .text.start,"ax"
.option norvc
.global _start, handler, outer_entry, inner_entry, checkpoint, outer_return_prepare
.global fault_pc, wait_outer, resume, resume_end, outer_wait, outer_wait_end, outer_mret
_start: j main
.org 0x80
handler:
  addi s3,s3,1
  bnez s4,inner_entry
outer_entry:
  csrr s8,mepc
  csrr s9,mstatus
  li t0,10
  sw t0,0(s11)
  csrr t0,mcause
  sw t0,4(s11)
  sw s8,8(s11)
  li t0,0x1888
  and t0,s9,t0
  sw t0,12(s11)
  sw s5,16(s11)
  sw s6,20(s11)
  sw s7,24(s11)
  addi s11,s11,28
#if OUTER != 0
  li t0,(1 << OUTER)
  sw t0,0x38(s0)
1:csrr t1,mip
  and t1,t1,t0
  bnez t1,1b
#endif
  li s4,1
  li t0,(1 << INNER)
  sw t0,0x34(s0)
checkpoint:
  sw s5,0x44(s0)
#if NESTED
  csrsi mstatus,8
outer_wait:
  li t0,2
  bne s4,t0,outer_wait
outer_wait_end:
#else
outer_wait:
  .rept 24
  nop
  .endr
outer_wait_end:
#endif
outer_return_prepare:
  csrci mstatus,8
#if OUTER == 0
  la s8,resume
#endif
#if BAD_RESTORE
  csrw mepc,zero
#else
  csrw mepc,s8
#endif
  csrw mstatus,s9
  li t0,30
  sw t0,0(s11)
  csrr t0,mepc
  sw t0,4(s11)
  csrr t0,mstatus
  li t1,0x1888
  and t0,t0,t1
  sw t0,8(s11)
  sw s4,12(s11)
  addi s11,s11,16
  li s4,3
outer_mret:
  mret
inner_entry:
  li t0,20
  sw t0,0(s11)
  csrr t0,mcause
  sw t0,4(s11)
  csrr t0,mepc
  sw t0,8(s11)
  csrr t0,mstatus
  li t1,0x1888
  and t0,t0,t1
  sw t0,12(s11)
  sw s4,16(s11)
  sw s5,20(s11)
  sw s6,24(s11)
  sw s7,28(s11)
  addi s11,s11,32
  li t0,(1 << INNER)
  sw t0,0x38(s0)
2:csrr t1,mip
  and t1,t1,t0
  bnez t1,2b
  li s4,2
  mret
.org 0x400
main:
  li s0,0x10000000
  li s11,0x80004000
  li s3,0
  li s4,0
  li s5,0xdeadbeef
  li s6,0x2468ace0
  li s7,0x13579bdf
  la t0,handler
  csrw mtvec,t0
  li t0,((1 << INNER) | (1 << OUTER))
  csrw mie,t0
  csrsi mstatus,8
#if OUTER != 0
  li t0,(1 << OUTER)
  sw t0,0x30(s0)
#endif
wait_outer:
#if OUTER == 0
fault_pc:
  ecall
#else
fault_pc:
  beq s3,zero,wait_outer
#endif
resume:
  li t0,2
  bne s3,t0,resume
resume_end:
  csrci mstatus,8
  li t0,40
  sw t0,0(s11)
  sw s3,4(s11)
  sw s5,8(s11)
  sw s6,12(s11)
  sw s7,16(s11)
  li t0,1
  sw t0,0x24(s0)
done:j done
