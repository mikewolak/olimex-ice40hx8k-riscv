//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// hexedit.c - Interactive Hex Editor with ZMODEM File Transfer
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Interactive Hex Editor Features:
 * - Memory dump (hex and ASCII)
 * - Memory read/write
 * - Memory block copy/move
 * - ZMODEM file receive (auto-start detection)
 * - 128KB receive limit, buffer at heap-140KB
 */

#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "../lib/zmodem/zmodem.h"
#include "../lib/xmodem/xmodem.h"
#include "../lib/intelhex/intelhex.h"
#include "../lib/microrl/microrl.h"

// Hardware addresses
#define UART_TX_DATA   (*(volatile uint32_t *)0x80000000)
#define UART_TX_STATUS (*(volatile uint32_t *)0x80000004)
#define UART_RX_DATA   (*(volatile uint32_t *)0x80000008)
#define UART_RX_STATUS (*(volatile uint32_t *)0x8000000C)

// Timer registers
#define TIMER_BASE          0x80000020
#define TIMER_CR            (*(volatile uint32_t*)(TIMER_BASE + 0x00))
#define TIMER_SR            (*(volatile uint32_t*)(TIMER_BASE + 0x04))
#define TIMER_PSC           (*(volatile uint32_t*)(TIMER_BASE + 0x08))
#define TIMER_ARR           (*(volatile uint32_t*)(TIMER_BASE + 0x0C))
#define TIMER_CNT           (*(volatile uint32_t*)(TIMER_BASE + 0x10))

#define TIMER_CR_ENABLE     (1 << 0)
#define TIMER_CR_ONE_SHOT   (1 << 1)
#define TIMER_SR_UIF        (1 << 0)

// Clock state (updated by interrupt at 60 Hz)
volatile uint32_t clock_frames = 0;   // Frame counter (0-59, increments at 60 Hz)
volatile uint32_t clock_seconds = 0;  // Seconds counter (0-59)
volatile uint32_t clock_minutes = 0;  // Minutes counter (0-59)
volatile uint32_t clock_hours = 0;    // Hours counter (0-23)
volatile uint8_t clock_updated = 0;   // Flag: clock changed

// Millisecond counter for timeouts (updated by interrupt)
volatile uint32_t millis = 0;         // Total milliseconds since start

// Memory layout (based on linker script)
// Physical memory: 0x00000000 - 0x0007FFFF (512KB SRAM)
// Application:     0x00000000 - 0x0003FFFF (256KB for code/data/bss)
// Heap:            End of BSS - 0x00042000
// Stack:           0x00042000 - 0x00080000 (grows down from 0x80000)
#define HEAP_END       0x00042000   // Heap ends here (from linker script)

// ZMODEM configuration
#define ZM_MAX_RECEIVE    (128 * 1024)          // 128KB max transfer
#define ZM_BUFFER_OFFSET  (140 * 1024)          // 140KB before heap end
#define ZM_BUFFER_ADDR    (HEAP_END - ZM_BUFFER_OFFSET)

// ZMODEM auto-start pattern: ZPAD ZPAD ZDLE ZHEX = 0x2A 0x2A 0x18 0x42
// (ZPAD and ZHEX defined in zmodem.h)
#define ZDLE  0x18

//==============================================================================
// PicoRV32 Interrupt Control (custom instructions)
//==============================================================================

// Enable interrupts (clear IRQ mask)
static inline void irq_enable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0" : "=r"(dummy) : "r"(0));
}

// Disable interrupts (set IRQ mask to all 1s)
static inline void irq_disable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0" : "=r"(dummy) : "r"(~0));
}

//==============================================================================
// Forward Declarations
//==============================================================================
void timer_init(void);
uint32_t get_time_ms(void);
void execute_command(const char *cmd);

// Global state for pagination
static uint32_t last_dump_addr = 0;
static uint32_t last_dump_len = 0x100;  // 256 bytes

//==============================================================================
// UART Functions
//==============================================================================

void uart_putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while busy
    UART_TX_DATA = c;
}

void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

