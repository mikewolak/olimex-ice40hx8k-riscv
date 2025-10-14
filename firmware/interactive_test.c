//===============================================================================
// Interactive Syscall Test - Menu-driven UART I/O Test
// Waits for user connection before running tests
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

// UART Register Definitions
#define UART_TX_DATA   (*(volatile unsigned int*)0x80000000)
#define UART_TX_STATUS (*(volatile unsigned int*)0x80000004)
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

// External syscall prototypes
extern int _write(int file, char *ptr, int len);
extern int _read(int file, char *ptr, int len);

//==============================================================================
// Helper Functions
//==============================================================================

static int strlen(const char *s) {
    int len = 0;
    while (*s++) len++;
    return len;
}

static void print(const char *s) {
    _write(1, (char*)s, strlen(s));
}

static void println(const char *s) {
    print(s);
    print("\r\n");
}

static void putchar(char c) {
    _write(1, &c, 1);
}

static char getchar_blocking(void) {
    char c;
    _read(0, &c, 1);
    return c;
}

// Check if RX data is available (non-blocking)
static int uart_available(void) {
    return !(UART_RX_STATUS & 0x01);
}

static void print_hex(unsigned int n) {
    const char *digits = "0123456789ABCDEF";
    print("0x");
    for (int i = 28; i >= 0; i -= 4) {
        putchar(digits[(n >> i) & 0xF]);
    }
}

static void print_dec(unsigned int n) {
    char buf[12];
    int i = 0;

    if (n == 0) {
        putchar('0');
        return;
    }

    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }

    while (i > 0) {
        putchar(buf[--i]);
    }
}

//==============================================================================
// Test Functions
//==============================================================================

static void test_string_output(void) {
    println("");
    println("=== String Output Test ===");
    println("This is a test string.");
    println("Line 2: Testing multiple lines");
    println("Line 3: Final line");
    println("Test complete!");
}

static void test_number_output(void) {
    println("");
    println("=== Number Output Test ===");

    print("Decimal numbers: ");
    for (int i = 0; i < 10; i++) {
        print_dec(i);
        putchar(' ');
    }
    println("");

    print("Hexadecimal: ");
    print_hex(0xDEADBEEF);
    println("");

    print("Large number: ");
    print_dec(123456789);
    println("");

    println("Test complete!");
}

static void test_character_echo(void) {
    println("");
    println("=== Character Echo Test ===");
    println("Type characters (press 'q' to quit):");
    println("");

    while (1) {
        char c = getchar_blocking();

        if (c == 'q' || c == 'Q') {
            println("");
            println("Exiting echo test...");
            break;
        }

        // Echo the character back
        print("You typed: ");
        putchar(c);
        print(" (ASCII: ");
        print_dec((unsigned char)c);
        print(")");
        println("");
    }
}

static void test_line_input(void) {
    char buffer[80];
    int idx = 0;

    println("");
    println("=== Line Input Test ===");
    println("Type a line and press Enter:");
    print("> ");

    while (1) {
        char c = getchar_blocking();

        if (c == '\r' || c == '\n') {
            buffer[idx] = '\0';
            println("");
            break;
        }

        if (idx < 79) {
            buffer[idx++] = c;
        }
    }

    print("You entered (");
    print_dec(idx);
    print(" chars): ");
    println(buffer);
}

static void test_performance(void) {
    println("");
    println("=== Performance Test ===");
    println("Sending 1000 characters...");

    unsigned int start = 0;  // TODO: Add timer support

    for (int i = 0; i < 1000; i++) {
        putchar('X');
        if ((i + 1) % 80 == 0) {
            println("");
        }
    }

    println("");
    println("Test complete!");
}

//==============================================================================
// Main Menu
//==============================================================================

static void show_menu(void) {
    println("");
    println("========================================");
    println("  Interactive Syscall Test Menu");
    println("========================================");
    println("1. String Output Test");
    println("2. Number Output Test");
    println("3. Character Echo Test");
    println("4. Line Input Test");
    println("5. Performance Test");
    println("6. Show this menu");
    println("q. Quit (infinite loop)");
    println("========================================");
    print("Select option: ");
}

int main(void) {
    // Banner - will be visible when terminal connects
    println("");
    println("");
    println("========================================");
    println("  Interactive Syscall Test");
    println("  UART I/O via _read/_write syscalls");
    println("========================================");
    println("");
    println("Press any key to start...");

    // Wait for user to press a key (ensures terminal is connected)
    getchar_blocking();

    println("");
    println("Terminal connected!");

    show_menu();

    // Main loop
    while (1) {
        char choice = getchar_blocking();

        // Skip only newline/carriage return (from echoed input)
        if (choice == '\n' || choice == '\r') {
            continue;
        }

        println("");

        switch (choice) {
            case '1':
                test_string_output();
                show_menu();
                break;

            case '2':
                test_number_output();
                show_menu();
                break;

            case '3':
                test_character_echo();
                show_menu();
                break;

            case '4':
                test_line_input();
                show_menu();
                break;

            case '5':
                test_performance();
                show_menu();
                break;

            case '6':
                show_menu();
                break;

            case 'q':
            case 'Q':
                println("Quitting...");
                println("Entering infinite loop (WFI).");
                while (1) {
                    __asm__ volatile ("wfi");
                }
                break;

            default:
                println("Invalid option. Press '6' for menu.");
                break;
        }
    }

    return 0;
}
