// Separate post-local-reset ROM fixture; target and pending pins may survive.
.section .text.start,"ax"
.option norvc
.global _start, handler, enabled, recovery_end
_start:j main
.org 0x80
handler:
  csrr t0,mcause
  sw t0,0(s11)
  csrr t1,mepc
  sw t1,4(s11)
  csrr t1,mtval
  sw t1,8(s11)
  csrr t1,mstatus
  li t2,0x1888
  and t1,t1,t2
  sw t1,12(s11)
  addi s11,s11,16
  andi t0,t0,31
  li t1,1
  sll t1,t1,t0
  sw t1,0x38(s0)
1:csrr t2,mip
  and t2,t2,t1
  bnez t2,1b
  addi s3,s3,1
  mret
.org 0x200
main:
  li s0,0x10000000
  li s11,0x80004800
  li s3,0
  li s5,0x89abcdef
  csrr t0,mstatus
  andi t0,t0,8 // Only the architecturally relevant reset MIE bit is asserted here.
  sw t0,0(s11)
  csrr t0,mie
  li t1,0x888
  and t0,t0,t1
  sw t0,4(s11)
  csrr s2,mip
  and s2,s2,t1
  sw s2,8(s11)
  addi s11,s11,12
  la t0,handler
  csrw mtvec,t0
  csrw mie,t1
  csrsi mstatus,8
enabled:
  .rept 64
  nop
  .endr
recovery_end:
  csrci mstatus,8
  sw s3,0(s11)
  sw s5,4(s11)
  li t0,2
  sw t0,0x24(s0)
done:j done
