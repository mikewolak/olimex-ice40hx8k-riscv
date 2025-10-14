//===============================================================================
// Heap Memory Test - Comprehensive malloc/free stress test
// Tests heap allocator with patterns inspired by memtest86
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// UART direct access for menu (no echo, no buffering)
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

// Timer peripheral registers (MMIO)
#define TIMER_CR   (*(volatile unsigned int*)0x80000020)  // Control register
#define TIMER_SR   (*(volatile unsigned int*)0x80000024)  // Status register
#define TIMER_PSC  (*(volatile unsigned int*)0x80000028)  // Prescaler
#define TIMER_ARR  (*(volatile unsigned int*)0x8000002C)  // Auto-reload register
#define TIMER_CNT  (*(volatile unsigned int*)0x80000030)  // Counter

// Heap symbols from linker script
extern char __heap_start;
extern char __heap_end;

// Throughput measurement globals
static volatile unsigned int bytes_processed = 0;
static volatile unsigned int seconds_elapsed = 0;
static volatile unsigned int new_second = 0;  // Flag: new second ready to display

// Direct UART getch - no echo, no buffering
static int getch(void) {
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

// Enable CPU interrupts
static inline void irq_enable(void) {
    unsigned int dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, x0, x0" : "=r"(dummy));
}

// Disable CPU interrupts
static inline void irq_disable(void) {
    unsigned int dummy;
    __asm__ volatile (".insn r 0x0B, 6, 2, %0, x0, x0" : "=r"(dummy));
}

// IRQ handler - called at 1 Hz (every 1 second)
// ABSOLUTE MINIMUM - just clear interrupt and set flag
// Do NOT do any math, increment, or processing here!
void irq_handler(void) {
    TIMER_SR = 0x00000001;  // Clear timer interrupt flag (required)
    new_second = 1;          // Signal main loop (single store)
}

//==============================================================================
// Memory Test Patterns
//==============================================================================

static int test_pattern_walking_ones(void *ptr, size_t size) {
    unsigned int *data = (unsigned int*)ptr;
    size_t words = size / sizeof(unsigned int);

    printf("  Walking ones pattern...\r\n");

    // Write walking ones
    for (size_t i = 0; i < words; i++) {
        data[i] = 1U << (i % 32);
    }

    // Verify
    for (size_t i = 0; i < words; i++) {
        if (data[i] != (1U << (i % 32))) {
            printf("  FAIL at offset %u: expected 0x%08X, got 0x%08X\r\n",
                   (unsigned int)i * 4, 1U << (i % 32), data[i]);
            return 0;
        }
    }

    return 1;
}

static int test_pattern_walking_zeros(void *ptr, size_t size) {
    unsigned int *data = (unsigned int*)ptr;
    size_t words = size / sizeof(unsigned int);

    printf("  Walking zeros pattern...\r\n");

    // Write walking zeros
    for (size_t i = 0; i < words; i++) {
        data[i] = ~(1U << (i % 32));
    }

    // Verify
    for (size_t i = 0; i < words; i++) {
        if (data[i] != ~(1U << (i % 32))) {
            printf("  FAIL at offset %u\r\n", (unsigned int)i * 4);
            return 0;
        }
    }

    return 1;
}

static int test_pattern_checkerboard(void *ptr, size_t size) {
    unsigned int *data = (unsigned int*)ptr;
    size_t words = size / sizeof(unsigned int);

    printf("  Checkerboard pattern...\r\n");

    // Write 0xAAAAAAAA and 0x55555555
    for (size_t i = 0; i < words; i++) {
        data[i] = (i & 1) ? 0x55555555 : 0xAAAAAAAA;
    }

    // Verify
    for (size_t i = 0; i < words; i++) {
        unsigned int expected = (i & 1) ? 0x55555555 : 0xAAAAAAAA;
        if (data[i] != expected) {
            printf("  FAIL at offset %u\r\n", (unsigned int)i * 4);
            return 0;
        }
    }

    return 1;
}

static int test_pattern_address_in_address(void *ptr, size_t size) {
    unsigned int *data = (unsigned int*)ptr;
    size_t words = size / sizeof(unsigned int);

    printf("  Address-in-address pattern...\r\n");

    // Write address as data
    for (size_t i = 0; i < words; i++) {
        data[i] = (unsigned int)&data[i];
    }

    // Verify
    for (size_t i = 0; i < words; i++) {
        if (data[i] != (unsigned int)&data[i]) {
            printf("  FAIL at offset %u\r\n", (unsigned int)i * 4);
            return 0;
        }
    }

    return 1;
}

static int test_pattern_random(void *ptr, size_t size) {
    unsigned int *data = (unsigned int*)ptr;
    size_t words = size / sizeof(unsigned int);
    unsigned int seed = 0xDEADBEEF;

    printf("  Random pattern (PRNG)...\r\n");

    // Write pseudo-random data (simple LCG)
    unsigned int rng = seed;
    for (size_t i = 0; i < words; i++) {
        rng = rng * 1664525 + 1013904223;  // LCG parameters
        data[i] = rng;
    }

    // Verify
    rng = seed;
    for (size_t i = 0; i < words; i++) {
        rng = rng * 1664525 + 1013904223;
        if (data[i] != rng) {
            printf("  FAIL at offset %u\r\n", (unsigned int)i * 4);
            return 0;
        }
    }

    return 1;
}

//==============================================================================
// Test Functions
//==============================================================================

static void test_heap_info(void) {
    unsigned int heap_start = (unsigned int)&__heap_start;
    unsigned int heap_end = (unsigned int)&__heap_end;
    unsigned int heap_size = heap_end - heap_start;

    printf("\r\n");
    printf("=== Heap Information ===\r\n");
    printf("Heap start:     0x%08X\r\n", heap_start);
    printf("Heap end:       0x%08X\r\n", heap_end);
    printf("Heap size:      %u bytes (%u KB)\r\n", heap_size, heap_size / 1024);
    printf("Stack region:   0x00042000 - 0x00080000 (248 KB)\r\n");
}

static void test_single_allocation(void) {
    printf("\r\n");
    printf("=== Single Allocation Test ===\r\n");

    size_t sizes[] = {16, 64, 256, 1024, 4096, 16384};

    for (size_t i = 0; i < sizeof(sizes)/sizeof(sizes[0]); i++) {
        printf("Allocating %u bytes... ", (unsigned int)sizes[i]);
        fflush(stdout);

        void *ptr = malloc(sizes[i]);
        if (!ptr) {
            printf("FAIL (malloc returned NULL)\r\n");
            continue;
        }

        // Write and verify
        memset(ptr, 0xAA, sizes[i]);
        int ok = 1;
        for (size_t j = 0; j < sizes[i]; j++) {
            if (((unsigned char*)ptr)[j] != 0xAA) {
                ok = 0;
                break;
            }
        }

        free(ptr);
        printf("%s\r\n", ok ? "PASS" : "FAIL");
    }
}

static void test_multiple_allocations(void) {
    printf("\r\n");
    printf("=== Multiple Allocations Test ===\r\n");

    #define NUM_ALLOCS 10
    void *ptrs[NUM_ALLOCS];

    printf("Allocating %d blocks of 1KB each...\r\n", NUM_ALLOCS);

    for (int i = 0; i < NUM_ALLOCS; i++) {
        ptrs[i] = malloc(1024);
        if (!ptrs[i]) {
            printf("FAIL: malloc returned NULL at block %d\r\n", i);
            for (int j = 0; j < i; j++) free(ptrs[j]);
            return;
        }
        memset(ptrs[i], i & 0xFF, 1024);
    }

    printf("Verifying data...\r\n");
    int ok = 1;
    for (int i = 0; i < NUM_ALLOCS; i++) {
        for (int j = 0; j < 1024; j++) {
            if (((unsigned char*)ptrs[i])[j] != (unsigned char)(i & 0xFF)) {
                printf("FAIL: corruption in block %d\r\n", i);
                ok = 0;
                break;
            }
        }
    }

    printf("Freeing all blocks...\r\n");
    for (int i = 0; i < NUM_ALLOCS; i++) {
        free(ptrs[i]);
    }

    printf("%s\r\n", ok ? "PASS" : "FAIL");
}

static void test_fragmentation(void) {
    printf("\r\n");
    printf("=== Fragmentation Test ===\r\n");

    #define FRAG_ALLOCS 20
    void *ptrs[FRAG_ALLOCS];

    printf("Allocating %d blocks...\r\n", FRAG_ALLOCS);
    for (int i = 0; i < FRAG_ALLOCS; i++) {
        ptrs[i] = malloc(512);
        if (!ptrs[i]) {
            printf("FAIL: malloc at block %d\r\n", i);
            for (int j = 0; j < i; j++) if (ptrs[j]) free(ptrs[j]);
            return;
        }
    }

    printf("Freeing every other block...\r\n");
    for (int i = 0; i < FRAG_ALLOCS; i += 2) {
        free(ptrs[i]);
        ptrs[i] = NULL;
    }

    printf("Re-allocating freed blocks...\r\n");
    for (int i = 0; i < FRAG_ALLOCS; i += 2) {
        ptrs[i] = malloc(512);
        if (!ptrs[i]) {
            printf("FAIL: re-malloc at block %d\r\n", i);
            for (int j = 0; j < FRAG_ALLOCS; j++) if (ptrs[j]) free(ptrs[j]);
            return;
        }
    }

    printf("Freeing all blocks...\r\n");
    for (int i = 0; i < FRAG_ALLOCS; i++) {
        if (ptrs[i]) free(ptrs[i]);
    }

    printf("PASS\r\n");
}

static void test_memory_patterns(void) {
    printf("\r\n");
    printf("=== Memory Pattern Test ===\r\n");

    // Calculate available heap space
    unsigned int heap_start = (unsigned int)&__heap_start;
    unsigned int heap_end = (unsigned int)&__heap_end;
    unsigned int heap_total = heap_end - heap_start;

    printf("Total heap space: %u bytes (%u KB)\r\n", heap_total, heap_total / 1024);

    // Try to allocate maximum available heap
    // Start with 90% of total, reduce if fails
    size_t test_size = (heap_total * 9) / 10;
    void *ptr = NULL;

    printf("Attempting to allocate maximum available heap...\r\n");
    fflush(stdout);

    while (test_size > 4096 && !ptr) {
        ptr = malloc(test_size);
        if (!ptr) {
            test_size = (test_size * 9) / 10;  // Reduce by 10%
        }
    }

    if (!ptr) {
        printf("FAIL: Unable to allocate even 4KB of heap\r\n");
        return;
    }

    printf("Allocated %u bytes (%u KB, %.1f%% of heap)\r\n",
           (unsigned int)test_size,
           (unsigned int)(test_size / 1024),
           (float)test_size * 100.0 / heap_total);
    printf("Testing entire allocated region with 5 patterns...\r\n");
    fflush(stdout);

    int all_pass = 1;
    all_pass &= test_pattern_walking_ones(ptr, test_size);
    all_pass &= test_pattern_walking_zeros(ptr, test_size);
    all_pass &= test_pattern_checkerboard(ptr, test_size);
    all_pass &= test_pattern_address_in_address(ptr, test_size);
    all_pass &= test_pattern_random(ptr, test_size);

    free(ptr);
    printf("\r\n");
    printf("%s\r\n", all_pass ? "ALL PATTERNS PASS" : "SOME PATTERNS FAILED");
}

static void test_stress_allocations(void) {
    printf("\r\n");
    printf("=== Stress Test (30 seconds) ===\r\n");
    printf("Rapid malloc/free cycles with verification...\r\n");
    printf("This will take ~30 seconds...\r\n");
    fflush(stdout);

    unsigned int iterations = 10000;
    unsigned int seed = 0x12345678;
    int failures = 0;

    for (unsigned int i = 0; i < iterations; i++) {
        // Pseudo-random size (100 - 2000 bytes)
        seed = seed * 1664525 + 1013904223;
        size_t size = 100 + (seed % 1900);

        void *ptr = malloc(size);
        if (!ptr) {
            failures++;
            continue;
        }

        // Fill with pattern
        unsigned char pattern = (unsigned char)(seed & 0xFF);
        memset(ptr, pattern, size);

        // Verify
        for (size_t j = 0; j < size; j++) {
            if (((unsigned char*)ptr)[j] != pattern) {
                failures++;
                break;
            }
        }

        free(ptr);

        // Progress indicator every 1000 iterations
        if ((i + 1) % 1000 == 0) {
            printf("  %u iterations complete...\r\n", i + 1);
            fflush(stdout);
        }
    }

    printf("\r\n");
    printf("Completed %u iterations\r\n", iterations);
    printf("Failures: %u\r\n", failures);
    printf("%s\r\n", failures == 0 ? "PASS" : "FAIL");
}

static void test_throughput(void) {
    printf("\r\n");
    printf("=== Memory Throughput Test ===\r\n");
    printf("Real-time throughput measurement with timer interrupts\r\n");
    printf("Uses 32-bit word copies for maximum performance\r\n");
    printf("Press 's' to start, 'q' to quit\r\n");
    fflush(stdout);

    // Wait for 's' to start
    while (1) {
        int ch = getch();
        if (ch == 's' || ch == 'S') break;
        if (ch == 'q' || ch == 'Q') return;
    }

    printf("\r\nStarting throughput test...\r\n");
    printf("Continuous 32-bit memory copy with 1-second samples\r\n");
    printf("Press any key to stop\r\n\r\n");
    fflush(stdout);

    // Allocate test buffers (64KB each, word-aligned)
    const size_t buf_size = 65536;
    unsigned int *src = (unsigned int*)malloc(buf_size);
    unsigned int *dst = (unsigned int*)malloc(buf_size);

    if (!src || !dst) {
        printf("FAIL: malloc failed\r\n");
        free(src);
        free(dst);
        return;
    }

    // Fill source with pattern (32-bit writes)
    size_t words = buf_size / sizeof(unsigned int);
    for (size_t i = 0; i < words; i++) {
        src[i] = 0xAAAAAAAA;
    }

    // Setup timer for 1 Hz interrupts (every 1 second)
    // Clock = 50 MHz
    // PSC = 49 → divide by 50 → 1 MHz tick
    // ARR = 999999 → 1000000 ticks → 1 Hz IRQ → 1 second period
    TIMER_PSC = 49;
    TIMER_ARR = 999999;

    // Reset counters
    bytes_processed = 0;
    seconds_elapsed = 0;
    new_second = 0;
    unsigned int last_bytes = 0;

    // Enable interrupts and timer
    irq_enable();
    TIMER_CR = 0x00000001;

    // Continuous 32-bit memory copy until keypress
    while (!(UART_RX_STATUS & 0x01)) {
        // 32-bit word copy (much faster than byte-by-byte)
        for (size_t i = 0; i < words; i++) {
            dst[i] = src[i];
        }
        bytes_processed += buf_size;

        // Check if a new second has elapsed (set by IRQ handler)
        if (new_second) {
            new_second = 0;  // Clear flag
            seconds_elapsed++;  // Do counter increment here, not in IRQ

            // Calculate bytes in last second
            unsigned int bytes_this_sec = bytes_processed - last_bytes;
            last_bytes = bytes_processed;

            // Auto-select units
            if (bytes_this_sec >= 1000000) {
                printf("  [%2us] Throughput: %u.%02u MB/s (%u MB total)\r\n",
                       seconds_elapsed,
                       bytes_this_sec / 1000000,
                       (bytes_this_sec % 1000000) / 10000,
                       bytes_processed / (1024 * 1024));
            } else if (bytes_this_sec >= 1000) {
                printf("  [%2us] Throughput: %u.%02u KB/s (%u KB total)\r\n",
                       seconds_elapsed,
                       bytes_this_sec / 1000,
                       (bytes_this_sec % 1000) / 10,
                       bytes_processed / 1024);
            } else {
                printf("  [%2us] Throughput: %u bytes/s (%u bytes total)\r\n",
                       seconds_elapsed,
                       bytes_this_sec,
                       bytes_processed);
            }
            fflush(stdout);
        }
    }

    // Disable timer (no more interrupts)
    TIMER_CR = 0x00000000;

    // Clear any pending timer interrupt
    TIMER_SR = 0x00000001;

    // Disable CPU interrupts
    irq_disable();

    // Consume the keypress
    (void)getch();

    // Drain any extra characters from UART buffer
    while (UART_RX_STATUS & 0x01) {
        (void)(UART_RX_DATA);
    }

    printf("\r\n");
    printf("Test stopped.\r\n");
    printf("Total time: %u seconds\r\n", seconds_elapsed);
    printf("Total bytes: %u (%u MB, %u KB)\r\n",
           bytes_processed,
           bytes_processed / (1024 * 1024),
           (bytes_processed / 1024) % 1024);

    if (seconds_elapsed > 0) {
        unsigned int avg_throughput = bytes_processed / seconds_elapsed;
        printf("Average throughput: %u.%02u MB/s\r\n",
               avg_throughput / 1000000,
               (avg_throughput % 1000000) / 10000);
    }

    free(src);
    free(dst);
}

//==============================================================================
// Main Menu
//==============================================================================

static void show_menu(void) {
    printf("\r\n");
    printf("========================================\r\n");
    printf("  Heap Memory Test Suite\r\n");
    printf("========================================\r\n");
    printf("1. Heap information\r\n");
    printf("2. Single allocation test\r\n");
    printf("3. Multiple allocations test\r\n");
    printf("4. Fragmentation test\r\n");
    printf("5. Memory pattern test\r\n");
    printf("6. Stress test (30 seconds)\r\n");
    printf("7. Throughput test (real-time)\r\n");
    printf("8. Run all tests\r\n");
    printf("h. Show this menu\r\n");
    printf("q. Quit\r\n");
    printf("========================================\r\n");
    printf("Select option: ");
    fflush(stdout);
}

int main(void) {
    printf("\r\n\r\n");
    printf("========================================\r\n");
    printf("  Heap Memory Test Suite\r\n");
    printf("  malloc/free stress testing\r\n");
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
                test_heap_info();
                show_menu();
                break;

            case '2':
                test_single_allocation();
                show_menu();
                break;

            case '3':
                test_multiple_allocations();
                show_menu();
                break;

            case '4':
                test_fragmentation();
                show_menu();
                break;

            case '5':
                test_memory_patterns();
                show_menu();
                break;

            case '6':
                test_stress_allocations();
                show_menu();
                break;

            case '7':
                test_throughput();
                show_menu();
                break;

            case '8':
                test_heap_info();
                test_single_allocation();
                test_multiple_allocations();
                test_fragmentation();
                test_memory_patterns();
                test_stress_allocations();
                printf("\r\n");
                printf("Note: Throughput test skipped (interactive)\r\n");
                printf("========================================\r\n");
                printf("All heap tests complete!\r\n");
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
