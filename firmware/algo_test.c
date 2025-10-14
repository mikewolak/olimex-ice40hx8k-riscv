//===============================================================================
// Algorithm Verification Test - Known results, 20-30 second runtime
// Tests complex algorithms with verified outputs
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// UART direct access
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

static int getch(void) {
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

//==============================================================================
// Prime Number Generation (Sieve of Eratosthenes)
//==============================================================================

static void test_prime_sieve(void) {
    printf("\r\n=== Prime Number Sieve ===\r\n");
    printf("Finding all primes up to 100,000 (~20 seconds)...\r\n");
    fflush(stdout);

    const int limit = 100000;
    unsigned char *sieve = malloc(limit + 1);
    if (!sieve) {
        printf("FAIL: malloc failed\r\n");
        return;
    }

    // Initialize sieve
    memset(sieve, 1, limit + 1);
    sieve[0] = sieve[1] = 0;

    // Sieve of Eratosthenes
    for (int p = 2; p * p <= limit; p++) {
        if (sieve[p]) {
            for (int i = p * p; i <= limit; i += p) {
                sieve[i] = 0;
            }
        }

        if (p % 1000 == 0) {
            printf("  Processing p=%d...\r\n", p);
            fflush(stdout);
        }
    }

    // Count primes
    int count = 0;
    for (int i = 0; i <= limit; i++) {
        if (sieve[i]) count++;
    }

    printf("\r\nPrimes found: %d\r\n", count);
    printf("Expected: 9592\r\n");
    printf("%s\r\n", (count == 9592) ? "PASS" : "FAIL");

    // Show first 20 primes
    printf("First 20 primes: ");
    int shown = 0;
    for (int i = 0; i <= limit && shown < 20; i++) {
        if (sieve[i]) {
            printf("%d ", i);
            shown++;
        }
    }
    printf("\r\n");

    free(sieve);
}

//==============================================================================
// Fibonacci Numbers (Iterative with modulo to prevent overflow)
//==============================================================================

static void test_fibonacci(void) {
    printf("\r\n=== Fibonacci Sequence ===\r\n");
    printf("Computing first 10,000 Fibonacci numbers (mod 1000000)...\r\n");
    fflush(stdout);

    const int count = 10000;
    const unsigned int mod = 1000000;
    unsigned int fib_prev = 0, fib_curr = 1;

    for (int i = 2; i <= count; i++) {
        unsigned int fib_next = (fib_prev + fib_curr) % mod;
        fib_prev = fib_curr;
        fib_curr = fib_next;

        if (i % 1000 == 0) {
            printf("  n=%d, fib=%u\r\n", i, fib_curr);
            fflush(stdout);
        }
    }

    printf("\r\nF(10000) mod 1000000 = %u\r\n", fib_curr);
    printf("Expected: 366875 (verified locally)\r\n");
    printf("%s\r\n", (fib_curr == 366875) ? "PASS" : "FAIL");
}

//==============================================================================
// QuickSort with Verification
//==============================================================================

static void quicksort(int *arr, int low, int high) {
    if (low < high) {
        // Partition
        int pivot = arr[high];
        int i = low - 1;

        for (int j = low; j < high; j++) {
            if (arr[j] < pivot) {
                i++;
                int temp = arr[i];
                arr[i] = arr[j];
                arr[j] = temp;
            }
        }

        int temp = arr[i + 1];
        arr[i + 1] = arr[high];
        arr[high] = temp;

        int pi = i + 1;

        // Recursively sort
        quicksort(arr, low, pi - 1);
        quicksort(arr, pi + 1, high);
    }
}

static void test_sorting(void) {
    printf("\r\n=== QuickSort Test ===\r\n");
    printf("Sorting 20,000 random numbers (~10 seconds)...\r\n");
    fflush(stdout);

    const int count = 20000;  // Reduced from 50K to fit in 240KB heap
    int *arr = malloc(count * sizeof(int));
    if (!arr) {
        printf("FAIL: malloc failed\r\n");
        return;
    }

    // Generate pseudo-random data
    unsigned int seed = 0xDEADBEEF;
    for (int i = 0; i < count; i++) {
        seed = seed * 1664525 + 1013904223;
        arr[i] = (int)(seed % 100000);
    }

    printf("Generated %d random numbers\r\n", count);
    printf("First 10: ");
    for (int i = 0; i < 10; i++) printf("%d ", arr[i]);
    printf("\r\n");

    // Sort
    printf("Sorting...\r\n");
    fflush(stdout);
    quicksort(arr, 0, count - 1);

    // Verify sorted
    int sorted = 1;
    for (int i = 1; i < count; i++) {
        if (arr[i] < arr[i-1]) {
            sorted = 0;
            printf("FAIL: Not sorted at index %d (%d < %d)\r\n",
                   i, arr[i], arr[i-1]);
            break;
        }
    }

    printf("Sorted first 10: ");
    for (int i = 0; i < 10; i++) printf("%d ", arr[i]);
    printf("\r\n");
    printf("Sorted last 10: ");
    for (int i = count - 10; i < count; i++) printf("%d ", arr[i]);
    printf("\r\n");

    printf("%s\r\n", sorted ? "PASS" : "FAIL");
    free(arr);
}

//==============================================================================
// CRC32 Checksum (Standard polynomial)
//==============================================================================

static unsigned int crc32_table[256];

static void crc32_init(void) {
    for (unsigned int i = 0; i < 256; i++) {
        unsigned int crc = i;
        for (int j = 0; j < 8; j++) {
            crc = (crc & 1) ? ((crc >> 1) ^ 0xEDB88320) : (crc >> 1);
        }
        crc32_table[i] = crc;
    }
}

static unsigned int crc32(const unsigned char *data, size_t len) {
    unsigned int crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    }
    return ~crc;
}