int uart_getc_available(void) {
    return UART_RX_STATUS & 1;
}

char uart_getc(void) {
    while (!uart_getc_available());
    return UART_RX_DATA & 0xFF;
}

// Flush UART RX buffer (discard all pending data)
void uart_flush_rx(void) {
    while (uart_getc_available()) {
        (void)UART_RX_DATA;  // Discard byte
    }
}

int getc_timeout(uint32_t timeout_ms) {
    uint32_t start = get_time_ms();
    while ((get_time_ms() - start) < timeout_ms) {
        if (uart_getc_available()) {
            return (int)(UART_RX_DATA & 0xFF);  // Return byte as positive int
        }
    }
    return -1;  // Timeout - returns proper -1 as int
}

//==============================================================================
// Interrupt Handler
//==============================================================================

void irq_handler(uint32_t irqs) {
    // Check if Timer interrupt (IRQ[0])
    if (irqs & (1 << 0)) {
        // CRITICAL: Clear the interrupt source FIRST
        TIMER_SR = TIMER_SR_UIF;  // Write 1 to clear

        // Update millisecond counter (60 Hz = ~16.67ms per tick)
        millis += 17;  // Approximate: 1000ms / 60Hz ≈ 16.67ms

        // Update frame counter (0-59)
        clock_frames++;
        if (clock_frames >= 60) {
            clock_frames = 0;

            // Update seconds
            clock_seconds++;
            if (clock_seconds >= 60) {
                clock_seconds = 0;

                // Update minutes
                clock_minutes++;
                if (clock_minutes >= 60) {
                    clock_minutes = 0;

                    // Update hours
                    clock_hours++;
                    if (clock_hours >= 24) {
                        clock_hours = 0;
                    }
                }
            }
        }

        clock_updated = 1;  // Signal main loop
    }
}

//==============================================================================
// Timer Functions
//==============================================================================

// Initialize timer for 60 Hz interrupts (50MHz system clock)
void timer_init(void) {
    // Stop timer if running
    TIMER_CR = 0x00000000;

    // Clear any pending interrupt
    TIMER_SR = 0x00000001;

    // Configure for 60 Hz (16.67ms period)
    // System clock: 50 MHz
    // Prescaler: 49 (divide by 50) → 1 MHz tick rate
    // Auto-reload: 16666 → 1,000,000 / 16,667 = 59.998 Hz ≈ 60 Hz
    TIMER_PSC = 49;
    TIMER_ARR = 16666;
    TIMER_CNT = 0;

    // Start timer (continuous mode, generates interrupts)
    TIMER_CR = 0x00000001;
}

// Get current time in milliseconds (for ZMODEM timeouts)
uint32_t get_time_ms(void) {
    return millis;
}

//==============================================================================
// Utility Functions
//==============================================================================

// Convert hex digit to value
int hex_to_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

// Print hex byte
void print_hex_byte(uint8_t b) {
    const char hex[] = "0123456789ABCDEF";
    uart_putc(hex[b >> 4]);
    uart_putc(hex[b & 0x0F]);
}

// Print hex word (32-bit)
void print_hex_word(uint32_t w) {
    print_hex_byte((w >> 24) & 0xFF);
    print_hex_byte((w >> 16) & 0xFF);
    print_hex_byte((w >> 8) & 0xFF);
    print_hex_byte(w & 0xFF);
}

// Print decimal number
void print_dec(uint32_t n) {
    char buf[12];
    int i = 0;

    if (n == 0) {
        uart_putc('0');
        return;
    }

    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }

    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

//==============================================================================
// ZMODEM Auto-Start Detection
//==============================================================================

typedef struct {
    uint8_t pattern[4];
    int index;
} zmodem_detector_t;

void zmodem_detector_init(zmodem_detector_t *det) {
    det->pattern[0] = 0x2A;  // ZPAD
    det->pattern[1] = 0x2A;  // ZPAD
    det->pattern[2] = ZDLE;
    det->pattern[3] = 0x42;  // ZHEX
    det->index = 0;
}

