/*==============================================================================
 * Olimex iCE40HX8K-EVB RISC-V Platform - Firmware/Application Linker Script
 * linker.ld - Memory layout for uploaded applications
 *
 * Copyright (c) October 2025 Michael Wolak
 * Email: mikewolak@gmail.com, mike@epromfoundry.com
 *
 * NOT FOR COMMERCIAL USE
 * Educational and research purposes only
 *============================================================================*/

/*
 * Application/Firmware Linker Script
 *
 * Physical Memory Map:
 *   0x00000000 - 0x0003FFFF : Application SRAM (256KB)
 *   0x00040000 - 0x00041FFF : Bootloader ROM (read-only, not for apps)
 *   0x00042000 - 0x0007FFFF : Heap/Stack SRAM (~248KB)
 *   0x80000000+            : MMIO peripherals
 *
 * Linking Strategy:
 *   Applications are uploaded by bootloader to SRAM starting at 0x00000000.
 *   Code executes at absolute address 0x0.
 *   Simple linking - VMA = LMA = 0x0.
 */

MEMORY
{
    /* Application code and data in SRAM */
    APPSRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K

    /* Stack/Heap space (shared with bootloader stack region) */
    STACK (rw)    : ORIGIN = 0x00042000, LENGTH = 248K
}

SECTIONS
{
    ENTRY(_start)

    /* Code section at 0x0 */
    .text : {
        *(.text.start)      /* Startup code first */
        *(.text*)
        . = ALIGN(4);
    } > APPSRAM

    /* Read-only data */
    .rodata : {
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
    } > APPSRAM

    /* Initialized data */
    .data : {
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
    } > APPSRAM

    /* Uninitialized data */
    .bss : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > APPSRAM

    /* Heap starts after BSS */
    __heap_start = ALIGN(., 4);
    __heap_end = ORIGIN(STACK);

    /* Stack pointer (grows down from top of stack region) */
    __stack_top = ORIGIN(STACK) + LENGTH(STACK);

    /* Verify application fits in SRAM */
    __app_size = SIZEOF(.text) + SIZEOF(.rodata) + SIZEOF(.data) + SIZEOF(.bss);
    ASSERT(__app_size <= 256K, "ERROR: Application exceeds 256KB SRAM!")
}