static void test_crc32(void) {
    printf("\r\n=== CRC32 Checksum Test ===\r\n");
    printf("Computing CRC32 of large data block...\r\n");
    fflush(stdout);

    crc32_init();

    // Allocate 100KB test data
    const size_t data_size = 100 * 1024;
    unsigned char *data = malloc(data_size);
    if (!data) {
        printf("FAIL: malloc failed\r\n");
        return;
    }

    // Fill with pattern
    unsigned int seed = 0x12345678;
    for (size_t i = 0; i < data_size; i++) {
        seed = seed * 1664525 + 1013904223;
        data[i] = (unsigned char)(seed & 0xFF);
    }

    // Compute CRC32
    printf("Computing CRC32 of %u bytes...\r\n", (unsigned int)data_size);
    fflush(stdout);
    unsigned int crc = crc32(data, data_size);

    printf("CRC32: 0x%08X\r\n", crc);

    // Known good CRC for this seed/pattern (verified locally)
    printf("Expected: 0xA9C0AAD0\r\n");
    printf("%s\r\n", (crc == 0xA9C0AAD0) ? "PASS" : "FAIL");

    free(data);
}

//==============================================================================
// Matrix Multiplication (floating point)
//==============================================================================

static void test_matrix_multiply(void) {
    printf("\r\n=== Matrix Multiplication Test ===\r\n");
    printf("Multiplying two 50x50 matrices (~5 seconds)...\r\n");
    fflush(stdout);

    const int N = 50;  // Reduced from 100 to fit in 240KB heap (3*50*50*8 = 60KB)

    // Allocate matrices
    double *A = malloc(N * N * sizeof(double));
    double *B = malloc(N * N * sizeof(double));
    double *C = malloc(N * N * sizeof(double));

    if (!A || !B || !C) {
        printf("FAIL: malloc failed\r\n");
        free(A); free(B); free(C);
        return;
    }

    // Initialize A and B with better pattern
    for (int i = 0; i < N * N; i++) {
        A[i] = (double)((i % 10) + 1);        // 1-10 pattern
        B[i] = (double)(((i * 7) % 10) + 1);  // 1-10 pattern (shifted)
    }

    // Matrix multiply: C = A * B
    printf("Computing C = A * B...\r\n");
    fflush(stdout);

    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            double sum = 0.0;
            for (int k = 0; k < N; k++) {
                sum += A[i * N + k] * B[k * N + j];
            }
            C[i * N + j] = sum;
        }

        if ((i + 1) % 10 == 0) {
            printf("  Row %d/%d complete\r\n", i + 1, N);
            fflush(stdout);
        }
    }

    // Verify a known element (C[0][0])
    // For N=50 with (i%10)+1 pattern: C[0][0] = sum(A[0][k]*B[k][0]) for k=0..49
    // A[0..49] = 1,2,3,4,5,6,7,8,9,10,1,2,3,4,5,6,7,8,9,10,... (5 complete cycles)
    // B[0,50,100,...] = B[k*50] = 1,1,1,1,1,... (all 1s because (k*50*7)%10 = 0, +1 = 1)
    // So C[0][0] = (1+2+3+4+5+6+7+8+9+10)*5*1 = 55*5 = 275
    double expected_c00 = 275.0;  // Verified locally for N=50
    printf("\r\nC[0][0] = %.1f\r\n", C[0]);
    printf("Expected: %.1f\r\n", expected_c00);
    printf("%s\r\n", (fabs(C[0] - expected_c00) < 0.1) ? "PASS" : "FAIL");

    free(A);
    free(B);
    free(C);
}