int zmodem_detector_feed(zmodem_detector_t *det, char c) {
    if (c == det->pattern[det->index]) {
        det->index++;
        if (det->index == 4) {
            det->index = 0;
            return 1;  // Pattern detected!
        }
    } else {
        det->index = 0;
        // Check if this char starts the pattern
        if (c == det->pattern[0]) {
            det->index = 1;
        }
    }
    return 0;
}

//==============================================================================
// ZMODEM Callbacks for UART
//==============================================================================

int zm_uart_getc(uint32_t timeout_ms) {
    return getc_timeout(timeout_ms);
}

void zm_uart_putc(uint8_t c) {
    uart_putc(c);
}

uint32_t zm_get_time(void) {
    return get_time_ms();
}

//==============================================================================
// Memory Operations
//==============================================================================

void cmd_dump(uint32_t addr, uint32_t len) {
    uint8_t *ptr = (uint8_t *)addr;

    for (uint32_t i = 0; i < len; i += 16) {
        // Print address
        print_hex_word(addr + i);
        uart_puts(": ");

        // Print hex bytes
        for (int j = 0; j < 16 && (i + j) < len; j++) {
            print_hex_byte(ptr[i + j]);
            uart_putc(' ');
        }

        // Padding for short lines
        for (int j = len - i; j < 16 && j >= 0; j++) {
            uart_puts("   ");
        }

        uart_puts(" |");

        // Print ASCII
        for (int j = 0; j < 16 && (i + j) < len; j++) {
            char c = ptr[i + j];
            uart_putc((c >= 32 && c < 127) ? c : '.');
        }

        uart_puts("|\n");
    }

    // Save for pagination
    last_dump_addr = addr;
    last_dump_len = len;
}

void cmd_write(uint32_t addr, uint8_t value) {
    uint8_t *ptr = (uint8_t *)addr;
    *ptr = value;
    uart_puts("Wrote 0x");
    print_hex_byte(value);
    uart_puts(" to 0x");
    print_hex_word(addr);
    uart_puts("\n");
}

void cmd_read(uint32_t addr) {
    uint8_t *ptr = (uint8_t *)addr;
    uart_puts("0x");
    print_hex_word(addr);
    uart_puts(" = 0x");
    print_hex_byte(*ptr);
    uart_puts("\n");
}

void cmd_copy(uint32_t src, uint32_t dst, uint32_t len) {
    uart_puts("Copying ");
    print_dec(len);
    uart_puts(" bytes from 0x");
    print_hex_word(src);
    uart_puts(" to 0x");
    print_hex_word(dst);
    uart_puts("\n");

    // Use memmove for safe overlapping copy
    memmove((void *)dst, (void *)src, len);

    uart_puts("Done.\n");
}

void cmd_fill(uint32_t addr, uint32_t len, uint8_t value) {
    memset((void *)addr, value, len);
    uart_puts("Filled ");
    print_dec(len);
    uart_puts(" bytes at 0x");
    print_hex_word(addr);
    uart_puts(" with 0x");
    print_hex_byte(value);
    uart_puts("\n");
}

//==============================================================================
// ZMODEM Receive
//==============================================================================

void cmd_zmodem_receive(void) {
    // Flush UART RX buffer FIRST (before any messages)
    uart_flush_rx();

    uart_puts("\n");
    uart_puts("=== ZMODEM Receive ===\n");
    uart_puts("Ready to receive. Start ZMODEM send from your terminal NOW.\n");
    uart_puts("(Send Ctrl-X five times from sender to cancel)\n");
    uart_puts("\n");

    // Set up ZMODEM context
    zm_callbacks_t callbacks = {
        .getc = zm_uart_getc,
        .putc = zm_uart_putc,
        .gettime = zm_get_time
    };

    zm_ctx_t ctx;
    zm_init(&ctx, &callbacks);

    // Use buffer at heap-140KB
    uint8_t *buffer = (uint8_t *)ZM_BUFFER_ADDR;
    uint32_t bytes_received = 0;
    char filename[64];

    // Receive file
    zm_error_t err = zm_receive_file(&ctx, buffer, ZM_MAX_RECEIVE, &bytes_received, filename);

    if (err == ZM_OK) {
        uart_puts("\n");
        uart_puts("=== Transfer Complete ===\n");
        uart_puts("Received: ");
        uart_puts(filename);
        uart_puts("\n");
        uart_puts("Size: ");
        print_dec(bytes_received);
        uart_puts(" bytes\n");
        uart_puts("Buffer: 0x");
        print_hex_word(ZM_BUFFER_ADDR);
        uart_puts("\n");
        uart_puts("\n");
        uart_puts("Use 'c <src> <dst> <len>' to copy data elsewhere\n");
    } else if (err == ZM_CANCEL) {
        uart_puts("\n*** Transfer cancelled ***\n");
    } else if (err == ZM_TIMEOUT) {
        uart_puts("\n*** Transfer timeout ***\n");
    } else {
        uart_puts("\n");
        uart_puts("Transfer failed with error: ");
        print_dec(-err);
        uart_puts("\n");
    }
}

