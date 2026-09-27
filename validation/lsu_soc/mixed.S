.section .text.start,"ax"
.option norvc
.global _start
_start: j start
.org 0x80
trap:
  li t0,0x10000010
  li t1,0xee
  sw t1,0(t0)
halt: j halt
start:
  li s0,0x80004800
  la s1,inputs
  li s2,0
  li s3,0
  li s4,32
loop:
  lw t0,0(s1)
  srli t1,t0,3
  li t2,7
  mul t0,t0,t2
  add t0,t0,s2
#ifdef MIX_MUTATION
  addi t0,t0,1
#endif
  xor t0,t0,t1
  li t2,3
  div t3,t0,t2
  rem t4,t0,t2
  sw t3,0(s0)
  sw t4,4(s0)
  sw zero,8(s0)
  sw zero,12(s0)
  sw t0,16(s0)
  lw a3,0(s0)
  bne a3,t3,trap
  andi t5,s2,3
  add t5,t5,s0
  sb t3,8(t5)
  lbu t6,8(t5)
  lb a0,8(t5)
  andi t5,s2,1
  slli t5,t5,1
  add t5,t5,s0
  sh t4,12(t5)
  lh a1,12(t5)
  lhu a2,12(t5)
  add s3,s3,t6
  add s3,s3,a2
  blt t0,zero,negative
  add s3,s3,t3
  j joined
negative:
  sub s3,s3,t3
joined:
  jal ra,mix
  sw s3,20(s0)
  sw a0,24(s0)
  sw a1,28(s0)
  addi s0,s0,32
  addi s1,s1,4
  addi s2,s2,1
  blt s2,s4,loop
  li t0,0x10000010
  li t1,0x5a
  sw t1,0(t0)
done: j done
mix:
  xor s3,s3,t0
  jalr zero,0(ra)
.align 2
inputs:
.include "mixed_inputs.inc"
