//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// interactive.c - Interactive Firmware with Bidirectional Mode Control
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Interactive Firmware with Bidirectional Mode Switching
 * Demonstrates Shell <-> CPU mode switching
 */

#define UART_TX_DATA   (*(volatile unsigned int *)0x80000000)
#define UART_TX_STATUS (*(volatile unsigned int *)0x80000004)
#define UART_RX_DATA   (*(volatile unsigned int *)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int *)0x8000000C)
#define LED_CONTROL    (*(volatile unsigned int *)0x80000010)
#define MODE_CONTROL   (*(volatile unsigned int *)0x80000014)

// UART functions
void putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while busy
    UART_TX_DATA = c;
}

void puts(const char *s) {
    while (*s) {
        if (*s == '\n') putc('\r');
        putc(*s++);
    }
}

int getc_available(void) {
    return UART_RX_STATUS & 1;  // Returns 1 if data available
}

char getc(void) {
    while (!getc_available());  // Wait for data
    return UART_RX_DATA & 0xFF;
}

char getc_nonblocking(void) {
    if (getc_available())
        return UART_RX_DATA & 0xFF;
    return 0;
}

// LED functions
void set_leds(int led1, int led2) {
    LED_CONTROL = (led2 << 1) | led1;
}

// Mode switching
void switch_to_shell(void) {
    MODE_CONTROL = 0;  // 0 = Shell mode
}

void switch_to_app(void) {
    MODE_CONTROL = 1;  // 1 = App mode (should already be set)
}

// Simple delay
void delay(unsigned int count) {
    for (volatile unsigned int i = 0; i < count; i++);
}

int main(void) {
    int led_state = 0;
    int counter = 0;

    puts("\n");
    puts("=================================\n");
    puts("PicoRV32 Interactive Demo\n");
    puts("=================================\n");
    puts("Commands:\n");
    puts("  s - Switch back to SHELL\n");
    puts("  1 - LED1 on\n");
    puts("  2 - LED2 on\n");
    puts("  0 - LEDs off\n");
    puts("  t - Toggle LEDs\n");
    puts("  c - Show counter\n");
    puts("=================================\n");
    puts("> ");

    while (1) {
        // Check for incoming commands (non-blocking)
        char c = getc_nonblocking();

        if (c) {
            putc(c);  // Echo
            putc('\r');
            putc('\n');

            if (c == 's' || c == 'S') {
                puts("Switching to SHELL mode...\n");
                delay(100000);  // Let message finish
                switch_to_shell();
                // If we get here, switch didn't work
                puts("ERROR: Still in APP mode!\n");
            }
            else if (c == '1') {
                set_leds(1, 0);
                puts("LED1 ON\n");
            }
            else if (c == '2') {
                set_leds(0, 1);
                puts("LED2 ON\n");
            }
            else if (c == '0') {
                set_leds(0, 0);
                puts("LEDs OFF\n");
            }
            else if (c == 't' || c == 'T') {
                led_state = !led_state;
                set_leds(led_state, !led_state);
                puts("LEDs toggled\n");
            }
            else if (c == 'c' || c == 'C') {
                puts("Counter: 0x");
                // Print as hex (no division needed)
                char hex[] = "0123456789ABCDEF";
                for (int i = 28; i >= 0; i -= 4) {
                    putc(hex[(counter >> i) & 0xF]);
                }
                counter++;
                puts("\n");
            }
            else {
                puts("Unknown command\n");
            }

            puts("> ");
        }

        // Background task: blink LED1 slowly
        static unsigned int blink_counter = 0;
        if (++blink_counter >= 100000) {
            blink_counter = 0;
            // Don't interfere with user LED commands
        }
    }

    return 0;
}