void cmd_zmodem_send(uint32_t addr, uint32_t len, const char *filename_arg) {
    // Flush UART RX buffer FIRST (before any messages)
    uart_flush_rx();

    uart_puts("\n");
    uart_puts("=== ZMODEM Send ===\n");
    uart_puts("Sending ");
    print_dec(len);
    uart_puts(" bytes from 0x");
    print_hex_word(addr);
    uart_puts("\n");
    uart_puts("Filename: ");
    uart_puts(filename_arg);
    uart_puts("\n");
    uart_puts("\n");
    uart_puts("Ready to send. Start ZMODEM receive in your terminal NOW.\n");
    uart_puts("\n");

    // Set up ZMODEM context
    zm_callbacks_t callbacks = {
        .getc = zm_uart_getc,
        .putc = zm_uart_putc,
        .gettime = zm_get_time
    };

    zm_ctx_t ctx;
    zm_init(&ctx, &callbacks);

    // Send file
    uint8_t *buffer = (uint8_t *)addr;
    zm_error_t err = zm_send_file(&ctx, buffer, len, filename_arg);

    uart_puts("[DEBUG] zm_send_file returned: ");
    print_dec(-err);
    uart_puts("\n");

    if (err == ZM_OK) {
        uart_puts("\n");
        uart_puts("=== Transfer Complete ===\n");
        uart_puts("Sent ");
        print_dec(len);
        uart_puts(" bytes\n");
    } else if (err == ZM_CANCEL) {
        uart_puts("\n*** Transfer cancelled by receiver ***\n");
    } else if (err == ZM_TIMEOUT) {
        uart_puts("\n*** Transfer timeout ***\n");
    } else {
        uart_puts("\n");
        uart_puts("Transfer failed with error: ");
        print_dec(-err);
        uart_puts("\n");
    }
}

//==============================================================================
// XMODEM Commands
//==============================================================================

void cmd_xmodem_receive(void) {
    // Flush UART RX buffer FIRST (before any messages)
    uart_flush_rx();

    uart_puts("\n");
    uart_puts("=== XMODEM-1K Receive ===\n");
    uart_puts("Ready to receive. Start XMODEM-1K send from your terminal NOW.\n");
    uart_puts("(Press Ctrl-X multiple times to cancel)\n");
    uart_puts("\n");

    // Set up XMODEM context (reuse ZMODEM callbacks - same signature!)
    xmodem_callbacks_t callbacks = {
        .getc = zm_uart_getc,
        .putc = zm_uart_putc,
        .gettime = zm_get_time
    };

    xmodem_ctx_t ctx;
    xmodem_init(&ctx, &callbacks);

    // Use same buffer as ZMODEM at heap-140KB
    uint8_t *buffer = (uint8_t *)ZM_BUFFER_ADDR;
    uint32_t bytes_received = 0;

    // Receive file
    xmodem_error_t err = xmodem_receive(&ctx, buffer, ZM_MAX_RECEIVE, &bytes_received);

    if (err == XMODEM_OK) {
        uart_puts("\n");
        uart_puts("=== Transfer Complete ===\n");
        uart_puts("Received: ");
        print_dec(bytes_received);
        uart_puts(" bytes\n");
        uart_puts("Buffer: 0x");
        print_hex_word(ZM_BUFFER_ADDR);
        uart_puts("\n");
        uart_puts("\n");
        uart_puts("Use 'd <addr> <len>' to view data\n");
        uart_puts("Use 'c <src> <dst> <len>' to copy data elsewhere\n");
    } else if (err == XMODEM_CANCEL) {
        uart_puts("\n*** Transfer cancelled ***\n");
    } else if (err == XMODEM_TIMEOUT) {
        uart_puts("\n*** Transfer timeout ***\n");
    } else if (err == XMODEM_CRC_ERROR) {
        uart_puts("\n*** Too many CRC errors ***\n");
    } else {
        uart_puts("\n");
        uart_puts("Transfer failed with error: ");
        print_dec(-err);
        uart_puts("\n");
    }
}

