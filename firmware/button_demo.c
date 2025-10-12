//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// button_demo.c - Button Input Demonstration Firmware
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Button Demo Firmware
 * Demonstrates button input reading via MMIO register 0x80000018
 * Features: Button-controlled LEDs, button state display, debouncing
 */

#define UART_TX_DATA   (*(volatile unsigned int *)0x80000000)
#define UART_TX_STATUS (*(volatile unsigned int *)0x80000004)
#define UART_RX_DATA   (*(volatile unsigned int *)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int *)0x8000000C)
#define LED_CONTROL    (*(volatile unsigned int *)0x80000010)
#define MODE_CONTROL   (*(volatile unsigned int *)0x80000014)
#define BUTTON_INPUT   (*(volatile unsigned int *)0x80000018)

// Button bits (active-high after synchronization)
#define BUT1_MASK      0x01
#define BUT2_MASK      0x02

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
    return UART_RX_STATUS & 1;
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

// Button functions
unsigned int read_buttons(void) {
    return BUTTON_INPUT & 0x03;  // Bits [1:0]
}

int button1_pressed(void) {
    return (BUTTON_INPUT & BUT1_MASK) ? 1 : 0;
}

int button2_pressed(void) {
    return (BUTTON_INPUT & BUT2_MASK) ? 1 : 0;
}

// Mode switching
void switch_to_shell(void) {
    MODE_CONTROL = 0;  // 0 = Shell mode
}

// Simple delay
void delay(unsigned int count) {
    for (volatile unsigned int i = 0; i < count; i++);
}

// Print hex digit
void print_hex_digit(unsigned int value) {
    char hex[] = "0123456789ABCDEF";
    putc(hex[value & 0xF]);
}

// Print 8-bit hex value
void print_hex8(unsigned int value) {
    print_hex_digit(value >> 4);
    print_hex_digit(value);
}

// Print 32-bit hex value
void print_hex32(unsigned int value) {
    for (int i = 28; i >= 0; i -= 4) {
        print_hex_digit(value >> i);
    }
}

int main(void) {
    unsigned int btn_prev = 0;  // Previous button state for edge detection
    unsigned int counter = 0;
    int mode = 0;  // 0=direct, 1=toggle, 2=count

    puts("\n");
    puts("=================================\n");
    puts("PicoRV32 Button Demo\n");
    puts("=================================\n");
    puts("Hardware: BUT1(K11), BUT2(P13)\n");
    puts("MMIO: 0x80000018 [1:0]\n");
    puts("\n");
    puts("Commands:\n");
    puts("  s - Switch to SHELL mode\n");
    puts("  0 - Direct mode (buttons->LEDs)\n");
    puts("  1 - Toggle mode (press to toggle)\n");
    puts("  2 - Counter mode (show counts)\n");
    puts("  b - Show button state\n");
    puts("=================================\n");
    puts("Mode: Direct (BUT1->LED1, BUT2->LED2)\n");
    puts("> ");

    while (1) {
        // Read current button state
        unsigned int btn_now = read_buttons();

        // Detect button edges (press = 0->1 transition)
        unsigned int btn_press = btn_now & ~btn_prev;

        // Update previous state
        btn_prev = btn_now;

        // Mode-specific behavior
        switch (mode) {
            case 0:  // Direct mode - buttons directly control LEDs
                set_leds((btn_now & BUT1_MASK) ? 1 : 0, (btn_now & BUT2_MASK) ? 1 : 0);
                break;

            case 1: {  // Toggle mode - button press toggles LED
                static int led1_state = 0, led2_state = 0;
                if (btn_press & BUT1_MASK) led1_state = !led1_state;
                if (btn_press & BUT2_MASK) led2_state = !led2_state;
                set_leds(led1_state, led2_state);
                break;
            }

            case 2: {  // Counter mode - display press counts
                static unsigned int but1_count = 0, but2_count = 0;
                if (btn_press & BUT1_MASK) {
                    but1_count++;
                    puts("BUT1: ");
                    print_hex32(but1_count);
                    puts("\n> ");
                    // Blink LED1
                    set_leds(1, 0);
                    delay(50000);
                    set_leds(0, 0);
                }
                if (btn_press & BUT2_MASK) {
                    but2_count++;
                    puts("BUT2: ");
                    print_hex32(but2_count);
                    puts("\n> ");
                    // Blink LED2
                    set_leds(0, 1);
                    delay(50000);
                    set_leds(0, 0);
                }
                break;
            }
        }

        // Check for UART commands (non-blocking)
        char c = getc_nonblocking();

        if (c) {
            putc(c);  // Echo
            putc('\r');
            putc('\n');

            if (c == 's' || c == 'S') {
                puts("Switching to SHELL mode...\n");
                delay(100000);
                switch_to_shell();
                puts("ERROR: Still in APP mode!\n");
            }
            else if (c == '0') {
                mode = 0;
                puts("Mode: Direct (BUT1->LED1, BUT2->LED2)\n");
            }
            else if (c == '1') {
                mode = 1;
                puts("Mode: Toggle (press to toggle LEDs)\n");
            }
            else if (c == '2') {
                mode = 2;
                set_leds(0, 0);  // Clear LEDs
                puts("Mode: Counter (count button presses)\n");
            }
            else if (c == 'b' || c == 'B') {
                unsigned int btn = read_buttons();
                puts("Button State: 0x");
                print_hex8(btn);
                puts(" (BUT1=");
                putc((btn & BUT1_MASK) ? '1' : '0');
                puts(", BUT2=");
                putc((btn & BUT2_MASK) ? '1' : '0');
                puts(")\n");
            }
            else {
                puts("Unknown command\n");
            }

            puts("> ");
        }

        // Small delay to avoid polling too fast
        delay(1000);
    }

    return 0;
}
