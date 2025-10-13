//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// start.S - RISC-V Startup Code with Interrupt Support
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Startup code for PicoRV32 (RV32IM) with IRQ support
 * Entry point: _start (0x00000000)
 * IRQ vector: irq_vec (0x00000010)
 */

//==============================================================================
// Reset Vector and Main Entry
//==============================================================================

.section .text.start
.global _start

_start:
    /* Jump over IRQ vector to initialization code */
    j init_start

//==============================================================================
// Interrupt Vector (PROGADDR_IRQ = 0x10)
//
// CRITICAL: This MUST be at address 0x10!
// PicoRV32 automatically performs the following on IRQ entry:
//   - Saves PC+4 to q0 (return address)
//   - Saves IRQ mask to q1 (interrupt state)
//   - Disables all interrupts
//   - Jumps to this vector
//
// This handler:
//   1. Saves clobbered registers to stack
//   2. Passes IRQ bitmask to C handler
//   3. Restores registers
//   4. Returns via retirq (restores PC from q0, IRQ mask from q1)
//==============================================================================

// Padding to align IRQ vector at 0x10 (if needed)
.balign 16
.global irq_vec
irq_vec:
    /* Save ALL caller-saved registers that might be in use */
    /* CRITICAL: Must save a0-a7 and t0-t6 because main() may be using them */
    /* (e.g., main uses a3 for loop counter comparison!) */
    addi sp, sp, -64
    sw ra,  0(sp)
    sw a0,  4(sp)
    sw a1,  8(sp)
    sw a2, 12(sp)
    sw a3, 16(sp)   // CRITICAL: main uses a3 for loop!
    sw a4, 20(sp)
    sw a5, 24(sp)
    sw a6, 28(sp)
    sw a7, 32(sp)
    sw t0, 36(sp)
    sw t1, 40(sp)
    sw t2, 44(sp)
    sw t3, 48(sp)
    sw t4, 52(sp)
    sw t5, 56(sp)
    sw t6, 60(sp)
    /* Note: s0-s11 are callee-saved, C handler will preserve them */

    /* Read which IRQ(s) fired from q1 */
    /* q1 contains the IRQ bitmask (set by hardware on entry) */
    .insn r 0x0B, 4, 0, a0, x1, x0  // getq a0, q1 (load IRQ mask into a0)

    /* Call C interrupt handler */
    call irq_handler

    /* Restore ALL caller-saved registers */
    lw ra,  0(sp)
    lw a0,  4(sp)
    lw a1,  8(sp)
    lw a2, 12(sp)
    lw a3, 16(sp)   // CRITICAL: restore a3!
    lw a4, 20(sp)
    lw a5, 24(sp)
    lw a6, 28(sp)
    lw a7, 32(sp)
    lw t0, 36(sp)
    lw t1, 40(sp)
    lw t2, 44(sp)
    lw t3, 48(sp)
    lw t4, 52(sp)
    lw t5, 56(sp)
    lw t6, 60(sp)
    addi sp, sp, 64

    /* Return from interrupt */
    /* This restores PC from q0 and IRQ mask from q1 automatically */
    .insn r 0x0B, 0, 2, x0, x0, x0  // retirq

//==============================================================================
// Initialization Code (jumped to from _start)
//==============================================================================

init_start:
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

//==============================================================================
// Default (Weak) IRQ Handler
//
// This is a weak symbol that can be overridden by user code.
// If the user doesn't provide their own irq_handler(), this default
// implementation will be used (does nothing, just returns).
//==============================================================================

.weak irq_handler
irq_handler:
    ret  // Do nothing, just return
