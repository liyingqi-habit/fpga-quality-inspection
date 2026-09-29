/* BA-0.2: board acceptance candidate, hardware UNVERIFIED. No stack/RAM state.
 * t3/t4 are exclusively trap scratch; s7..s11 are trap contract state.
 * No nesting, no C ABI, no actuator control. Match validation/axil/soc.sv.
 */
.option norvc
.option norelax
.equ IO, 0x10000000
.equ HZ, 27000000
.section .text.start,"ax"
.global _start
_start: j main
.org 0x80
j trap
.org 0x100
main:
  csrci mstatus,8
  csrw mie,zero
  la t0,trap_vector
  csrw mtvec,t0
  /* These CSRs have no defined reset value in this CPU configuration.
   * A RAM failure before the first trap must still print defined diagnostics. */
diagnostics_init:
  csrw mepc,zero
  csrw mcause,zero
  csrw mtval,zero
  li s7,0
  li s8,-1
  li s9,0
  li s10,0
  li s11,0
  li t0,IO
  sw zero,0x30(t0)
  li t1,-1
  sw t1,0x34(t0)
  sw zero,0x10(t0)
  la a0,banner
  jal puts
  /* Destructive full 16 KiB RAM test, no stack/data/bss in RAM. */
  li s2,0
  li s3,4
ram_pass:
  li s0,0x80004000
  li s1,0x80008000
ram_fill:
  xor t0,s0,s2
  sw t0,0(s0)
  addi s0,s0,4
  bltu s0,s1,ram_fill
  fence rw,rw
  li s0,0x80004000
ram_check:
  xor t0,s0,s2
  lw t1,0(s0)
  li a0,0x10
  bne t0,t1,fail
  addi s0,s0,4
  bltu s0,s1,ram_check
  addi s3,s3,-1
  beqz s3,ram_done
  li t0,3
  beq s3,t0,pattern_ones
  li t0,2
  beq s3,t0,pattern_55
  li s2,0xaaaaaaaa
  j ram_pass
pattern_ones: li s2,-1
  j ram_pass
pattern_55: li s2,0x55555555
  j ram_pass
ram_done:
  la a0,ram_ok
  jal puts
  li s7,0
  li s8,11
  la s9,ecall_site
  la s10,ecall_return
  li s11,0
ecall_site: ecall
ecall_return:
  li a0,0x20
  jal check_trap
  li s7,0
  li s8,2
  la s9,illegal_site
  la s10,illegal_return
  li s11,0
illegal_site: .word 0
illegal_return:
  li a0,0x21
  jal check_trap
  li s7,0
  li s8,3
  la s9,break_site
  la s10,break_return
  li s11,0
break_site: ebreak
break_return:
  li a0,0x22
  jal check_trap
  la a0,exceptions_ok
  jal puts
  /* Only the selected IRQ is enabled; trap masks it before returning. */
  li s7,0
  li s8,0x80000003
  li t0,IO
  li t1,1
  sw t1,0x30(t0)
  li t1,8
  csrw mie,t1
  csrsi mstatus,8
  li a0,0x30
  jal wait_irq
  la a0,software_ok
  jal puts
  li s7,0
  li s8,0x80000007
  li t0,IO
  lw t1,0x20(t0)
  li t2,270000
  add t2,t1,t2
  li a0,0x32
  bltu t2,t1,fail
  sw t2,0x34(t0)
  li t1,128
  csrw mie,t1
  csrsi mstatus,8
  li a0,0x31
  jal wait_irq
  la a0,timer_ok
  jal puts
  la a0,release_prompt
  jal puts
  li a0,0x40
  jal wait_release
  la a0,press_prompt
  jal puts
  li s7,0
  li s8,0x8000000b
  li t1,2048
  csrw mie,t1
  csrsi mstatus,8
  li a0,0x41
  jal wait_irq
  la a0,release_prompt
  jal puts
  li a0,0x42
  jal wait_release
  li s8,-1
  la a0,external_ok
  jal puts
  la a0,done_prompt
  jal puts
  /* No automatic restart. LED0 heartbeat is not a substitute for UART log. */
idle:
  li t0,IO
  lw t1,0x20(t0)
  srli t1,t1,24
  andi t1,t1,1
  sw t1,0x10(t0)
  j idle

check_trap:
  li t0,1
  bne s7,t0,fail
  li s8,-1
  ret

/* Bounded by tick elapsed AND loop budget, no WFI/no indefinite key wait.
 * 30 s at 27 MHz; unsigned subtraction handles one tick wrap. */
wait_irq:
  li t0,IO
  lw a1,0x20(t0)
  li a2,810000000
  li a3,100000000
1:
  bnez s7,2f
  lw t1,0x20(t0)
  sub t1,t1,a1
  bgeu t1,a2,fail
  addi a3,a3,-1
  beqz a3,fail
  j 1b