//==============================================================================
// Stress Test - Combined Algorithms
//==============================================================================

static void test_combined_stress(void) {
    printf("\r\n=== Combined Algorithm Stress Test (30 seconds) ===\r\n");
    printf("Running multiple algorithms in sequence...\r\n");
    fflush(stdout);

    // Quick prime check
    printf("\n1. Quick prime sieve (10,000)...\r\n");
    const int limit = 10000;
    unsigned char *sieve = malloc(limit + 1);
    if (sieve) {
        memset(sieve, 1, limit + 1);
        for (int p = 2; p * p <= limit; p++) {
            if (sieve[p]) {
                for (int i = p * p; i <= limit; i += p) sieve[i] = 0;
            }
        }
        int count = 0;
        for (int i = 2; i <= limit; i++) if (sieve[i]) count++;
        printf("   Found %d primes (expected 1229): %s\r\n", count,
               (count == 1229) ? "PASS" : "FAIL");
        free(sieve);
    }

    // Quick sort
    printf("\n2. Sorting 10,000 numbers...\r\n");
    int *arr = malloc(10000 * sizeof(int));
    if (arr) {
        unsigned int seed = 42;
        for (int i = 0; i < 10000; i++) {
            seed = seed * 1664525 + 1013904223;
            arr[i] = seed % 10000;
        }
        quicksort(arr, 0, 9999);
        int sorted = 1;
        for (int i = 1; i < 10000; i++) {
            if (arr[i] < arr[i-1]) { sorted = 0; break; }
        }
        printf("   %s\r\n", sorted ? "PASS" : "FAIL");
        free(arr);
    }

    // Math computations
    printf("\n3. Math computations (10,000 iterations)...\r\n");
    double sum = 0.0;
    for (int i = 1; i <= 10000; i++) {
        double x = (double)i / 100.0;
        sum += sin(x) + cos(x) + sqrt(x) + log(x);
    }
    printf("   Sum = %.6f (computed)\r\n", sum);

    printf("\r\nCombined stress test complete!\r\n");
}

//==============================================================================
// Main Menu
//==============================================================================

static void show_menu(void) {
    printf("\r\n");
    printf("========================================\r\n");
    printf("  Algorithm Verification Suite\r\n");
    printf("========================================\r\n");
    printf("1. Prime sieve (~20s)\r\n");
    printf("2. Fibonacci sequence\r\n");
    printf("3. QuickSort test (~10s)\r\n");
    printf("4. CRC32 checksum\r\n");
    printf("5. Matrix multiply (~5s)\r\n");
    printf("6. Combined stress test (~30s)\r\n");
    printf("7. Run all tests\r\n");
    printf("h. Show this menu\r\n");
    printf("q. Quit\r\n");
    printf("========================================\r\n");
    printf("Select option: ");
    fflush(stdout);
}

int main(void) {
    printf("\r\n\r\n");
    printf("========================================\r\n");
    printf("  Algorithm Verification Suite\r\n");
    printf("  Known results, 20-30s runtime\r\n");
    printf("========================================\r\n");
    printf("\r\n");
    printf("Press any key to start...\r\n");

    getch();

    printf("\r\n");
    printf("Terminal connected!\r\n");

    show_menu();

    while (1) {
        int choice = getch();

        printf("\r\n");

        switch (choice) {
            case '1':
                test_prime_sieve();
                show_menu();
                break;

            case '2':
                test_fibonacci();
                show_menu();
                break;

            case '3':
                test_sorting();
                show_menu();
                break;

            case '4':
                test_crc32();
                show_menu();
                break;

            case '5':
                test_matrix_multiply();
                show_menu();
                break;

            case '6':
                test_combined_stress();
                show_menu();
                break;

            case '7':
                test_prime_sieve();
                test_fibonacci();
                test_sorting();
                test_crc32();
                test_matrix_multiply();
                test_combined_stress();
                printf("\r\n");
                printf("========================================\r\n");
                printf("All algorithm tests complete!\r\n");
                printf("========================================\r\n");
                show_menu();
                break;

            case 'h':
            case 'H':
                show_menu();
                break;

            case 'q':
            case 'Q':
                printf("Quitting...\r\n");
                printf("Entering infinite loop (WFI).\r\n");
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
