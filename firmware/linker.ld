/*
 * Linker script for PicoRV32 on iCE40-HX8K
 * 512KB SRAM (0x00000000 - 0x0007FFFF)
 *
 * Memory allocation:
 *   Code/Data/BSS: 80% = 417,792 bytes (0x66000)
 *   Heap:          15% =  77,824 bytes (0x13000)
 *   Stack:          5% =  28,672 bytes (0x07000)
 *   Total:              524,288 bytes (0x80000 = 512KB)
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    SRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x80000  /* 512 KB */
}

SECTIONS
{
    /* Code and read-only data */
    .text : {
        *(.text.start)    /* Entry point */
        *(.text*)         /* All code */
        *(.rodata*)       /* Read-only data */
        . = ALIGN(4);
    } > SRAM

    /* Initialized data */
    .data : {
        . = ALIGN(4);
        __data_start = .;
        *(.data*)
        . = ALIGN(4);
        __data_end = .;
    } > SRAM

    /* Uninitialized data (BSS) */
    .bss : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > SRAM

    /* End of code/data/bss - start of heap */
    . = ALIGN(4);
    __code_end = .;

    /* Heap: 77,824 bytes (0x13000) starting after BSS */
    .heap : {
        __heap_start = .;
        . = . + 0x13000;  /* 15% of 512KB */
        __heap_end = .;
    } > SRAM

    /* Stack: 28,672 bytes (0x07000) at top of SRAM */
    /* Stack grows downward from __stack_top */
    __stack_bottom = 0x00079000;  /* 0x80000 - 0x7000 */
    __stack_top = 0x00080000;     /* Top of SRAM */

    /* Sanity check: ensure we don't overflow */
    ASSERT(__heap_end <= __stack_bottom, "Heap overflow into stack region!")
}
