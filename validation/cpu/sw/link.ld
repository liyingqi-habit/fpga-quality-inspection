OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
  ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 16K
  RAM (rwx) : ORIGIN = 0x80004000, LENGTH = 16K
}
SECTIONS {
  .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) . = ALIGN(4); } > ROM
  .data : { _sdata = .; *(.sdata*) *(.data*) . = ALIGN(4); _edata = .; } > RAM AT> ROM
  _sidata = LOADADDR(.data);
  .bss (NOLOAD) : { _sbss = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(_ebss + 2048 < _stack_top, "Insufficient stack")
}
