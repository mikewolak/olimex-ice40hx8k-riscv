//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform - Bootloader
// bootloader.c - Software bootloader replacing hardware shell
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Bootloader - Runs from SPRAM at 0x10000
 *
 * Boot sequence:
 *   1. Wait for UART command with timeout (~2 seconds)
 *   2. If 'd' received: Enter download mode, receive firmware to SRAM at 0x0
 *   3. If timeout or 'r' received: Jump to firmware at 0x0
 *   4. Verify CRC32 before running downloaded firmware
 *
 * Protocol (compatible with existing fw_upload tool):
 *   PC -> MCU: 'd\n'           (enter download mode)
 *   MCU -> PC: '@@@'           (ready prompt)
 *   PC -> MCU: [4B len][data][4B CRC32]
 *   MCU -> PC: 'OK\n' or 'ERROR\n'
 *   PC -> MCU: 'r\n'           (run command)
 *   MCU: jumps to 0x0
 */

#include <stdint.h>

// MMIO Addresses
#define UART_TX_DATA   (*(volatile uint32_t *)0x80000000)
#define UART_TX_STATUS (*(volatile uint32_t *)0x80000004)
#define UART_RX_DATA   (*(volatile uint32_t *)0x80000008)
#define UART_RX_STATUS (*(volatile uint32_t *)0x8000000C)
#define LED_CONTROL    (*(volatile uint32_t *)0x80000010)
#define BUTTON_STATUS  (*(volatile uint32_t *)0x80000018)

// Target firmware location
#define FIRMWARE_BASE  0x00000000
#define MAX_FIRMWARE_SIZE (64 * 1024)  // 64KB max

// Timeout for waiting for UART command (~2 seconds @ 12MHz)
#define BOOT_TIMEOUT   (24000000)

// External assembly function
extern void jump_to_firmware(uint32_t addr);

//=============================================================================
// UART Functions
//=============================================================================

static void uart_putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while busy
    UART_TX_DATA = c;
}

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static int uart_getc_timeout(uint32_t timeout) {
    while (timeout--) {
        if ((UART_RX_STATUS & 1) == 0) {  // Data available (active low)
            return UART_RX_DATA & 0xFF;
        }
    }
    return -1;  // Timeout
}

static int uart_getc(void) {
    while (UART_RX_STATUS & 1);  // Wait for data
    return UART_RX_DATA & 0xFF;
}

//=============================================================================
// CRC32 Calculation
//=============================================================================

static uint32_t crc32_table[256];

static void crc32_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
        }
        crc32_table[i] = crc;
    }
}

static uint32_t crc32(const uint8_t *data, uint32_t length) {
    uint32_t crc = 0xFFFFFFFF;
    for (uint32_t i = 0; i < length; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    }
    return ~crc;
}

//=============================================================================
// Firmware Download
//=============================================================================

static int download_firmware(void) {
    uint8_t *firmware = (uint8_t *)FIRMWARE_BASE;
    uint32_t length, received_crc, calculated_crc;

    // Send ready prompt
    uart_puts("@@@");

    // Receive length (4 bytes, little-endian)
    length = 0;
    for (int i = 0; i < 4; i++) {
        int byte = uart_getc();
        if (byte < 0) return -1;
        length |= ((uint32_t)byte) << (i * 8);
    }

    // Sanity check
    if (length == 0 || length > MAX_FIRMWARE_SIZE) {
        uart_puts("ERROR: Invalid length\n");
        return -1;
    }

    // Receive firmware data
    for (uint32_t i = 0; i < length; i++) {
        int byte = uart_getc();
        if (byte < 0) return -1;
        firmware[i] = (uint8_t)byte;

        // Toggle LED1 to show activity
        if ((i & 0xFF) == 0) {
            LED_CONTROL ^= 0x01;
        }
    }

    // Receive CRC32 (4 bytes, little-endian)
    received_crc = 0;
    for (int i = 0; i < 4; i++) {
        int byte = uart_getc();
        if (byte < 0) return -1;
        received_crc |= ((uint32_t)byte) << (i * 8);
    }

    // Calculate CRC32
    calculated_crc = crc32(firmware, length);

    // Verify
    if (calculated_crc != received_crc) {
        uart_puts("ERROR: CRC mismatch\n");
        return -1;
    }

    uart_puts("OK\n");
    LED_CONTROL = 0x03;  // Both LEDs on = success
    return 0;
}

//=============================================================================
// Main Bootloader
//=============================================================================

void bootloader_main(void) {
    int cmd;

    // Initialize CRC32 lookup table
    crc32_init();

    // LED pattern: LED1 blinking = waiting for command
    LED_CONTROL = 0x01;

    // Wait for UART command with timeout
    cmd = uart_getc_timeout(BOOT_TIMEOUT);

    if (cmd == 'd' || cmd == 'D') {
        // Download command received
        LED_CONTROL = 0x02;  // LED2 on = downloading

        // Wait for newline
        uart_getc();

        // Download firmware
        if (download_firmware() == 0) {
            // Wait for run command
            while (1) {
                cmd = uart_getc();
                if (cmd == 'r' || cmd == 'R') {
                    uart_getc();  // consume newline
                    break;
                }
            }
        }
    }

    // Jump to firmware at 0x0
    // Turn off LEDs before jumping
    LED_CONTROL = 0x00;

    // Jump!
    jump_to_firmware(FIRMWARE_BASE);

    // Should never return
    while (1);
}
