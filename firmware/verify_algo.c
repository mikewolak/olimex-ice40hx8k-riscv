//===============================================================================
// Local verification of algorithm expected values
// Compile: gcc verify_algo.c -o verify_algo -lm
//===============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Fibonacci test
void verify_fibonacci() {
    printf("=== Verifying Fibonacci ===\n");
    const int count = 10000;
    const unsigned int mod = 1000000;
    unsigned int fib_prev = 0, fib_curr = 1;

    printf("F(0) = %u\n", fib_prev);
    printf("F(1) = %u\n", fib_curr);

    for (int i = 2; i <= count; i++) {
        unsigned int fib_next = (fib_prev + fib_curr) % mod;
        fib_prev = fib_curr;
        fib_curr = fib_next;

        if (i <= 10 || i == count) {
            printf("F(%d) mod 1000000 = %u\n", i, fib_curr);
        }
    }

    printf("\nF(10000) mod 1000000 = %u\n", fib_curr);
    printf("Expected in code: 366875 (FIXED)\n");
    printf("Match: %s\n\n", (fib_curr == 366875) ? "YES" : "NO");
}

// CRC32 test
static unsigned int crc32_table[256];

void crc32_init() {
    for (unsigned int i = 0; i < 256; i++) {
        unsigned int crc = i;
        for (int j = 0; j < 8; j++) {
            crc = (crc & 1) ? ((crc >> 1) ^ 0xEDB88320) : (crc >> 1);
        }
        crc32_table[i] = crc;
    }
}

unsigned int crc32(const unsigned char *data, size_t len) {
    unsigned int crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    }
    return ~crc;
}

void verify_crc32() {
    printf("=== Verifying CRC32 ===\n");
    crc32_init();

    const size_t data_size = 100 * 1024;
    unsigned char *data = malloc(data_size);
    if (!data) {
        printf("malloc failed\n");
        return;
    }

    // Same pattern as embedded code
    unsigned int seed = 0x12345678;
    for (size_t i = 0; i < data_size; i++) {
        seed = seed * 1664525 + 1013904223;
        data[i] = (unsigned char)(seed & 0xFF);
    }

    unsigned int computed_crc = crc32(data, data_size);
    printf("CRC32: 0x%08X\n", computed_crc);
    printf("Expected in code: 0xA9C0AAD0 (FIXED)\n");
    printf("Match: %s\n\n", (computed_crc == 0xA9C0AAD0) ? "YES" : "NO");

    free(data);
}

// Matrix multiply test
void verify_matrix() {
    printf("=== Verifying Matrix Multiply ===\n");
    const int N = 50;  // Updated to match new embedded code

    double *A = malloc(N * N * sizeof(double));
    double *B = malloc(N * N * sizeof(double));
    double *C = malloc(N * N * sizeof(double));

    if (!A || !B || !C) {
        printf("malloc failed\n");
        free(A); free(B); free(C);
        return;
    }

    // Same initialization as embedded code (updated pattern)
    for (int i = 0; i < N * N; i++) {
        A[i] = (double)((i % 10) + 1);
        B[i] = (double)(((i * 7) % 10) + 1);
    }

    // Matrix multiply: C = A * B
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            double sum = 0.0;
            for (int k = 0; k < N; k++) {
                sum += A[i * N + k] * B[k * N + j];
            }
            C[i * N + j] = sum;
        }
    }

    printf("C[0][0] = %.1f\n", C[0]);
    printf("Expected in code: 275.0\n");
    printf("Match: %s\n\n", (fabs(C[0] - 275.0) < 0.1) ? "YES" : "NO");

    free(A);
    free(B);
    free(C);
}

int main() {
    printf("Algorithm Verification (Local Machine)\n");
    printf("=======================================\n\n");

    verify_fibonacci();
    verify_crc32();
    verify_matrix();

    printf("Done!\n");
    return 0;
}
