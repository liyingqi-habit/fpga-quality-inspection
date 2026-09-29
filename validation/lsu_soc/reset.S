.section .text.start,"ax"
.option norvc
.global _start
_start: j start
.org 0x80
trap:
  csrr t3,mcause
  csrr t4,mepc
  csrr t5,mtval
  bne t3,s1,fail
  bne t4,s2,fail
  bne t5,s3,fail
  addi s5,s5,1
  addi t4,t4,4
  csrw mepc,t4
  mret
start:
  li s5,0
  li s0,0x80004400
  li t0,0x1234abcd
  sw t0,0(s0)
  lw t1,0(s0)
  bne t0,t1,fail
  li s1,5
  li s3,0x20000000
  la s2,badread
badread: lw t1,0(s3)
  li s1,7
  la s2,badwrite
badwrite: sw t0,0(s3)
  li t0,2
  bne s5,t0,fail
  li t0,0x10000010
  li t1,0x66
  sw t1,0(t0)
done: j done
fail:
  li t0,0x10000010
  li t1,0xee
  sw t1,0(t0)
failed: j failed
