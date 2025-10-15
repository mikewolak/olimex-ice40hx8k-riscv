//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// hexedit.c - Interactive Hex Editor with Simple Upload Protocol
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
 * - Simple Upload (bootloader protocol) file transfer
 * - 128KB receive limit, buffer at heap-140KB
 */

#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include "../lib/simple_upload/simple_upload.h"
#include "../lib/microrl/microrl.h"
#include "../lib/incurses/curses.h"

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
volatile uint8_t clock_enabled = 0;   // Flag: clock display enabled (0=off, 1=on)

// Millisecond counter for timeouts (updated by interrupt)
volatile uint32_t millis = 0;         // Total milliseconds since start

// Memory layout (based on linker script)
// Physical memory: 0x00000000 - 0x0007FFFF (512KB SRAM)
// Application:     0x00000000 - 0x0003FFFF (256KB for code/data/bss)
// Heap:            End of BSS - 0x00042000
// Stack:           0x00042000 - 0x00080000 (grows down from 0x80000)
#define HEAP_END       0x00042000   // Heap ends here (from linker script)

// File transfer configuration
#define ZM_MAX_RECEIVE    (128 * 1024)          // 128KB max transfer
#define ZM_BUFFER_OFFSET  (140 * 1024)          // 140KB before heap end
#define ZM_BUFFER_ADDR    (HEAP_END - ZM_BUFFER_OFFSET)

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

// Get current time in milliseconds
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
// Simple Upload Protocol Commands
//==============================================================================

// UART callbacks for simple_upload
static void simple_uart_putc(uint8_t c) {
    while (UART_TX_STATUS & 1);  // Wait while busy
    UART_TX_DATA = c;
}

static uint8_t simple_uart_getc(void) {
    while (!(UART_RX_STATUS & 1));  // Wait until data available
    return UART_RX_DATA & 0xFF;
}

void cmd_simple_upload(uint32_t addr) {
    // Flush UART RX buffer FIRST
    uart_flush_rx();

    uart_puts("\n");
    uart_puts("=== Simple Upload (bootloader protocol) ===\n");
    uart_puts("Receiving file to address: 0x");
    print_hex_word(addr);
    uart_puts("\n");
    uart_puts("Max size: ");
    print_dec(ZM_MAX_RECEIVE);
    uart_puts(" bytes\n");
    uart_puts("\n");
    uart_puts("Start fw_upload on your PC now...\n");

    // Set up callbacks
    simple_callbacks_t callbacks = {
        .putc = simple_uart_putc,
        .getc = simple_uart_getc
    };

    // Receive file using bootloader protocol
    int32_t bytes = simple_receive(&callbacks, (uint8_t *)addr, ZM_MAX_RECEIVE);

    if (bytes > 0) {
        uart_puts("\n");
        uart_puts("*** Upload SUCCESS ***\n");
        uart_puts("Received: ");
        print_dec((uint32_t)bytes);
        uart_puts(" bytes\n");
        uart_puts("Address: 0x");
        print_hex_word(addr);
        uart_puts("\n");
    } else {
        uart_puts("\n");
        uart_puts("*** Upload FAILED ***\n");
        uart_puts("Error code: ");
        print_dec((uint32_t)(-bytes));
        uart_puts("\n");
    }
}

//==============================================================================
// Visual Hex Editor (incurses-based)
//==============================================================================