void cmd_xmodem_send(uint32_t addr, uint32_t len) {
    // Flush UART RX buffer FIRST (before any messages)
    uart_flush_rx();

    uart_puts("\n");
    uart_puts("=== XMODEM-1K Send ===\n");
    uart_puts("Sending ");
    print_dec(len);
    uart_puts(" bytes from 0x");
    print_hex_word(addr);
    uart_puts("\n");
    uart_puts("\n");
    uart_puts("Ready to send. Start XMODEM-1K (CRC) receive in your terminal NOW.\n");
    uart_puts("Waiting for 'C' from receiver (60 sec timeout)...\n");
    uart_puts("\n");

    // Set up XMODEM context (reuse ZMODEM callbacks)
    xmodem_callbacks_t callbacks = {
        .getc = zm_uart_getc,
        .putc = zm_uart_putc,
        .gettime = zm_get_time
    };

    xmodem_ctx_t ctx;
    xmodem_init(&ctx, &callbacks);

    // Send file
    uint8_t *buffer = (uint8_t *)addr;
    xmodem_error_t err = xmodem_send(&ctx, buffer, len);

    if (err == XMODEM_OK) {
        uart_puts("\n");
        uart_puts("=== Transfer Complete ===\n");
        uart_puts("Sent ");
        print_dec(len);
        uart_puts(" bytes\n");
    } else if (err == XMODEM_CANCEL) {
        uart_puts("\n*** Transfer cancelled by receiver ***\n");
    } else if (err == XMODEM_TIMEOUT) {
        uart_puts("\n*** Transfer timeout ***\n");
    } else if (err == XMODEM_CRC_ERROR) {
        uart_puts("\n*** Too many CRC errors ***\n");
    } else {
        uart_puts("\n");
        uart_puts("Transfer failed with error: ");
        print_dec(-err);
        uart_puts("\n");
    }
}

//==============================================================================
// Intel HEX Commands
//==============================================================================

// Intel HEX callbacks
int ihex_uart_getc(void) {
    return (int)uart_getc();  // Blocking read
}

void ihex_uart_putc(uint8_t c) {
    uart_putc(c);
}

void ihex_mem_write(uint32_t addr, const uint8_t *data, uint8_t len) {
    for (uint8_t i = 0; i < len; i++) {
        *((volatile uint8_t *)addr++) = data[i];
    }
}

void ihex_mem_read(uint32_t addr, uint8_t *data, uint8_t len) {
    for (uint8_t i = 0; i < len; i++) {
        data[i] = *((volatile uint8_t *)addr++);
    }
}

