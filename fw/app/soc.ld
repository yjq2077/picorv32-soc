/* soc.ld - link PicoRV32 firmware into the 64KB AXI-Lite RAM at 0x00000000 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;

  .text : {
    *(.text)
    *(.text.*)
  }

  .rodata : {
    *(.rodata .rodata.*)
  }

  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
  }

  __bss_start = .;
  .bss : {
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
  }
  . = ALIGN(4);
  __bss_end = .;

  _end = .;
}
