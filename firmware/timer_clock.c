//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// timer_clock.c - Timer Interrupt Clock Demo
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

#include <stdint.h>

// Memory-mapped I/O register addresses
#define MMIO_BASE           0x80000000
#define UART_TX_DATA        (*(volatile uint32_t*)(MMIO_BASE + 0x00))
#define UART_TX_STATUS      (*(volatile uint32_t*)(MMIO_BASE + 0x04))
#define UART_RX_DATA        (*(volatile uint32_t*)(MMIO_BASE + 0x08))
#define UART_RX_STATUS      (*(volatile uint32_t*)(MMIO_BASE + 0x0C))
#define LED_CONTROL         (*(volatile uint32_t*)(MMIO_BASE + 0x10))

// Timer peripheral registers (base 0x80000020)
#define TIMER_BASE          0x80000020
#define TIMER_CR            (*(volatile uint32_t*)(TIMER_BASE + 0x00))
#define TIMER_SR            (*(volatile uint32_t*)(TIMER_BASE + 0x04))
#define TIMER_PSC           (*(volatile uint32_t*)(TIMER_BASE + 0x08))
#define TIMER_ARR           (*(volatile uint32_t*)(TIMER_BASE + 0x0C))
#define TIMER_CNT           (*(volatile uint32_t*)(TIMER_BASE + 0x10))

// Timer control bits
#define TIMER_CR_ENABLE     (1 << 0)
#define TIMER_CR_ONE_SHOT   (1 << 1)
#define TIMER_SR_UIF        (1 << 0)

//==============================================================================
// PicoRV32 Custom IRQ Instructions (inline assembly macros)
//==============================================================================

// Enable all interrupts (clear IRQ mask)
static inline void irq_enable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0" : "=r"(dummy) : "r"(0));
}

//==============================================================================
// UART Functions
//==============================================================================

static void uart_putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while TX busy
    UART_TX_DATA = c;
}

static void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

//==============================================================================
// Timer Helper Functions
//==============================================================================

static void timer_init(void) {
    TIMER_CR = 0;               // Disable timer
    TIMER_SR = TIMER_SR_UIF;    // Clear any pending interrupt
}

static void timer_config(uint16_t psc, uint32_t arr) {
    TIMER_PSC = psc;
    TIMER_ARR = arr;
}

static void timer_start(void) {
    TIMER_CR = TIMER_CR_ENABLE;  // Enable, continuous mode
}

static void timer_clear_irq(void) {
    TIMER_SR = TIMER_SR_UIF;     // Write 1 to clear
}

//==============================================================================
// Clock State (updated by interrupt)
//==============================================================================

volatile uint32_t frames = 0;   // Frame counter (0-59, increments at 60 Hz)
volatile uint32_t seconds = 0;  // Seconds counter (0-59)
volatile uint32_t minutes = 0;  // Minutes counter (0-59)
volatile uint32_t hours = 0;    // Hours counter (0-23)

//==============================================================================
// Interrupt Handler
//
// Called by assembly handler in start.S when IRQ occurs.
// Receives IRQ bitmask showing which IRQ(s) fired.
//
// Flow:
//   1. Check if Timer IRQ (bit 0) is set
//   2. Clear the timer interrupt flag (MUST do this!)
//   3. Update clock state
//   4. Return (retirq in assembly restores IRQ mask automatically)
//==============================================================================

void irq_handler(uint32_t irqs) {
    // Check if Timer interrupt (IRQ[0])
    if (irqs & (1 << 0)) {
        // CRITICAL: Clear the interrupt source FIRST
        // Write 1 to UIF bit to clear it
        timer_clear_irq();

        // Update frame counter (0-59)
        frames++;
        if (frames >= 60) {
            frames = 0;

            // Update seconds
            seconds++;
            if (seconds >= 60) {
                seconds = 0;

                // Update minutes
                minutes++;
                if (minutes >= 60) {
                    minutes = 0;

                    // Update hours
                    hours++;
                    if (hours >= 24) {
                        hours = 0;
                    }
                }
            }
        }
    }

    // Note: retirq instruction (in start.S) will automatically:
    //   - Restore PC from q0
    //   - Restore IRQ mask from q1 (re-enables interrupts)
}

//==============================================================================
// Print clock value to UART
//==============================================================================

void print_clock(void) {
    // Format: HH:MM:SS:FF  (FF = frame, 0-59)

    // Hours (00-23)
    uart_putc('0' + (hours / 10));
    uart_putc('0' + (hours % 10));
    uart_putc(':');

    // Minutes (00-59)
    uart_putc('0' + (minutes / 10));
    uart_putc('0' + (minutes % 10));
    uart_putc(':');

    // Seconds (00-59)
    uart_putc('0' + (seconds / 10));
    uart_putc('0' + (seconds % 10));
    uart_putc(':');

    // Frames (00-59, 60 Hz = 1/60 second resolution)
    uart_putc('0' + (frames / 10));
    uart_putc('0' + (frames % 10));

    uart_putc('\r');  // Carriage return (no newline, overwrite same line)
}

//==============================================================================
// Main Function
//==============================================================================

int main(void) {
    // Print banner
    uart_puts("\r\n");
    uart_puts("==========================================\r\n");
    uart_puts("Timer Interrupt Clock Demo\r\n");
    uart_puts("PicoRV32 @ 50 MHz with Timer Peripheral\r\n");
    uart_puts("==========================================\r\n");
    uart_puts("\r\n");
    uart_puts("Configuring timer for 60 Hz interrupts...\r\n");

    // Initialize timer peripheral
    timer_init();

    // Configure timer for 60 Hz (16.67ms period)
    // System clock: 50 MHz
    // Prescaler: 49 (divide by 50) → 1 MHz tick rate
    // Auto-reload: 16666 → 1,000,000 / 16,667 = 59.998 Hz ≈ 60 Hz
    timer_config(49, 16666);

    uart_puts("Timer configured: PSC=49, ARR=16666 (60 Hz)\r\n");
    uart_puts("\r\n");

    // Enable Timer IRQ (IRQ[0])
    // PicoRV32 IRQ mask: 1 = masked (disabled), 0 = unmasked (enabled)
    // We want to ENABLE IRQ[0], so clear bit 0 in mask
    uart_puts("Enabling Timer IRQ[0]...\r\n");
    irq_enable();  // Enable all interrupts (clear all mask bits)

    // Start timer (continuous mode)
    uart_puts("Starting timer...\r\n");
    timer_start();

    uart_puts("\r\n");
    uart_puts("Clock running! (HH:MM:SS:FF format, 60 FPS)\r\n");
    uart_puts("\r\n");

    // Save last frame count to detect changes
    uint32_t last_frames = frames;

    // Main loop: Print clock when frame counter changes
    while (1) {
        // Check if interrupt updated the frame counter
        if (frames != last_frames) {
            last_frames = frames;
            print_clock();
        }

        // Optional: Use waitirq to save power when idle
        // picorv32_waitirq();  // Uncomment to halt CPU between interrupts
    }

    return 0;
}
