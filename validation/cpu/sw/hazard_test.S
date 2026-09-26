/* Directed RAW dependency tests; not a complete ISA compliance suite.
 * Caller-saved registers only. Vary instruction distance to cover bypass paths.
 */
.section .text
.global hazard_test
hazard_test:
  .option push
  .option norvc
  .macro check_gap gap
    li t0, 19
    .rept \gap
      nop
    .endr
    add t1, t0, t0
    li t2, 38
    bne t1, t2, bad
    addi t0, t1, 3
    add t1, t0, t1
    li t2, 79
    bne t1, t2, bad
  .endm
  check_gap 0
  check_gap 1
  check_gap 2
  check_gap 3
  check_gap 4
  check_gap 5
  addi sp, sp, -16
  li t0, 0x12345678
  sw t0, 0(sp)
  lw t1, 0(sp)
  add t2, t1, t1
  li t3, 0x2468acf0
  addi sp, sp, 16
  bne t2, t3, bad
  addi zero, t0, 1
  addi t1, zero, 0
  bnez t1, bad
  li a0, 0
  ret
bad:
  li a0, 1
  ret
  .option pop
