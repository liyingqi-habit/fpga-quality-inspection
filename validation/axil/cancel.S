.option norvc
.section .text
.global _start
_start:
  lui t0,0x10000
  addi t0,t0,(BOOT*16)
#if BOOT == 0
  lui t1,0xaabbd
  addi t1,t1,-803
#else
  lui t1,0x55667
  addi t1,t1,1928
#endif
fault:
#if WRITE == 1
  sw t1,0(t0)
  addi a0,t1,0
#else
  lw a0,0(t0)
  nop
#endif
  sw a0,(32-BOOT*16)(t0)
  lui a1,0x600d0
  addi a1,a1,BOOT
  sw a1,(36-BOOT*16)(t0)
done: j done
.org 0x80
handler:
  csrr a0,mcause
  csrr a1,mepc
  csrr a2,mtval
  lui t0,0x10000
  sw a0,40(t0)
  sw a1,44(t0)
  sw a2,48(t0)
  li a1,0xbad
  sw a1,36(t0)
trapped: j trapped
