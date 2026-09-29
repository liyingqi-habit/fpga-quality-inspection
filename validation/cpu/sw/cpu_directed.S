/* Offline-only directed tests. Not a board image or full ISA certification.
 * Expected constants are independent of the DUT, following RISC-V M v2.0.
 */
.section .text.start,"ax"
.global _start
.option norvc
_start:
  j tests
  .org 0x80
trap:
#ifdef MIGRATED_SOC
  csrr t3,mcause
  li t4,7
  bne t3,t4,fail
  csrr t3,mepc
  la t4,invalid_store
  bne t3,t4,fail
  csrr t4,mtval
  li t5,0x20000000
  bne t4,t5,fail
  addi s6,s6,1
  addi t3,t3,4
  csrw mepc,t3
  mret
#else
  li t0, 0x10000010
  li t1, 0xee
  sw t1, 0(t0)
1: j 1b
#endif

.macro check id, op, lhs, rhs, expected
  li s0, \id
  li t0, \lhs
  li t1, \rhs
  \op t2, t0, t1
  li t3, \expected
  bne t2, t3, fail
.endm

tests:
  li s6,0
#ifdef CPU_TEST_MUTATION
  check 1, mul, -1, -1, 2
#else
  check 1, mul, -1, -1, 1
#endif
  check 2, mulh, -1, -1, 0
  check 3, mulh, 0x80000000, 2, -1
  check 4, mulhu, 0xffffffff, 0xffffffff, 0xfffffffe
  check 5, mulhsu, -1, 0xffffffff, -1
  check 6, mulhsu, 0x80000000, 2, -1
  check 7, div, -7, 3, -2
  check 8, rem, -7, 3, -1
  check 9, div, 7, -3, -2
  check 10, rem, 7, -3, 1
  check 11, div, 0x80000000, -1, 0x80000000
  check 12, rem, 0x80000000, -1, 0
  check 13, div, -7, 0, -1
  check 14, rem, -7, 0, -7
  check 15, divu, 0x87654321, 0, 0xffffffff
  check 16, remu, 0x87654321, 0, 0x87654321
  check 17, divu, 0xffffffff, 2, 0x7fffffff
  check 18, remu, 0xffffffff, 2, 1

  li s1, 0x80004000
  li t0, 0x11223344
  sw t0, 0(s1)
  li s0, 19
  li t0, 0x80
  sb t0, 1(s1)
  lw t2, 0(s1)
  li t3, 0x11228044
  bne t2, t3, fail
  li s0, 20
  lb t2, 1(s1)
  li t3, -128
  bne t2, t3, fail
  li s0, 21
  lbu t2, 1(s1)
  li t3, 128
  bne t2, t3, fail
  li s0, 22
  li t0, 0x8001
  sh t0, 2(s1)
  lw t2, 0(s1)
  li t3, 0x80018044
  bne t2, t3, fail
  li s0, 23
  lh t2, 2(s1)
  li t3, 0xffff8001
  bne t2, t3, fail
  li s0, 24
  lhu t2, 2(s1)
  li t3, 0x8001
  bne t2, t3, fail

  /* Wrong-path stores must not change the sentinel. */
  li s0, 25
  sw zero, 4(s1)
  li t0, 1
  beq t0, t0, taken
  sw t0, 4(s1)
taken:
  lw t2, 4(s1)
  bnez t2, fail

  /* Default: characterize the legacy diagnostic-only invalid store.
   * MIGRATED_SOC: handler validates precise cause7/PC/address and resumes. */
  li s0, 26
  li t0, 0x20000000
invalid_store: sw zero, 0(t0)
  li t0, 0x10000028
  lw t2, 0(t0)
  li t3, 1
  bne t2, t3, fail

  /* No polling: the second write must wait while the first frame is busy. */
#ifdef MIGRATED_SOC
  li t3,1
  bne s6,t3,fail
#endif
  li s0, 27
  li t0, 0x10000000
  li t1, 0x41
  sw t1, 0(t0)
  li t1, 0x42
  sw t1, 0(t0)
  li t0, 0x10000010
  li t1, 0x55
  sw t1, 0(t0)
done: j done
fail:
  li t0, 0x10000010
  ori t1, s0, 0x80
  sw t1, 0(t0)
2: j 2b
