//==============================================================================
// Minimal Tetris Test - Just prints and exits
//==============================================================================

#include <stdio.h>

// UART direct access for getchar
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

static char uart_getc(void) {
    // Wait for RX data available
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

int main(int argc, char **argv) {
    // Wait for user to press a key before printing
    uart_getc();

    printf("Minimal tetris test starting...\n");
    printf("argc=%d, argv=%p\n", argc, (void*)argv);
    printf("If you see this, basic initialization works!\n");

    while(1);  // Loop forever
    return 0;
}
