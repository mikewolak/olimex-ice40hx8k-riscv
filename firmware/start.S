//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// start.s - RISC-V Startup Code
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Startup code for PicoRV32 (RV32E)
 * Entry point: _start
 */

.section .text.start
.global _start

_start:
    /* Set up stack pointer */
    la sp, __stack_top

    /* Clear BSS section */
    la t0, __bss_start
    la t1, __bss_end
clear_bss:
    bge t0, t1, done_clear_bss
    sw zero, 0(t0)
    addi t0, t0, 4
    j clear_bss
done_clear_bss:

    /* Call main function */
    call main

    /* Infinite loop if main returns */
loop_forever:
    j loop_forever
