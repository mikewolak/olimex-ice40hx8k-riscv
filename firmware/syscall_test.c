//===============================================================================
// Basic Syscall Test - Verify _write works
// Tests UART output without needing full libc
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

// External syscall prototypes
extern int _write(int file, char *ptr, int len);

// Simple string length function
static int strlen(const char *s) {
    int len = 0;
    while (*s++) len++;
    return len;
}

// Simple puts function using _write
static void puts(const char *s) {
    _write(1, (char*)s, strlen(s));
    _write(1, "\r\n", 2);
}

// Simple putchar function
static void putchar(char c) {
    _write(1, &c, 1);
}

// Simple number to string (decimal)
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

    // Print in reverse
    while (i > 0) {
        putchar(buf[--i]);
    }
}

// Simple number to string (hex)
static void print_hex(unsigned int n) {
    const char *digits = "0123456789ABCDEF";
    _write(1, "0x", 2);

    for (int i = 28; i >= 0; i -= 4) {
        putchar(digits[(n >> i) & 0xF]);
    }
}

int main(void) {
    // Test basic string output
    puts("");
    puts("========================================");
    puts("Basic Syscall Test");
    puts("Testing _write() via UART");
    puts("========================================");
    puts("");

    // Test putchar
    _write(1, "Testing putchar: ", 17);
    putchar('H');
    putchar('e');
    putchar('l');
    putchar('l');
    putchar('o');
    putchar('!');
    puts("");
    puts("");

    // Test number printing
    puts("Testing decimal output:");
    _write(1, "  Value: ", 9);
    print_dec(12345);
    puts("");
    puts("");

    // Test hex printing
    puts("Testing hexadecimal output:");
    _write(1, "  Value: ", 9);
    print_hex(0xDEADBEEF);
    puts("");
    puts("");

    // Test loop
    puts("Counting test:");
    for (int i = 0; i < 10; i++) {
        _write(1, "  Count: ", 9);
        print_dec(i);
        puts("");
    }
    puts("");

    puts("========================================");
    puts("Syscall test complete!");
    puts("All _write() calls successful.");
    puts("========================================");

    while (1) {
        // Infinite loop
    }

    return 0;
}