void cmd_intelhex_receive(void) {
    uart_puts("\n");
    uart_puts("=== Intel HEX Receive ===\n");
    uart_puts("Paste Intel HEX data into terminal (or send text file).\n");
    uart_puts("Press Ctrl-C to cancel.\n");
    uart_puts("\n");
    uart_puts("Ready to receive Intel HEX...\n");
    uart_puts("\n");

    // Set up callbacks
    ihex_callbacks_t callbacks = {
        .getc = ihex_uart_getc,
        .putc = ihex_uart_putc,
        .write = ihex_mem_write,
        .read = ihex_mem_read
    };

    // Receive Intel HEX
    ihex_error_t err = ihex_receive(&callbacks);

    if (err == IHEX_OK) {
        uart_puts("\n");
        uart_puts("=== Intel HEX Receive Complete ===\n");
        uart_puts("Data successfully written to memory.\n");
    } else {
        uart_puts("\n");
        uart_puts("*** Intel HEX Receive Failed ***\n");
        uart_puts("Error code: ");
        print_dec(-err);
        uart_puts("\n");

        switch (err) {
            case IHEX_ERROR_INVALID_START:
                uart_puts("Line doesn't start with ':'\n");
                break;
            case IHEX_ERROR_CHECKSUM:
                uart_puts("Checksum mismatch\n");
                break;
            case IHEX_ERROR_INVALID_HEX:
                uart_puts("Invalid hex characters\n");
                break;
            default:
                break;
        }
    }
}

void cmd_intelhex_send(uint32_t addr, uint32_t len) {
    uart_puts("\n");
    uart_puts("=== Intel HEX Send ===\n");
    uart_puts("Sending ");
    print_dec(len);
    uart_puts(" bytes from 0x");
    print_hex_word(addr);
    uart_puts("\n");
    uart_puts("\n");
    uart_puts("Capture this output or copy to file:\n");
    uart_puts("========================================\n");

    // Set up callbacks
    ihex_callbacks_t callbacks = {
        .getc = ihex_uart_getc,
        .putc = ihex_uart_putc,
        .write = ihex_mem_write,
        .read = ihex_mem_read
    };

    // Send Intel HEX
    ihex_error_t err = ihex_send(&callbacks, addr, len);

    uart_puts("========================================\n");
    if (err == IHEX_OK) {
        uart_puts("Intel HEX output complete.\n");
    } else {
        uart_puts("*** Intel HEX Send Failed ***\n");
    }
}

//==============================================================================
// MicroRL Callbacks
//==============================================================================

// Output callback for microRL - print string to UART
int microrl_output(microrl_t *mrl, const char *str) {
    (void)mrl;  // Unused
    uart_puts(str);
    return 0;
}

// Execute callback for microRL - rebuild command line and execute
int microrl_execute(microrl_t *mrl, int argc, const char* const *argv) {
    (void)mrl;  // Unused

    if (argc == 0) {
        return 0;  // Empty command
    }

    // Rebuild command line from argc/argv
    char cmdline[128];
    int pos = 0;

    for (int i = 0; i < argc && pos < 127; i++) {
        if (i > 0) {
            cmdline[pos++] = ' ';  // Space between arguments
        }
        const char *arg = argv[i];
        while (*arg && pos < 127) {
            cmdline[pos++] = *arg++;
        }
    }
    cmdline[pos] = '\0';

    // Execute using existing parser
    execute_command(cmdline);

    return 0;
}

//==============================================================================
// Command Parser Utilities
//==============================================================================

// Parse hex number from string
uint32_t parse_hex(const char *str, const char **end) {
    uint32_t val = 0;

    // Skip "0x" prefix if present
    if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
        str += 2;
    }

    while (*str) {
        int digit = hex_to_val(*str);
        if (digit < 0) break;
        val = (val << 4) | digit;
        str++;
    }

    if (end) *end = str;
    return val;
}

void skip_whitespace(const char **str) {
    while (**str == ' ' || **str == '\t') {
        (*str)++;
    }
}

