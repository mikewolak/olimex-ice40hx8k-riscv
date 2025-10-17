//===============================================================================
// Simple UART Echo Test with Newlib
// Diagnostic test to verify getchar()/putchar() behavior
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include <stdio.h>

int main(void) {
    printf("\r\n\r\n");
    printf("========================================\r\n");
    printf("  UART Echo Test (Newlib)\r\n");
    printf("========================================\r\n");
    printf("\r\n");
    printf("Type characters - they will be echoed back.\r\n");
    printf("Press 'q' to quit.\r\n");
    printf("\r\n");

    while (1) {
        // Read one character
        int c = getchar();

        // Show what we received (ASCII value)
        printf("Received: 0x%02X (%d) = '", c, c);

        // Print the character if printable
        if (c >= 32 && c <= 126) {
            putchar((char)c);
        } else {
            printf("?");
        }
        printf("'\r\n");

        // Check for quit
        if (c == 'q' || c == 'Q') {
            printf("\r\nQuitting...\r\n");
            break;
        }
    }

    printf("Entering infinite loop.\r\n");
    while (1) {
        __asm__ volatile ("wfi");
    }

    return 0;
}
