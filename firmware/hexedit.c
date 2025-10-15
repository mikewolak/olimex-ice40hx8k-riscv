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
#include "../lib/zmodem/zmodem.h"

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
// Forward Declarations
//==============================================================================
void timer_init(void);
uint32_t get_time_ms(void);

// Global state for pagination
static uint32_t last_dump_addr = 0;
static uint32_t last_dump_len = 0x100;  // 256 bytes

//==============================================================================
// UART Functions
//==============================================================================

void putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while busy
    UART_TX_DATA = c;
}

void puts(const char *s) {
    while (*s) {
        if (*s == '\n') putc('\r');
        putc(*s++);
    }
}

int getc_available(void) {
    return UART_RX_STATUS & 1;
}

char getc(void) {
    while (!getc_available());
    return UART_RX_DATA & 0xFF;
}

char getc_timeout(uint32_t timeout_ms) {
    uint32_t start = get_time_ms();
    while ((get_time_ms() - start) < timeout_ms) {
        if (getc_available()) {
            return UART_RX_DATA & 0xFF;
        }
    }
    return -1;  // Timeout
}

//==============================================================================
// Timer Functions
//==============================================================================

// Initialize timer for 1ms ticks (assumes 12MHz clock)
void timer_init(void) {
    TIMER_CR = 0;  // Disable timer
    TIMER_PSC = 11999;  // 12MHz / (11999+1) = 1000 Hz = 1ms ticks
    TIMER_ARR = 0xFFFFFFFF;  // Max count (free-running)
    TIMER_CNT = 0;  // Reset counter
    TIMER_CR = TIMER_CR_ENABLE;  // Enable timer
}

// Get current time in milliseconds
uint32_t get_time_ms(void) {
    return TIMER_CNT;  // Timer counts in milliseconds
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
    putc(hex[b >> 4]);
    putc(hex[b & 0x0F]);
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
        putc('0');
        return;
    }

    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }

    while (i > 0) {
        putc(buf[--i]);
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
    putc(c);
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
        puts(": ");

        // Print hex bytes
        for (int j = 0; j < 16 && (i + j) < len; j++) {
            print_hex_byte(ptr[i + j]);
            putc(' ');
        }

        // Padding for short lines
        for (int j = len - i; j < 16 && j >= 0; j++) {
            puts("   ");
        }

        puts(" |");

        // Print ASCII
        for (int j = 0; j < 16 && (i + j) < len; j++) {
            char c = ptr[i + j];
            putc((c >= 32 && c < 127) ? c : '.');
        }

        puts("|\n");
    }

    // Save for pagination
    last_dump_addr = addr;
    last_dump_len = len;
}

void cmd_write(uint32_t addr, uint8_t value) {
    uint8_t *ptr = (uint8_t *)addr;
    *ptr = value;
    puts("Wrote 0x");
    print_hex_byte(value);
    puts(" to 0x");
    print_hex_word(addr);
    puts("\n");
}

void cmd_read(uint32_t addr) {
    uint8_t *ptr = (uint8_t *)addr;
    puts("0x");
    print_hex_word(addr);
    puts(" = 0x");
    print_hex_byte(*ptr);
    puts("\n");
}

void cmd_copy(uint32_t src, uint32_t dst, uint32_t len) {
    puts("Copying ");
    print_dec(len);
    puts(" bytes from 0x");
    print_hex_word(src);
    puts(" to 0x");
    print_hex_word(dst);
    puts("\n");

    // Use memmove for safe overlapping copy
    memmove((void *)dst, (void *)src, len);

    puts("Done.\n");
}

void cmd_fill(uint32_t addr, uint32_t len, uint8_t value) {
    memset((void *)addr, value, len);
    puts("Filled ");
    print_dec(len);
    puts(" bytes at 0x");
    print_hex_word(addr);
    puts(" with 0x");
    print_hex_byte(value);
    puts("\n");
}

//==============================================================================
// ZMODEM Receive
//==============================================================================

void cmd_zmodem_receive(void) {
    puts("\n");
    puts("=== ZMODEM Receive ===\n");
    puts("Waiting for sender to start transfer...\n");
    puts("(Send Ctrl-X five times from sender to cancel)\n");
    puts("\n");

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
        puts("\n");
        puts("=== Transfer Complete ===\n");
        puts("Received: ");
        puts(filename);
        puts("\n");
        puts("Size: ");
        print_dec(bytes_received);
        puts(" bytes\n");
        puts("Buffer: 0x");
        print_hex_word(ZM_BUFFER_ADDR);
        puts("\n");
        puts("\n");
        puts("Use 'c <src> <dst> <len>' to copy data elsewhere\n");
    } else if (err == ZM_CANCEL) {
        puts("\n*** Transfer cancelled ***\n");
    } else if (err == ZM_TIMEOUT) {
        puts("\n*** Transfer timeout ***\n");
    } else {
        puts("\n");
        puts("Transfer failed with error: ");
        print_dec(-err);
        puts("\n");
    }
}

