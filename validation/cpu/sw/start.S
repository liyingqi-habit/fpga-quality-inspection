.section .text.start,"ax"
.global _start
_start:
  j boot
  .org 0x80
trap:
  li t0, 0x10000010
  li t1, 0xee
  sw t1, 0(t0)
1: j 1b
boot:
  la sp, _stack_top
  la t0, _sidata
  la t1, _sdata
  la t2, _edata
1: bgeu t1, t2, 2f
  lw t3, 0(t0)
  sw t3, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  j 1b
2: la t0, _sbss
  la t1, _ebss
3: bgeu t0, t1, 4f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 3b
4: call main
5: j 5b
