//===============================================================================
// ZMODEM Send Test - Send file via stdin/stdout for testing
//
// Usage: ./sz_test <filename> | ./rz_test
//===============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include "zmodem.h"

//==============================================================================
// Callbacks for stdio (instead of UART)
//==============================================================================

static uint32_t get_time_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (tv.tv_sec * 1000) + (tv.tv_usec / 1000);
}

static int stdio_getc(uint32_t timeout_ms) {
    uint32_t start = get_time_ms();

    fd_set readfds;
    struct timeval tv;

    while (1) {
        FD_ZERO(&readfds);
        FD_SET(STDIN_FILENO, &readfds);

        uint32_t elapsed = get_time_ms() - start;
        if (elapsed >= timeout_ms) {
            return -1;  // Timeout
        }

        uint32_t remaining = timeout_ms - elapsed;
        tv.tv_sec = remaining / 1000;
        tv.tv_usec = (remaining % 1000) * 1000;

        int ret = select(STDIN_FILENO + 1, &readfds, NULL, NULL, &tv);
        if (ret > 0) {
            uint8_t byte;
            ssize_t n = read(STDIN_FILENO, &byte, 1);
            if (n <= 0) return -1;
            if (byte != '\n' && byte != '\r') {
                fprintf(stderr, "[GETC] %02X ('%c')\n", byte, (byte >= 32 && byte < 127) ? byte : '.');
            }
            return byte;
        } else if (ret == 0) {
            return -1;  // Timeout
        }
    }
}

static void stdio_putc(uint8_t c) {
    write(STDOUT_FILENO, &c, 1);
}

//==============================================================================
// Main
//==============================================================================

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        fprintf(stderr, "Example: %s test.bin | ./rz_test\n", argv[0]);
        return 1;
    }

    // Open input file
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) {
        fprintf(stderr, "Error: Cannot open file: %s\n", argv[1]);
        return 1;
    }

    // Get file size
    fseek(fp, 0, SEEK_END);
    long file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if (file_size > 1024*1024) {  // Limit to 1MB for testing
        fprintf(stderr, "Error: File too large (max 1MB)\n");
        fclose(fp);
        return 1;
    }

    // Read entire file into memory
    uint8_t *data = malloc(file_size);
    if (!data) {
        fprintf(stderr, "Error: Out of memory\n");
        fclose(fp);
        return 1;
    }

    size_t bytes_read = fread(data, 1, file_size, fp);
    fclose(fp);

    if (bytes_read != (size_t)file_size) {
        fprintf(stderr, "Error: Failed to read file\n");
        free(data);
        return 1;
    }

    fprintf(stderr, "Sending: %s (%ld bytes)\n", argv[1], file_size);

    // Set up ZMODEM context
    zm_callbacks_t callbacks = {
        .getc = stdio_getc,
        .putc = stdio_putc,
        .gettime = get_time_ms
    };

    zm_ctx_t ctx;
    zm_init(&ctx, &callbacks);

    // Send file
    zm_error_t err = zm_send_file(&ctx, data, file_size, argv[1]);

    free(data);

    if (err == ZM_OK) {
        fprintf(stderr, "Transfer complete!\n");
        return 0;
    } else {
        fprintf(stderr, "Transfer failed: %d\n", err);
        return 1;
    }
}
