//==============================================================================
// Minimal Tetris Test - Tests timer interrupts with clock display
//==============================================================================

#include <stdio.h>
#include <stdint.h>
#include "timer_ms.h"

// UART direct access
#define UART_TX_DATA   (*(volatile unsigned int*)0x80000000)
#define UART_TX_STATUS (*(volatile unsigned int*)0x80000004)
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

static void uart_putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while TX busy
    UART_TX_DATA = c;
}

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static char uart_getc(void) {
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

// IRQ Handler - routes timer interrupts
void irq_handler(uint32_t irqs) {
    if (irqs & (1 << 0)) {
        timer_ms_irq_handler();
    }
}

// Print clock: HH:MM:SS:1/60
static void print_clock(void) {
    uint32_t ms = get_millis();
    uint32_t total_seconds = ms / 1000;
    uint32_t hours = total_seconds / 3600;
    uint32_t minutes = (total_seconds % 3600) / 60;
    uint32_t seconds = total_seconds % 60;
    uint32_t sixtieths = (ms % 1000) * 60 / 1000;

    // Move cursor to beginning of line and print
    uart_putc('\r');
    printf("Clock: %02u:%02u:%02u:%02u", hours, minutes, seconds, sixtieths);
}

int main(int argc, char **argv) {
    // Wait for user to press a key before printing
    uart_getc();

    printf("Minimal tetris test starting...\r\n");
    printf("argc=%d, argv=%p\r\n", argc, (void*)argv);
    printf("If you see this, basic initialization works!\r\n");
    printf("\r\nInitializing timer...\r\n");

    timer_ms_init();

    printf("Timer initialized. Clock display running (60Hz updates):\r\n");
    printf("Press any key to exit\r\n\r\n");

    uint32_t last_update = 0;
    while(1) {
        uint32_t now = get_millis();

        // Update clock at ~60Hz (every 16-17ms)
        if (now - last_update >= 16) {
            print_clock();
            last_update = now;
        }

        // Check for keypress to exit
        if (UART_RX_STATUS & 0x01) {
            uart_getc();
            printf("\r\n\r\nClock test complete!\r\n");
            while(1);  // Loop forever
        }
    }

    return 0;
}
