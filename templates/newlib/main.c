//===============================================================================
// Newlib Project Template
// Simple hello world with printf/scanf
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include <stdio.h>
#include "../../lib/peripherals.h"

// Direct UART getch - no echo, no buffering (for non-echoed input)
static int getch(void) {
    while (!uart_available());
    return uart_getc();
}

int main(void) {
    int count = 0;

    printf("\r\n");
    printf("========================================\r\n");
    printf("  Newlib Hello World\r\n");
    printf("  Press any key to continue...\r\n");
    printf("========================================\r\n");
    printf("\r\n");

    while (1) {
        printf("<%d> Hello, World!\r\n", count);
        fflush(stdout);

        // Wait for any character (no echo)
        getch();

        count++;
    }

    return 0;
}
