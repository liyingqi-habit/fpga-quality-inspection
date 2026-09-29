.option norvc
.section .text
.global _start
_start:
  lui t0,0x10000
  addi t0,t0,TEST_OFFSET
  lui t1,0xaabbd
  addi t1,t1,(-1024+TEST_ID)
fault_store:
  sw t1,0(t0)
young_store:
  sw t1,4(t0)
done:
  j done
.org 0x80
handler:
  csrr a0,mcause
  csrr a1,mepc
  csrr a2,mtval
trapped:
  j trapped
