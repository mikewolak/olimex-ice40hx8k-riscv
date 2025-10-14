//===============================================================================
// Comprehensive printf/scanf Test - With println comparison
// Tests BOTH printf() AND custom println() functions
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include <stdio.h>
#include <string.h>
#include <math.h>

// UART direct access for menu (no echo, no buffering)
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

// Custom print functions for comparison
extern int _write(int file, char *ptr, int len);

static int custom_strlen(const char *s) {
    int len = 0;
    while (*s++) len++;
    return len;
}

static void println(const char *s) {
    _write(1, (char*)s, custom_strlen(s));
    _write(1, "\r\n", 2);
}

// Direct UART getch - no echo, no buffering (for menu input)
static int getch(void) {
    // Wait for RX data available (bit is 1 when data available)
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

//==============================================================================
// Test Functions
//==============================================================================

static void test_printf_basics(void) {
    println("");
    println("=== printf() Basic Tests ===");

    // String output
    printf("String test: %s\r\n", "Hello, World!");

    // Character output
    printf("Character: %c %c %c\r\n", 'A', 'B', 'C');

    // Integer formatting
    printf("Integers:\r\n");
    printf("  Decimal: %d\r\n", 12345);
    printf("  Negative: %d\r\n", -42);
    printf("  Zero: %d\r\n", 0);
    printf("  Large: %d\r\n", 2147483647);

    // Unsigned integers
    printf("Unsigned:\r\n");
    printf("  %u\r\n", 4294967295U);
    printf("  %u\r\n", 0U);

    // Hexadecimal
    printf("Hexadecimal:\r\n");
    printf("  Lowercase: 0x%x\r\n", 0xdeadbeef);
    printf("  Uppercase: 0x%X\r\n", 0xDEADBEEF);
    printf("  With zeros: 0x%08X\r\n", 0x1234);

    // Octal
    printf("Octal: %o\r\n", 0755);

    // Binary (custom - not standard printf)
    printf("Pointer: %p\r\n", (void*)0x12345678);
}

static void test_printf_float(void) {
    println("");
    println("=== printf() Floating Point Tests ===");

    // Basic floats
    printf("Float: %f\r\n", 3.14159f);
    printf("Double: %f\r\n", 2.71828);

    // Precision control
    printf("Precision tests:\r\n");
    printf("  %.0f\r\n", 3.14159);
    printf("  %.2f\r\n", 3.14159);
    printf("  %.4f\r\n", 3.14159);
    printf("  %.6f\r\n", 3.14159);

    // Scientific notation
    printf("Scientific notation:\r\n");
    printf("  %e\r\n", 1234.5678);
    printf("  %E\r\n", 0.00012345);

    // Automatic format
    printf("Auto format (%%g):\r\n");
    printf("  %g\r\n", 123456.789);
    printf("  %g\r\n", 0.00012345);

    // Special values
    printf("Special values:\r\n");
    printf("  Zero: %f\r\n", 0.0);
    printf("  Negative: %f\r\n", -123.456);
    printf("  Very small: %e\r\n", 0.00000001);
    printf("  Very large: %e\r\n", 123456789.0);
}

static void test_printf_formatting(void) {
    println("");
    println("=== printf() Advanced Formatting ===");

    // Width control
    printf("Width control:\r\n");
    printf("  |%5d|\r\n", 42);
    printf("  |%10s|\r\n", "Hello");
    printf("  |%-10s|\r\n", "Hello");

    // Zero padding
    printf("Zero padding:\r\n");
    printf("  %05d\r\n", 42);
    printf("  %08X\r\n", 0xABCD);

    // Multiple arguments
    printf("Multiple args: %d + %d = %d\r\n", 5, 3, 8);
    printf("Mixed types: %s is %d years old, %.2f meters tall\r\n",
           "Alice", 30, 1.65);

    // Percent sign
    printf("Percent sign: 100%% complete\r\n");
}

static void test_scanf_integers(void) {
    println("");
    println("=== scanf() Integer Input Tests ===");

    int decimal;
    printf("Enter a decimal number: ");
    scanf("%d", &decimal);
    printf("You entered: %d (0x%X)\r\n", decimal, decimal);

    unsigned int hex;
    printf("\r\nEnter a hex number (with 0x prefix): ");
    scanf("%x", &hex);
    printf("You entered: 0x%X (%u decimal)\r\n", hex, hex);

    int oct;
    printf("\r\nEnter an octal number: ");
    scanf("%o", &oct);
    printf("You entered: %o octal (%d decimal)\r\n", oct, oct);
}

static void test_scanf_floats(void) {
    println("");
    println("=== scanf() Floating Point Input Tests ===");

    float f;
    printf("Enter a float: ");
    scanf("%f", &f);
    printf("You entered: %f\r\n", f);
    printf("  Scientific: %e\r\n", f);
    printf("  Compact: %g\r\n", f);

    double d;
    printf("\r\nEnter a double: ");
    scanf("%lf", &d);
    printf("You entered: %.10f\r\n", d);

    // Math operations
    printf("\r\nMath operations on %.2f:\r\n", f);
    printf("  Square: %.2f\r\n", f * f);
    printf("  Square root: %.2f\r\n", sqrt(f));
    printf("  Sin: %.4f\r\n", sin(f));
    printf("  Cos: %.4f\r\n", cos(f));
    printf("  Exp: %.4f\r\n", exp(f));
    printf("  Log: %.4f\r\n", log(f));
}

static void test_scanf_strings(void) {
    println("");
    println("=== scanf() String Input Tests ===");

    char word[80];
    printf("Enter a word (no spaces): ");
    scanf("%s", word);
    printf("You entered: '%s' (length=%d)\r\n", word, strlen(word));

    char buffer[80];
    printf("\r\nEnter a line with spaces: ");
    scanf(" %[^\r\n]", buffer);  // Read until newline
    printf("You entered: '%s'\r\n", buffer);
}

static void test_comparison(void) {
    println("");
    println("=== println() vs printf() Comparison ===");
    println("");

    println("Using println():");
    println("  Simple string output");
    println("  Multiple lines");
    println("  Fast and compact");
    println("");

    printf("Using printf():\r\n");
    printf("  Formatted string: %s\r\n", "with variables");
    printf("  Numbers: %d, 0x%X, %.2f\r\n", 42, 0xDEAD, 3.14);
    printf("  Powerful but larger code\r\n");
    println("");

    println("Both use same _write() syscall!");
    printf("Both go through UART to terminal\r\n");
}

//==============================================================================
// Main Menu
//==============================================================================

static void show_menu(void) {
    println("");
    println("========================================");
    println("  Comprehensive printf/scanf Test");
    println("========================================");
    println("1. printf() - Basic tests");
    println("2. printf() - Floating point");
    println("3. printf() - Advanced formatting");
    println("4. scanf() - Integer input (dec/hex/oct)");
    println("5. scanf() - Float input + math");
    println("6. scanf() - String input");
    println("7. println() vs printf() comparison");
    println("8. Run all printf tests");
    println("9. Run all scanf tests");
    println("h. Show this menu");
    println("q. Quit");
    println("========================================");
    printf("Select option: ");
}

int main(void) {
    // Banner
    println("");
    println("");
    println("========================================");
    println("  Comprehensive I/O Test");
    println("  Testing printf() AND println()");
    println("========================================");
    println("");
    println("Press any key to start...");

    // Wait for keypress (no echo)
    getch();

    println("");
    println("Terminal connected!");
    println("");
    printf("Using newlib %s\r\n", _NEWLIB_VERSION);
    printf("Compiled: %s %s\r\n", __DATE__, __TIME__);

    show_menu();

    // Main loop - use getch() for unbuffered, non-echoed menu input
    while (1) {
        int choice = getch();

        println("");

        switch (choice) {
            case '1':
                test_printf_basics();
                show_menu();
                break;

            case '2':
                test_printf_float();
                show_menu();
                break;

            case '3':
                test_printf_formatting();
                show_menu();
                break;

            case '4':
                test_scanf_integers();
                show_menu();
                break;

            case '5':
                test_scanf_floats();
                show_menu();
                break;

            case '6':
                test_scanf_strings();
                show_menu();
                break;

            case '7':
                test_comparison();
                show_menu();
                break;

            case '8':
                test_printf_basics();
                test_printf_float();
                test_printf_formatting();
                println("");
                println("All printf tests complete!");
                show_menu();
                break;

            case '9':
                test_scanf_integers();
                test_scanf_floats();
                test_scanf_strings();
                println("");
                println("All scanf tests complete!");
                show_menu();
                break;

            case 'h':
            case 'H':
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
                printf("Invalid option: '%c'. Press 'h' for menu.\r\n", choice);
                break;
        }
    }

    return 0;
}