void cmd_zmodem_send(uint32_t addr, uint32_t len, const char *filename_arg) {
    puts("\n");
    puts("=== ZMODEM Send ===\n");
    puts("Sending ");
    print_dec(len);
    puts(" bytes from 0x");
    print_hex_word(addr);
    puts("\n");
    puts("Filename: ");
    puts(filename_arg);
    puts("\n");
    puts("\n");

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

    if (err == ZM_OK) {
        puts("\n");
        puts("=== Transfer Complete ===\n");
        puts("Sent ");
        print_dec(len);
        puts(" bytes\n");
    } else if (err == ZM_CANCEL) {
        puts("\n*** Transfer cancelled by receiver ***\n");
    } else if (err == ZM_TIMEOUT) {
        puts("\n*** Transfer timeout ***\n");
    } else {
        puts("\n");
        puts("Transfer failed with error: ");
        print_dec(-err);
        puts("\n");
    }
}

//==============================================================================
// Command Parser
//==============================================================================

typedef struct {
    char buffer[128];
    int pos;
} cmd_buffer_t;

void cmd_buffer_init(cmd_buffer_t *cmd) {
    cmd->pos = 0;
    cmd->buffer[0] = '\0';
}

void cmd_buffer_add(cmd_buffer_t *cmd, char c) {
    if (c == '\r' || c == '\n') {
        cmd->buffer[cmd->pos] = '\0';
    } else if (c == '\b' || c == 127) {  // Backspace
        if (cmd->pos > 0) {
            cmd->pos--;
            putc('\b');
            putc(' ');
            putc('\b');
        }
    } else if (cmd->pos < 127) {
        cmd->buffer[cmd->pos++] = c;
        putc(c);  // Echo
    }
}

int cmd_buffer_ready(cmd_buffer_t *cmd, char c) {
    (void)cmd;  // Unused parameter
    return (c == '\r' || c == '\n');
}

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
                puts("Usage: c <src> <dst> <len>\n");
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
                puts("Usage: f <addr> <len> <value>\n");
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
                puts("Usage: s <addr> <len> <filename>\n");
            }
            break;
        }

        case 'h':  // Help
        case 'H':
        case '?': {
            puts("\n");
            puts("Commands:\n");
            puts("  d <addr> [len]           - Dump memory (hex+ASCII)\n");
            puts("  SPACE                    - Page to next 256 bytes\n");
            puts("  r <addr>                 - Read byte\n");
            puts("  w <addr> <value>         - Write byte\n");
            puts("  c <src> <dst> <len>      - Copy memory block\n");
            puts("  f <addr> <len> <val>     - Fill memory\n");
            puts("  z                        - ZMODEM receive file\n");
            puts("  s <addr> <len> <name>    - ZMODEM send file\n");
            puts("  h or ?                   - This help\n");
            puts("\n");
            puts("Addresses and values in hex (0x optional)\n");
            puts("Default dump: 256 bytes (0x100)\n");
            puts("ZMODEM buffer at: 0x");
            print_hex_word(ZM_BUFFER_ADDR);
            puts(" (128KB max)\n");
            puts("\n");
            break;
        }

        default:
            puts("Unknown command. Type 'h' for help.\n");
            break;
    }
}

//==============================================================================
// Main
//==============================================================================

int main(void) {
    cmd_buffer_t cmd_buf;
    zmodem_detector_t zmodem_det;

    // Initialize hardware timer for timeouts
    timer_init();

    cmd_buffer_init(&cmd_buf);
    zmodem_detector_init(&zmodem_det);

    puts("\n");
    puts("===========================================\n");
    puts("  PicoRV32 Hex Editor with ZMODEM\n");
    puts("===========================================\n");
    puts("Type 'h' for help\n");
    puts("\n");
    puts("> ");

    while (1) {
        char c = getc();

        // Check for ZMODEM auto-start
        if (zmodem_detector_feed(&zmodem_det, c)) {
            puts("\n*** ZMODEM transfer detected! ***\n");
            cmd_zmodem_receive();
            cmd_buffer_init(&cmd_buf);
            puts("> ");
            continue;
        }

        // Spacebar: page to next 256 bytes
        if (c == ' ') {
            puts("\n");
            uint32_t next_addr = last_dump_addr + last_dump_len;
            cmd_dump(next_addr, 0x100);
            puts("> ");
            continue;
        }

        // Normal command handling
        cmd_buffer_add(&cmd_buf, c);

        if (cmd_buffer_ready(&cmd_buf, c)) {
            puts("\n");
            execute_command(cmd_buf.buffer);
            cmd_buffer_init(&cmd_buf);
            puts("> ");
        }
    }

    return 0;
}