void execute_command(const char *cmd) {
    skip_whitespace(&cmd);

    if (*cmd == '\0') {
        return;  // Empty command
    }

    char op = *cmd++;
    skip_whitespace(&cmd);

    switch (op) {
        case 'd':  // Dump memory
        case 'D': {
            uint32_t addr = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            uint32_t len = parse_hex(cmd, &cmd);
            if (len == 0) len = 256;  // Default 256 bytes
            cmd_dump(addr, len);
            break;
        }

        case 'r':  // Read byte
        case 'R': {
            uint32_t addr = parse_hex(cmd, &cmd);
            cmd_read(addr);
            break;
        }

        case 'w':  // Write byte
        case 'W': {
            uint32_t addr = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            uint8_t value = (uint8_t)parse_hex(cmd, &cmd);
            cmd_write(addr, value);
            break;
        }

        case 'c':  // Copy memory
        case 'C': {
            uint32_t src = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            uint32_t dst = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            uint32_t len = parse_hex(cmd, &cmd);
            if (len > 0) {
                cmd_copy(src, dst, len);
            } else {
                uart_puts("Usage: c <src> <dst> <len>\n");
            }
            break;
        }

        case 'f':  // Fill memory
        case 'F': {
            uint32_t addr = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            uint32_t len = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            uint8_t value = (uint8_t)parse_hex(cmd, &cmd);
            if (len > 0) {
                cmd_fill(addr, len, value);
            } else {
                uart_puts("Usage: f <addr> <len> <value>\n");
            }
            break;
        }

        case 'z':  // ZMODEM receive
        case 'Z': {
            cmd_zmodem_receive();
            break;
        }

        case 's':  // ZMODEM send
        case 'S': {
            uint32_t addr = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            uint32_t len = parse_hex(cmd, &cmd);
            skip_whitespace(&cmd);
            // Get filename (rest of the line)
            const char *filename = cmd;
            if (len > 0 && *filename) {
                cmd_zmodem_send(addr, len, filename);
            } else {
                uart_puts("Usage: s <addr> <len> <filename>\n");
            }
            break;
        }

        case 'x':  // XMODEM receive
        case 'X': {
            // Check if this is 'xr' or 'xs'
            if (*cmd == 'r' || *cmd == 'R') {
                cmd_xmodem_receive();
            } else if (*cmd == 's' || *cmd == 'S') {
                // Parse xmodem send parameters
                cmd++;  // Skip 's'/'S'
                skip_whitespace(&cmd);
                uint32_t addr = parse_hex(cmd, &cmd);
                skip_whitespace(&cmd);
                uint32_t len = parse_hex(cmd, &cmd);
                if (len > 0) {
                    cmd_xmodem_send(addr, len);
                } else {
                    uart_puts("Usage: xs <addr> <len>\n");
                }
            } else {
                uart_puts("XMODEM commands:\n");
                uart_puts("  xr        - XMODEM-1K receive file\n");
                uart_puts("  xs <addr> <len> - XMODEM-1K send file\n");
            }
            break;
        }

        case 'i':  // Intel HEX
        case 'I': {
            // Check if this is 'ihr' or 'ihs'
            if (*cmd == 'h' || *cmd == 'H') {
                cmd++;  // Skip 'h'/'H'
                if (*cmd == 'r' || *cmd == 'R') {
                    cmd_intelhex_receive();
                } else if (*cmd == 's' || *cmd == 'S') {
                    // Parse send parameters
                    cmd++;  // Skip 's'/'S'
                    skip_whitespace(&cmd);
                    uint32_t addr = parse_hex(cmd, &cmd);
                    skip_whitespace(&cmd);
                    uint32_t len = parse_hex(cmd, &cmd);
                    if (len > 0) {
                        cmd_intelhex_send(addr, len);
                    } else {
                        uart_puts("Usage: ihs <addr> <len>\n");
                    }
                } else {
                    uart_puts("Intel HEX commands:\n");
                    uart_puts("  ihr             - Receive Intel HEX\n");
                    uart_puts("  ihs <addr> <len> - Send Intel HEX\n");
                }
            } else {
                uart_puts("Intel HEX commands:\n");
                uart_puts("  ihr             - Receive Intel HEX\n");
                uart_puts("  ihs <addr> <len> - Send Intel HEX\n");
            }
            break;
        }

        case 'h':  // Help
        case 'H':
        case '?': {
            uart_puts("\n");
            uart_puts("Commands:\n");
            uart_puts("  d <addr> [len]           - Dump memory (hex+ASCII)\n");
            uart_puts("  SPACE                    - Page to next 256 bytes\n");
            uart_puts("  r <addr>                 - Read byte\n");
            uart_puts("  w <addr> <value>         - Write byte\n");
            uart_puts("  c <src> <dst> <len>      - Copy memory block\n");
            uart_puts("  f <addr> <len> <val>     - Fill memory\n");
            uart_puts("  z                        - ZMODEM receive file\n");
            uart_puts("  s <addr> <len> <name>    - ZMODEM send file\n");
            uart_puts("  xr                       - XMODEM-1K receive file\n");
            uart_puts("  xs <addr> <len>          - XMODEM-1K send file\n");
            uart_puts("  ihr                      - Intel HEX receive (paste text)\n");
            uart_puts("  ihs <addr> <len>         - Intel HEX send (ASCII output)\n");
            uart_puts("  h or ?                   - This help\n");
            uart_puts("\n");
            uart_puts("Addresses and values in hex (0x optional)\n");
            uart_puts("Default dump: 256 bytes (0x100)\n");
            uart_puts("Transfer buffer at: 0x");
            print_hex_word(ZM_BUFFER_ADDR);
            uart_puts(" (128KB max)\n");
            uart_puts("\n");
            break;
        }

        default:
            uart_puts("Unknown command. Type 'h' for help.\n");
            break;
    }
}

