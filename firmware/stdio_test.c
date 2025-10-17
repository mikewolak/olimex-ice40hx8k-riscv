//===============================================================================
// Standard I/O Test - printf/scanf via UART
// Tests syscalls implementation with C standard library
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include <stdio.h>
#include <string.h>

int main(void) {
    char name[32];
    int age;
    float height;

    // Test printf
    printf("\n\r========================================\n\r");
    printf("Standard I/O Test via UART\n\r");
    printf("========================================\n\r\n\r");

    printf("Testing printf with different types:\n\r");
    printf("  Integer: %d\n\r", 42);
    printf("  Hex: 0x%08X\n\r", 0xDEADBEEF);
    printf("  String: %s\n\r", "Hello, World!");
    printf("  Character: %c\n\r", 'A');
    printf("\n\r");

    // Test scanf
    printf("Enter your name: ");
    scanf("%s", name);
    printf("Hello, %s!\n\r\n\r", name);

    printf("Enter your age: ");
    scanf("%d", &age);
    printf("You are %d years old.\n\r\n\r", age);

    printf("Enter your height (meters): ");
    scanf("%f", &height);
    printf("Your height is %.2f meters.\n\r\n\r", height);

    // Interactive loop
    printf("========================================\n\r");
    printf("Interactive Echo Test\n\r");
    printf("Type messages and press Enter.\n\r");
    printf("Type 'quit' to exit.\n\r");
    printf("========================================\n\r\n\r");

    while (1) {
        char buffer[80];

        printf("> ");
        scanf("%s", buffer);

        if (strcmp(buffer, "quit") == 0) {
            printf("Goodbye!\n\r");
            break;
        }

        printf("You typed: %s (length=%d)\n\r\n\r", buffer, strlen(buffer));
    }

    return 0;
}
