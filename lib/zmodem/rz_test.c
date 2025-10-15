//===============================================================================
// ZMODEM Receive Test - Receive file via stdin/stdout for testing
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

int main(void) {
    fprintf(stderr, "Waiting to receive file...\n");

    // Allocate receive buffer (1MB max)
    uint8_t *buffer = malloc(1024 * 1024);
    if (!buffer) {
        fprintf(stderr, "Error: Out of memory\n");
        return 1;
    }

    // Set up ZMODEM context
    zm_callbacks_t callbacks = {
        .getc = stdio_getc,
        .putc = stdio_putc,
        .gettime = get_time_ms
    };

    zm_ctx_t ctx;
    zm_init(&ctx, &callbacks);

    // Receive file
    uint32_t bytes_received;
    char filename[256];
    zm_error_t err = zm_receive_file(&ctx, buffer, 1024*1024, &bytes_received, filename);

    if (err == ZM_OK) {
        fprintf(stderr, "Received: %s (%u bytes)\n", filename, bytes_received);

        // Save to file
        FILE *fp = fopen("received.bin", "wb");
        if (!fp) {
            fprintf(stderr, "Error: Cannot create output file\n");
            free(buffer);
            return 1;
        }

        size_t written = fwrite(buffer, 1, bytes_received, fp);
        fclose(fp);

        if (written != bytes_received) {
            fprintf(stderr, "Error: Failed to write file\n");
            free(buffer);
            return 1;
        }

        fprintf(stderr, "Saved to: received.bin\n");
        free(buffer);
        return 0;
    } else {
        fprintf(stderr, "Transfer failed: %d\n", err);
        free(buffer);
        return 1;
    }
}