//==============================================================================
// Clock Display
//==============================================================================

void print_clock(void) {
    // Save cursor position
    uart_puts("\033[s");

    // Move to top-right (row 1, col 60)
    uart_puts("\033[1;60H");

    // Print clock: HH:MM:SS:FF
    char buf[16];
    snprintf(buf, sizeof(buf), "[%02u:%02u:%02u:%02u]",
             (unsigned int)clock_hours,
             (unsigned int)clock_minutes,
             (unsigned int)clock_seconds,
             (unsigned int)clock_frames);
    uart_puts(buf);

    // Restore cursor position
    uart_puts("\033[u");
}

//==============================================================================
// Main
//==============================================================================

int main(void) {
    microrl_t mrl;
    zmodem_detector_t zmodem_det;

    // Initialize hardware timer for 60 Hz interrupts
    timer_init();

    // Enable Timer IRQ (IRQ[0])
    uart_puts("Enabling timer interrupts...\n");
    irq_enable();

    // Initialize ZMODEM auto-start detection
    zmodem_detector_init(&zmodem_det);

    // Initialize microRL
    microrl_init(&mrl, microrl_output, microrl_execute);
    microrl_set_prompt(&mrl, "> ");

    uart_puts("\n");
    uart_puts("===========================================\n");
    uart_puts("  PicoRV32 Hex Editor with ZMODEM + microRL\n");
    uart_puts("===========================================\n");
    uart_puts("Type 'h' for help\n");
    uart_puts("Features: Command history (UP/DOWN), line editing\n");
    uart_puts("\n");
    uart_puts("Clock display in top-right corner [HH:MM:SS:FF]\n");
    uart_puts("\n");

    while (1) {
        // Update clock display if timer interrupt fired
        if (clock_updated) {
            clock_updated = 0;
            print_clock();
        }

        // Check for UART input (non-blocking)
        if (!uart_getc_available()) {
            continue;  // No input yet, keep checking clock
        }

        char c = uart_getc();

        // Check for ZMODEM auto-start
        if (zmodem_detector_feed(&zmodem_det, c)) {
            uart_puts("\n\n*** ZMODEM transfer detected! ***\n");
            cmd_zmodem_receive();
            uart_puts("\n");
            microrl_set_prompt(&mrl, "> ");  // Reprint prompt
            continue;
        }

        // Spacebar: page to next 256 bytes (special handling before microRL)
        if (c == ' ' && mrl.cmdlen == 0) {
            // Only handle spacebar if command line is empty
            uart_puts("\n");
            uint32_t next_addr = last_dump_addr + last_dump_len;
            cmd_dump(next_addr, 0x100);
            microrl_set_prompt(&mrl, "> ");  // Reprint prompt
            continue;
        }

        // Feed character to microRL for processing
        microrl_processing_input(&mrl, &c, 1);
    }

    return 0;
}
