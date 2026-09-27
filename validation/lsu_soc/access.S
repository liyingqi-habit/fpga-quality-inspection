.section .text.start,"ax"
.option norvc
.global _start
_start: j tests
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
.macro eq reg,value
  li t6,\value
  bne \reg,t6,fail
.endm
.macro fault cause,addr,label
  li s1,\cause
  li s3,\addr
  la s2,\label
.endm
tests:
  li s0,1
  li s5,0
  li s4,0x80004200
  li t0,0x11223344
  sw t0,0(s4)
  li t0,0x80
  sb t0,0(s4)
  li t0,0xff
  sb t0,1(s4)
  li t0,0x7f
  sb t0,2(s4)
  li t0,0x81
  sb t0,3(s4)
  lw t1,0(s4)
  eq t1,0x817fff80
  lb t1,0(s4)
  eq t1,-128
  lbu t1,0(s4)
  eq t1,128
  lb t1,1(s4)
  eq t1,-1
  lbu t1,1(s4)
#ifdef LOAD_MUTATION
  eq t1,-1
#else
  eq t1,255
#endif
  lb t1,2(s4)
  eq t1,127
  lbu t1,2(s4)
  eq t1,127
  lb t1,3(s4)
  eq t1,-127
  lbu t1,3(s4)
  eq t1,129
  li s0,2
  li t0,0x8001
  sh t0,0(s4)
  li t0,0xfedc
  sh t0,2(s4)
  lw t1,0(s4)
  eq t1,0xfedc8001
  lh t1,0(s4)
  eq t1,0xffff8001
  lhu t1,0(s4)
  eq t1,0x8001
  lh t1,2(s4)
  eq t1,0xfffffedc
  lhu t1,2(s4)
  eq t1,0xfedc
  # ROM reads, RAM boundary and load-to-use dependency.
  li s0,3
  la t0,romword
  lw t1,0(t0)
  eq t1,0x13579bdf
  li t0,0x80007ffc
  sw t1,0(t0)
  lw t2,0(t0)
  addi t2,t2,1
  eq t2,0x13579be0
  li s0,4
  li t0,0x800043f0
  li t1,1
#ifdef FLUSH_MUTATION
  bne t1,t1,taken
#else
  beq t1,t1,taken
#endif
wrong_ram: sw t1,0(t0)
taken:
  li t0,0x10000000
  jal zero,jumped
wrong_mmio: sw t1,0(t0)
jumped:
  li t0,0x20000000
  bne t1,zero,skipload
wrong_load: lw t2,0(t0)
skipload:
  li t0,0x80004220
  beq t1,zero,fail
  sw t1,0(t0)
  lw t2,0(t0)
  eq t2,1
  li s0,5
  fault 5,0x20000000,badread
  li t0,0x20000000
badread: lw t1,0(t0)
  fault 7,0x20000000,badwrite
badwrite: sw zero,0(t0)
  fault 7,0x80000000,romwrite
  li t0,0x80000000
romwrite: sw zero,0(t0)
  fault 7,0x10000024,readonlywrite
  li t0,0x10000024
readonlywrite: sw zero,0(t0)
  li s0,6
  fault 4,0x80004201,misread
misread: lh t1,1(s4)
  fault 6,0x80004201,miswrite
miswrite: sh zero,1(s4)
  eq s5,6
  lw t1,0(s4)
#ifdef ACCESS_MUTATION
  eq t1,0xfedc8000
#else
  eq t1,0xfedc8001
#endif
  li t0,0x10000010
  li t1,0x55
  sw t1,0(t0)
done: j done
fail:
  li t0,0x10000010
  ori t1,s0,0x80
  sw t1,0(t0)
failed: j failed
.align 2
romword: .word 0x13579bdf