// Visual hex editor with curses interface
void cmd_visual(uint32_t start_addr) {
    int cursor_x = 0;   // 0-15 (byte column)
    int cursor_y = 0;   // 0-21 (row on screen)
    uint32_t top_addr = start_addr & ~0xF;  // Align to 16-byte boundary
    int editing = 0;    // Edit mode flag
    int edit_nibble = 0; // 0=high nibble, 1=low nibble
    uint8_t edit_value = 0;

    // Initialize curses
    initscr();
    noecho();
    raw();
    keypad(stdscr, TRUE);

    while (1) {
        // Clear screen
        clear();

        // Draw title bar
        move(0, 0);
        attron(A_REVERSE);
        addstr("Visual Hex Editor - Arrow keys:navigate Enter:edit ESC:exit q:quit");
        for (int i = 68; i < COLS; i++) addch(' ');
        standend();

        // Draw hex grid (22 rows of 16 bytes each)
        for (int row = 0; row < 22; row++) {
            uint32_t addr = top_addr + (row * 16);
            move(row + 2, 0);

            // Print address
            char addr_str[12];
            snprintf(addr_str, sizeof(addr_str), "%08X: ", (unsigned int)addr);
            addstr(addr_str);

            // Print hex bytes
            for (int col = 0; col < 16; col++) {
                uint8_t byte = ((uint8_t *)(addr))[col];

                // Highlight current byte
                if (row == cursor_y && col == cursor_x && !editing) {
                    attron(A_REVERSE);
                }

                // Print hex byte
                char hex_str[4];
                snprintf(hex_str, sizeof(hex_str), "%02X ", byte);
                addstr(hex_str);

                if (row == cursor_y && col == cursor_x && !editing) {
                    standend();
                }
            }

            // Print ASCII
            addstr(" ");
            for (int col = 0; col < 16; col++) {
                uint8_t byte = ((uint8_t *)(addr))[col];
                char c = (byte >= 32 && byte < 127) ? byte : '.';

                if (row == cursor_y && col == cursor_x && !editing) {
                    attron(A_REVERSE);
                }

                addch(c);

                if (row == cursor_y && col == cursor_x && !editing) {
                    standend();
                }
            }
        }

        // Status bar
        move(LINES - 1, 0);
        attron(A_REVERSE);
        char status[COLS + 1];
        uint32_t current_addr = top_addr + (cursor_y * 16) + cursor_x;
        uint8_t current_byte = ((uint8_t *)current_addr)[0];
        snprintf(status, sizeof(status),
                 "Addr:0x%08X Val:0x%02X(%u) Cursor:(%d,%d) Top:0x%08X %s",
                 (unsigned int)current_addr,
                 current_byte,
                 current_byte,
                 cursor_x,
                 cursor_y,
                 (unsigned int)top_addr,
                 editing ? "EDIT" : "");
        addstr(status);
        for (int i = strlen(status); i < COLS; i++) addch(' ');
        standend();

        // Cursor management
        if (editing) {
            // Show cursor and position it at the edit location
            curs_set(1);
            move(cursor_y + 2, 10 + (cursor_x * 3) + edit_nibble);
        } else {
            // Hide cursor when navigating
            curs_set(0);
        }

        refresh();

        // Get key
        int ch = getch();

        if (editing) {
            // Edit mode - accept hex digits
            if (ch >= '0' && ch <= '9') {
                int digit = ch - '0';
                if (edit_nibble == 0) {
                    edit_value = (digit << 4);
                    edit_nibble = 1;
                } else {
                    edit_value |= digit;
                    // Write the byte
                    uint32_t addr = top_addr + (cursor_y * 16) + cursor_x;
                    *((uint8_t *)addr) = edit_value;
                    editing = 0;
                    edit_nibble = 0;
                    // Move to next byte
                    cursor_x++;
                    if (cursor_x >= 16) {
                        cursor_x = 0;
                        cursor_y++;
                        if (cursor_y >= 22) {
                            cursor_y = 21;
                            top_addr += 16;
                        }
                    }
                }
            } else if ((ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')) {
                int digit = ((ch & 0xDF) - 'A') + 10;  // Convert to uppercase and get 10-15
                if (edit_nibble == 0) {
                    edit_value = (digit << 4);
                    edit_nibble = 1;
                } else {
                    edit_value |= digit;
                    // Write the byte
                    uint32_t addr = top_addr + (cursor_y * 16) + cursor_x;
                    *((uint8_t *)addr) = edit_value;
                    editing = 0;
                    edit_nibble = 0;
                    // Move to next byte
                    cursor_x++;
                    if (cursor_x >= 16) {
                        cursor_x = 0;
                        cursor_y++;
                        if (cursor_y >= 22) {
                            cursor_y = 21;
                            top_addr += 16;
                        }
                    }
                }
            } else if (ch == 27) {  // ESC - cancel edit
                editing = 0;
                edit_nibble = 0;
            }
        } else {
            // Navigation mode
            switch (ch) {
                case 27:   // ESC - exit visual mode
                case 'q':
                case 'Q':
                    endwin();
                    return;

                case '\n':  // Enter - start editing
                case '\r':
                    editing = 1;
                    edit_nibble = 0;
                    edit_value = 0;
                    break;

                // Arrow keys (curses KEY_* constants)
                case 'h':  // Left (vi-style)
                case 68:   // Left arrow (if keypad works)
                    if (cursor_x > 0) cursor_x--;
                    break;

                case 'l':  // Right (vi-style)
                case 67:   // Right arrow
                    if (cursor_x < 15) cursor_x++;
                    break;

                case 'k':  // Up (vi-style)
                case 65:   // Up arrow
                    if (cursor_y > 0) {
                        cursor_y--;
                    } else if (top_addr >= 16) {
                        top_addr -= 16;
                    }
                    break;

                case 'j':  // Down (vi-style)
                case 66:   // Down arrow
                    if (cursor_y < 21) {
                        cursor_y++;
                    } else {
                        top_addr += 16;
                    }
                    break;

                case ' ':  // Page down
                case 'f':  // Page forward
                    top_addr += (22 * 16);
                    break;

                case 'b':  // Page back
                    if (top_addr >= (22 * 16)) {
                        top_addr -= (22 * 16);
                    } else {
                        top_addr = 0;
                    }
                    break;

                case 'g':  // Go to address (simple version - go to start)
                    top_addr = 0;
                    cursor_x = 0;
                    cursor_y = 0;
                    break;
            }
        }
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

        case 'u':  // Upload using bootloader protocol
        case 'U': {
            // Check if this is 'up' (upload from PC)
            if (*cmd == 'p' || *cmd == 'P') {
                cmd++;  // Skip 'p'/'P'
                skip_whitespace(&cmd);
                uint32_t addr = parse_hex(cmd, &cmd);
                if (addr == 0 && *cmd == '\0') {
                    addr = ZM_BUFFER_ADDR;  // Default to transfer buffer
                }
                cmd_simple_upload(addr);
            } else {
                uart_puts("Upload command:\n");
                uart_puts("  up [addr]  - Upload file (bootloader protocol)\n");
                uart_puts("               Default addr: 0x");
                print_hex_word(ZM_BUFFER_ADDR);
                uart_puts("\n");
            }
            break;
        }

        case 't':  // Toggle clock display
        case 'T': {
            clock_enabled = !clock_enabled;
            if (clock_enabled) {
                uart_puts("Clock display enabled\n");
            } else {
                uart_puts("Clock display disabled\n");
                // Clear the clock area
                uart_puts("\033[s");         // Save cursor
                uart_puts("\033[1;60H");     // Move to clock position
                uart_puts("               ");  // Clear with spaces
                uart_puts("\033[u");         // Restore cursor
            }
            break;
        }

        case 'v':  // Visual hex editor
        case 'V': {
            uint32_t addr = 0;
            if (*cmd != '\0') {
                addr = parse_hex(cmd, &cmd);
            }
            cmd_visual(addr);
            // After exiting visual mode, clear screen and show prompt
            uart_puts("\033[2J\033[H");  // Clear screen, home cursor
            uart_puts("Exited visual mode\n");
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
            uart_puts("  v [addr]                 - Visual hex editor (curses)\n");
            uart_puts("  t                        - Toggle clock display on/off\n");
            uart_puts("  up [addr]                - Upload file (bootloader protocol)\n");
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

    // Initialize hardware timer for 60 Hz interrupts
    timer_init();

    // Enable Timer IRQ (IRQ[0])
    uart_puts("Enabling timer interrupts...\n");
    irq_enable();

    // Initialize microRL
    microrl_init(&mrl, microrl_output, microrl_execute);
    microrl_set_prompt(&mrl, "> ");

    uart_puts("\n");
    uart_puts("===========================================\n");
    uart_puts("  PicoRV32 Hex Editor + microRL\n");
    uart_puts("===========================================\n");
    uart_puts("Type 'h' for help, 't' to toggle clock display\n");
    uart_puts("Features: Command history (UP/DOWN), line editing\n");
    uart_puts("\n");

    while (1) {
        // Update clock display if timer interrupt fired and enabled
        if (clock_updated && clock_enabled) {
            clock_updated = 0;
            print_clock();
        }

        // Check for UART input (non-blocking)
        if (!uart_getc_available()) {
            continue;  // No input yet, keep checking clock
        }

        char c = uart_getc();

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
