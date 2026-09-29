/* Offline trap and reset regression; never a board firmware image. */
.section .text.start,"ax"
.global _start
.option norvc
_start: j tests
.org 0x80
trap:
  csrr t3, mcause
  csrr t4, mepc
  csrr t5, mtval
  sw t3, 0(s4)
  sw t4, 4(s4)
  sw t5, 8(s4)
  bne t3, s1, fail
  bne t4, s2, fail
  bne t5, s3, fail
  addi s4, s4, 12
  addi s5, s5, 1
  addi t4, t4, 4
  csrw mepc, t4
  mret
.macro expect id, cause, address, instruction
  li s0, \id
  li s1, \cause
  li s3, \address
  la s2, \instruction
.endm
tests:
  li s4, 0x80004000
  li s5, 0
  expect 1, 2, 0, illegal
#ifdef TRAP_MUTATION
  li s1, 3
#endif
illegal: .word 0
  expect 2, 5, 0x20000000, badread
  li t0, 0x20000000
badread: lw t1, 0(t0)
  expect 3, 4, 0x80004101, misload
  li t0, 0x80004100
  li t1, 0x11223344
  sw t1, 0(t0)
  sw t1, 4(t0)
misload: lw t2, 1(t0)
  expect 4, 6, 0x80004102, misstore
misstore: sw t1, 2(t0)
  lw t2, 0(t0)
  bne t1, t2, fail
  li t2, 4
  bne s5, t2, fail
  li t0, 0x10000010
  li t1, 0x31
  sw t1, 0(t0)
  li t0, 0x10000000
  li t1, 0x41
  sw t1, 0(t0)
  li t1, 0x42
  sw t1, 0(t0)
  li t0, 0x10000010
  li t1, 0x32
  sw t1, 0(t0)
  li t0, 0x87654321
  li t1, 7
  divu t2, t0, t1
  li t3, 0x13579be0
  bne t2, t3, fail
  li t0, 0x10000010
  li t1, 0x55
  sw t1, 0(t0)
done: j done
fail:
  li t0, 0x10000010
  ori t1, s0, 0x80
  sw t1, 0(t0)
failed: j failed
