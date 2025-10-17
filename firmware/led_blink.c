/*
 * LED Blink Test Firmware for PicoRV32
 * Toggles LED1 and LED2 via MMIO at 0x80000010
 */

#include <stdint.h>

// Memory-mapped I/O register addresses
#define MMIO_BASE       0x80000000

#define UART_TX_DATA    (*(volatile uint32_t*)(MMIO_BASE + 0x00))
#define UART_TX_STATUS  (*(volatile uint32_t*)(MMIO_BASE + 0x04))
#define UART_RX_DATA    (*(volatile uint32_t*)(MMIO_BASE + 0x08))
#define UART_RX_STATUS  (*(volatile uint32_t*)(MMIO_BASE + 0x0C))
#define LED_CONTROL     (*(volatile uint32_t*)(MMIO_BASE + 0x10))

// LED control bits
#define LED1 (1 << 0)
#define LED2 (1 << 1)

// Simple delay loop
static void delay(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++) {
        asm volatile ("nop");
    }
}

// UART transmit character
static void uart_putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while TX busy
    UART_TX_DATA = c;
}

// UART transmit string
static void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

// Main entry point
int main(void) {
    // Send startup message
    uart_puts("PicoRV32 LED Blink Test\r\n");
    uart_puts("LED1 and LED2 alternating\r\n");

    // Infinite loop: toggle LEDs
    while (1) {
        // Pattern 1: LED1 on, LED2 off
        LED_CONTROL = LED1;
        uart_putc('1');
        delay(10000);  // ~1 second at 25 MHz

        // Pattern 2: LED1 off, LED2 on
        LED_CONTROL = LED2;
        uart_putc('2');
        delay(10000);

        // Pattern 3: Both LEDs on
        LED_CONTROL = LED1 | LED2;
        uart_putc('3');
        delay(10000);

        // Pattern 4: Both LEDs off
        LED_CONTROL = 0;
        uart_putc('0');
        delay(10000);
    }

    return 0;  // Never reached
}
