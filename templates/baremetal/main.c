//===============================================================================
// Bare-Metal Project Template
// Simple hello world with UART I/O
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include "../../lib/peripherals.h"

int main(void) {
    int count = 0;

    uart_puts("\r\n");
    uart_puts("========================================\r\n");
    uart_puts("  Bare-Metal Hello World\r\n");
    uart_puts("  Press any key to continue...\r\n");
    uart_puts("========================================\r\n");
    uart_puts("\r\n");

    while (1) {
        // Print counter
        uart_puts("<");

        // Print number (simple digit-by-digit)
        if (count >= 10) {
            uart_putc('0' + (count / 10));
        }
        uart_putc('0' + (count % 10));

        uart_puts("> Hello, World!\r\n");

        // Wait for any character
        uart_getc();

        // Increment counter
        count++;
    }

    return 0;
}
