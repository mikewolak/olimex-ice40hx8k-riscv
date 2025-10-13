// Timer Interrupt Integration Test
// Configures timer peripheral to generate interrupts and counts them

#include <stdint.h>

// Timer peripheral registers (MMIO)
#define TIMER_CR   ((volatile uint32_t*)0x80000020)  // Control register
#define TIMER_SR   ((volatile uint32_t*)0x80000024)  // Status register
#define TIMER_PSC  ((volatile uint32_t*)0x80000028)  // Prescaler
#define TIMER_ARR  ((volatile uint32_t*)0x8000002C)  // Auto-reload register
#define TIMER_CNT  ((volatile uint32_t*)0x80000030)  // Counter

#define LED_CONTROL ((volatile uint32_t*)0x80000008)

volatile uint32_t interrupt_count = 0;

static inline void irq_enable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, x0, x0" : "=r"(dummy));
}

void irq_handler(void) {
    // Increment counter
    interrupt_count++;

    // Clear timer interrupt flag (write 1 to clear UIF bit)
    *TIMER_SR = 0x00000001;
}

int main(void) {
    // Enable interrupts in CPU
    irq_enable();

    // Configure timer for fast simulation testing
    // Clock = 50 MHz
    // PSC = 9 → divide by 10 → 5 MHz tick
    // ARR = 499 → 500 ticks → 10 kHz IRQ → 100us period

    *TIMER_PSC = 9;         // Prescaler: divide by 10
    *TIMER_ARR = 499;       // Auto-reload: 500 ticks (10kHz for fast simulation)
    *TIMER_CR  = 0x00000001; // Enable timer

    // Wait for 10 interrupts
    while (interrupt_count < 10) {
        asm volatile("nop");
    }

    // Disable timer
    *TIMER_CR = 0x00000000;

    // Signal completion with LEDs
    *LED_CONTROL = 0x3;

    // Infinite loop
    while (1) {
        asm volatile("nop");
    }

    return 0;
}