2:
  csrr t1,mstatus
  andi t1,t1,8
  beqz t1,fail
  csrci mstatus,8
  csrw mie,zero
  li t1,1
  bne s7,t1,fail
  li s8,-1
  ret

/* Require external mip bit low continuously for 100 ms (not a press debounce).
 * 30 s overall timeout; keeps MEIE masked during release/bounce. */
wait_release:
  li t0,IO
  lw a1,0x20(t0)
  mv a2,a1
  li a3,100000000
1:
  lw t1,0x20(t0)
  sub t2,t1,a1
  li a4,810000000
  bgeu t2,a4,fail
  addi a3,a3,-1
  beqz a3,fail
  /* MEIP mask cannot use sign-extended immediate 0x800. */
  csrr t2,mip
  srli t2,t2,11
  andi t2,t2,1
  beqz t2,2f
  mv a2,t1
  j 1b
2:
  sub t2,t1,a2
  li a4,2700000
  bltu t2,a4,1b
  ret

.balign 4
trap_vector: j trap
trap:
  csrr t3,mcause
  bne t3,s8,trap_bad
  bnez s7,trap_bad
  csrr t4,mstatus
  andi t4,t4,8
  bnez t4,trap_bad
  bltz t3,trap_irq
  csrr t4,mepc
  bne t4,s9,trap_bad
  csrr t4,mtval
  bne t4,s11,trap_bad
  csrw mepc,s10
  li s7,1
  mret
trap_irq:
  csrr t4,mtval
  bnez t4,trap_bad
  csrw mie,zero
  li t3,IO
  sw zero,0x30(t3)
  li t4,-1
  sw t4,0x34(t3)
  li s7,1
  mret
trap_bad:
  li a0,0xe0
  j fail

/* puts clobbers a0,t0,t1,t2,s6; never used from a passing trap. */
puts:
  mv s6,ra
1: lbu t0,0(a0)
  beqz t0,2f
  jal putc
  addi a0,a0,1
  j 1b
2: jr s6
putc:
  li t1,IO
  li t2,2700000
1: lw a5,4(t1)
  andi a5,a5,1
  beqz a5,2f
  addi t2,t2,-1
  bnez t2,1b
  j quiet_failure
2: sw t0,0(t1)
  ret
hex32:
  mv s5,ra
  mv a2,a0
  li a3,8
1: srli t0,a2,28
  li a4,10
  bltu t0,a4,2f
  addi t0,t0,55
  j 3f
2: addi t0,t0,48
3: jal putc
  slli a2,a2,4
  addi a3,a3,-1
  bnez a3,1b
  jr s5
fail:
  csrci mstatus,8
  csrw mie,zero
  mv s3,a0
  la a0,fail_prompt
  jal puts
  mv a0,s3
  jal hex32
  la a0,cause_prompt
  jal puts
  csrr a0,mcause
  jal hex32
  la a0,pc_prompt
  jal puts
  csrr a0,mepc
  jal hex32
  la a0,tval_prompt
  jal puts
  csrr a0,mtval
  jal hex32
  la a0,newline
  jal puts
quiet_failure:
  csrci mstatus,8
  csrw mie,zero
  li t0,IO
  li t1,1
  sw t1,0x10(t0)
1: j 1b

.section .rodata
banner: .asciz "\r\nCPU BOARD ACCEPTANCE BA-0.2 UNVERIFIED\r\nCPU=RC1-d0e23f3c CLK=27000000 UART=115200-8N1\r\nBOOT RAM-DESTRUCTIVE NO-ACTUATORS\r\n"
ram_ok: .asciz "PASS RAM 0x80004000..0x80007FFF 4 address-XOR passes\r\n"
exceptions_ok: .asciz "PASS EXCEPTIONS ECALL ILLEGAL EBREAK\r\n"
software_ok: .asciz "PASS IRQ SOFTWARE\r\n"
timer_ok: .asciz "PASS IRQ TIMER\r\n"
release_prompt: .asciz "WAIT RELEASE KEY1 (30s timeout, 100ms stable)\r\n"
press_prompt: .asciz "WAIT PRESS KEY1 ONCE (30s timeout)\r\n"
external_ok: .asciz "PASS IRQ EXTERNAL PRESS/RELEASE\r\n"
done_prompt: .asciz "SELFTEST PASS (limited tests only)\r\nMANUAL: KEY0 reset -> repeat entire test; then cold power cycle -> repeat.\r\n"
fail_prompt: .asciz "\r\nFAIL code=0x"
cause_prompt: .asciz " mcause=0x"
pc_prompt: .asciz " mepc=0x"
tval_prompt: .asciz " mtval=0x"
newline: .asciz "\r\n"
