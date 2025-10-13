//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// picorv32_irq.h - PicoRV32 Custom Interrupt Instructions
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

#ifndef PICORV32_IRQ_H
#define PICORV32_IRQ_H

#include <stdint.h>

//==============================================================================
// PicoRV32 Custom Interrupt Instructions
//
// PicoRV32 uses custom RISC-V instructions (opcode 0x0B) for interrupt handling.
// These are NOT standard RISC-V instructions and require special macros.
//
// IRQ Shadow Registers (Q-Registers):
//   When ENABLE_IRQ_QREGS=1, PicoRV32 provides 4 shadow registers (q0-q3):
//   - q0: Automatically stores return PC when interrupt occurs
//   - q1: Automatically stores IRQ mask when interrupt occurs
//   - q2-q3: Available for handler use (save/restore clobbered registers)
//
// Interrupt Flow:
//   1. IRQ occurs → CPU jumps to PROGADDR_IRQ (0x10 in our system)
//   2. Hardware automatically: PC → q0, IRQ mask → q1, disable IRQs
//   3. Assembly handler: Save context to q2/q3, call C handler
//   4. C handler: Process interrupt, clear interrupt source
//   5. Assembly handler: Restore context from q2/q3
//   6. Execute retirq → restores PC from q0, IRQ mask from q1
//==============================================================================

//==============================================================================
// Instruction Macros (for inline assembly)
//==============================================================================

// picorv32_getq(rd, qs) - Get value from IRQ shadow register
//   rd: Destination general-purpose register (x0-x31)
//   qs: Source Q-register (q0-q3, encoded as 0-3)
//
//   Opcode: 0x0B, Funct7: 0x00, Funct3: 0x4
//   Example: picorv32_getq(x10, q2) - Load q2 into a0 (x10)
#define picorv32_getq(rd, qs) \
    __asm__ volatile (".insn r 0x0B, 4, 0, %0, %1, x0" : "=r"(rd) : "r"(qs))

// picorv32_setq(qd, rs) - Set IRQ shadow register from general register
//   qd: Destination Q-register (q0-q3, encoded as 0-3)
//   rs: Source general-purpose register (x0-x31)
//
//   Opcode: 0x0B, Funct7: 0x01, Funct3: 0x2
//   Example: picorv32_setq(q2, x10) - Save a0 (x10) to q2
#define picorv32_setq(qd, rs) \
    __asm__ volatile (".insn r 0x0B, 2, 1, x0, %0, %1" :: "r"(rs), "r"(qd))

// picorv32_retirq() - Return from interrupt handler
//   Restores PC from q0 and IRQ mask from q1 (automatic)
//
//   Opcode: 0x0B, Funct7: 0x02, Funct3: 0x0
//   Must be last instruction in IRQ handler
#define picorv32_retirq() \
    __asm__ volatile (".insn r 0x0B, 0, 2, x0, x0, x0" ::: "memory")

// picorv32_maskirq(rd, rs) - Mask/unmask interrupts
//   rs: New IRQ mask (1 = masked/disabled, 0 = unmasked/enabled)
//   rd: Returns previous IRQ mask value
//
//   Opcode: 0x0B, Funct7: 0x03, Funct3: 0x6
//   Example: uint32_t old_mask = picorv32_maskirq_read(0xFFFFFFFF); // Disable all
#define picorv32_maskirq(rd, rs) \
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0" : "=r"(rd) : "r"(rs))

// picorv32_waitirq() - Wait for interrupt (low-power mode)
//   CPU halts until an interrupt occurs
//
//   Opcode: 0x0B, Funct7: 0x04, Funct3: 0x4
//   Use for power-saving when idle
#define picorv32_waitirq() \
    __asm__ volatile (".insn r 0x0B, 4, 4, x0, x0, x0" ::: "memory")

// picorv32_timer(rd, rs) - Read/write CPU timer register
//   rs: New timer value (write)
//   rd: Previous timer value (read)
//
//   Opcode: 0x0B, Funct7: 0x05, Funct3: 0x6
//   Note: This is PicoRV32's internal cycle counter, NOT our timer peripheral
#define picorv32_timer(rd, rs) \
    __asm__ volatile (".insn r 0x0B, 6, 5, %0, %1, x0" : "=r"(rd) : "r"(rs))

//==============================================================================
// Helper Macros for Common Operations
//==============================================================================

// Disable all interrupts, return previous mask
static inline uint32_t irq_disable(void) {
    uint32_t old_mask;
    picorv32_maskirq(old_mask, 0xFFFFFFFF);
    return old_mask;
}

// Enable all interrupts, return previous mask
static inline uint32_t irq_enable(void) {
    uint32_t old_mask;
    picorv32_maskirq(old_mask, 0x00000000);
    return old_mask;
}

// Restore interrupt mask
static inline void irq_restore(uint32_t mask) {
    uint32_t dummy;
    picorv32_maskirq(dummy, mask);
    (void)dummy;
}

// Enable specific IRQ bit (0-31)
static inline void irq_enable_bit(uint32_t bit) {
    uint32_t old_mask, new_mask;
    picorv32_maskirq(old_mask, 0);  // Read current mask without changing
    picorv32_maskirq(old_mask, 0);  // Read again (quirk)
    new_mask = old_mask & ~(1 << bit);  // Clear bit = enable IRQ
    picorv32_maskirq(old_mask, new_mask);
}

// Disable specific IRQ bit (0-31)
static inline void irq_disable_bit(uint32_t bit) {
    uint32_t old_mask, new_mask;
    picorv32_maskirq(old_mask, 0);  // Read current mask without changing
    picorv32_maskirq(old_mask, 0);  // Read again (quirk)
    new_mask = old_mask | (1 << bit);  // Set bit = disable IRQ
    picorv32_maskirq(old_mask, new_mask);
}

//==============================================================================
// C Interrupt Handler Prototype
//
// This function is called by the assembly IRQ handler in start.S
// It receives the current IRQ bitmask showing which interrupts fired.
//
// Handler should:
//   1. Check which IRQ(s) are set in the 'irqs' parameter
//   2. Clear the interrupt source(s) at the peripheral level
//   3. Return 0
//
// Example:
//   void irq_handler(uint32_t irqs) {
//       if (irqs & (1 << 0)) {
//           // Timer interrupt (IRQ[0])
//           handle_timer_interrupt();
//       }
//   }
//==============================================================================

extern void irq_handler(uint32_t irqs);

#endif // PICORV32_IRQ_H
