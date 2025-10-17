//==============================================================================
// Simple Interrupt Counter Test
// Tests basic interrupt handling without timer peripheral
// NO UART OUTPUT - just test interrupts!
//==============================================================================

#include <stdint.h>

// Memory-mapped I/O addresses
#define LED_CONTROL     ((volatile uint32_t*)0x80000008)

// Result location (testbench will read this)
#define RESULT_ADDR     ((volatile uint32_t*)0x00001000)

// Global interrupt counter
volatile uint32_t interrupt_count = 0;

// PicoRV32 custom IRQ instruction - enable all interrupts (clear IRQ mask)
static inline void irq_enable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, x0, x0" : "=r"(dummy));
}

// Interrupt handler - called from assembly stub at 0x10
// Note: With very short IRQ pulses (<50ns), the latch clears before handler completes
void irq_handler(void) {
    interrupt_count++;
}

int main(void) {
    // Enable interrupts immediately - no delays, no UART!
    irq_enable();

    // Wait for interrupts (testbench will trigger them)
    while (interrupt_count < 10) {
        asm volatile("nop");
    }

    // Write result to memory location for testbench verification
    *RESULT_ADDR = interrupt_count;

    // Signal completion
    *LED_CONTROL = 0x3;  // Light both LEDs

    // Infinite loop
    while (1) {
        asm volatile("nop");
    }

    return 0;
}
