#!/bin/bash
# Generate start.S from .config

set -e

if [ ! -f .config ]; then
    echo "ERROR: .config not found. Run 'make menuconfig' or 'make defconfig' first."
    exit 1
fi

source .config

mkdir -p build/generated

cat > build/generated/start.S << 'EOF'
// Auto-generated from .config - DO NOT EDIT
// RISC-V Startup Code with Interrupt Support

.section .text.start
.global _start

_start:
    /* Jump over IRQ vector to initialization code */
    j init_start

//==============================================================================
// Interrupt Vector (PROGADDR_IRQ = 0x10)
//==============================================================================

.balign 16
.global irq_vec
irq_vec:
    /* Save ALL caller-saved registers */
    addi sp, sp, -64
    sw ra,  0(sp)
    sw a0,  4(sp)
    sw a1,  8(sp)
    sw a2, 12(sp)
    sw a3, 16(sp)
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

    /* Read which IRQ(s) fired from q1 */
    .insn r 0x0B, 4, 0, a0, x1, x0  // getq a0, q1

    /* Call C interrupt handler */
    call irq_handler

    /* Restore ALL caller-saved registers */
    lw ra,  0(sp)
    lw a0,  4(sp)
    lw a1,  8(sp)
    lw a2, 12(sp)
    lw a3, 16(sp)
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
    .insn r 0x0B, 0, 2, x0, x0, x0  // retirq

//==============================================================================
// Initialization Code
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

    /* Set up argc and argv for main(int argc, char **argv) */
    li a0, 0        // argc = 0
    li a1, 0        // argv = NULL

    /* Call main function */
    call main

    /* Infinite loop if main returns */
loop_forever:
    j loop_forever

//==============================================================================
// Default (Weak) IRQ Handler
//==============================================================================

.weak irq_handler
irq_handler:
    ret  // Do nothing, just return
EOF

echo "✓ Generated build/generated/start.S"
