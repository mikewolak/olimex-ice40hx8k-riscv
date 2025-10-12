/*==============================================================================
 * Olimex iCE40HX8K-EVB RISC-V Platform - Bootloader Linker Script
 * linker.ld - Memory layout for bootloader at 0x10000
 *
 * Copyright (c) October 2025 Michael Wolak
 * Email: mikewolak@gmail.com, mike@epromfoundry.com
 *
 * NOT FOR COMMERCIAL USE
 * Educational and research purposes only
 *============================================================================*/

/*
 * Bootloader Memory Map:
 *   0x00010000 - 0x00011FFF : Bootloader ROM (8KB SPRAM/BRAM)
 *   0x00000000 - 0x0007FFFF : Target SRAM (512KB) - where we write firmware
 *   0x80000000+            : MMIO peripherals
 */

MEMORY
{
    /* Bootloader runs from high memory (SPRAM initialized from bitstream) */
    BOOTROM (rx)  : ORIGIN = 0x00010000, LENGTH = 8K

    /* Stack grows down from end of bootloader space */
    STACK (rw)    : ORIGIN = 0x00011F00, LENGTH = 256
}

SECTIONS
{
    /* Entry point */
    ENTRY(_start)

    /* Bootloader code section */
    .text : {
        *(.text.start)      /* start.S must be first */
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > BOOTROM

    /* Read-only data */
    .rodata : {
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
    } > BOOTROM

    /* Initialized data (will be in ROM, copied to RAM if needed) */
    .data : {
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
    } > BOOTROM

    /* BSS section - uninitialized data */
    .bss : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > BOOTROM

    /* Stack pointer (grows downward from top of stack region) */
    __stack_top = ORIGIN(STACK) + LENGTH(STACK);

    /* Verify we didn't overflow */
    ASSERT(. <= 0x00012000, "ERROR: Bootloader exceeds 8KB!")
}
