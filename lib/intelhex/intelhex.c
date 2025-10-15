//===============================================================================
// Intel HEX Format Parser/Generator
// Simple, reliable text-based data transfer for embedded systems
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include "intelhex.h"
#include <string.h>

//===============================================================================
// Helper Functions
//===============================================================================

// Convert hex character to value (0-15)
static int hex_char_to_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

// Convert value (0-15) to hex character
static char val_to_hex_char(uint8_t val) {
    return (val < 10) ? ('0' + val) : ('A' + val - 10);
}

// Convert two hex characters to byte
static int hex_to_byte(const char *hex) {
    int high = hex_char_to_val(hex[0]);
    int low = hex_char_to_val(hex[1]);
    if (high < 0 || low < 0) return -1;
    return (high << 4) | low;
}

// Convert byte to two hex characters
static void byte_to_hex(uint8_t byte, char *hex) {
    hex[0] = val_to_hex_char(byte >> 4);
    hex[1] = val_to_hex_char(byte & 0x0F);
}

// Calculate Intel HEX checksum (two's complement)
static uint8_t calc_checksum(const uint8_t *data, int len) {
    uint8_t sum = 0;
    for (int i = 0; i < len; i++) {
        sum += data[i];
    }
    return (~sum + 1) & 0xFF;  // Two's complement
}

//===============================================================================
// Receive Intel HEX
//===============================================================================

ihex_error_t ihex_receive(ihex_callbacks_t *callbacks) {
    char line[IHEX_MAX_LINE_LEN];
    uint8_t data[256];  // Max data bytes in a record
    uint32_t base_addr = 0;  // Upper 16 bits for extended linear address

    while (1) {
        // Read one line - skip whitespace/garbage until we find ':'
        int line_len = 0;
        int found_start = 0;

        // Wait for ':' (start of Intel HEX record)
        while (!found_start) {
            int c = callbacks->getc();
            if (c < 0) return IHEX_ERROR;  // Timeout or error

            // Check for Ctrl-C (cancel)
            if (c == 0x03) {
                return IHEX_ERROR;  // User cancelled
            }

            // Skip whitespace and garbage
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                continue;
            }

            if (c == ':') {
                line[line_len++] = (char)c;
                found_start = 1;
                break;
            }

            // Unexpected character - might be garbage, skip it
            // Just continue and keep looking for ':'
            continue;
        }

        // Read rest of line until newline
        while (line_len < IHEX_MAX_LINE_LEN - 1) {
            int c = callbacks->getc();
            if (c < 0) return IHEX_ERROR;  // Timeout or error

            if (c == '\n' || c == '\r') {
                break;  // Got complete line
            }

            line[line_len++] = (char)c;
        }
        line[line_len] = '\0';

        // Minimum valid line: :LLAAAATTCC (11 chars)
        if (line_len < 11) {
            return IHEX_ERROR_INVALID_LENGTH;
        }

        // Parse byte count
        int byte_count = hex_to_byte(&line[1]);
        if (byte_count < 0) return IHEX_ERROR_INVALID_HEX;

        // Parse address
        int addr_high = hex_to_byte(&line[3]);
        int addr_low = hex_to_byte(&line[5]);
        if (addr_high < 0 || addr_low < 0) return IHEX_ERROR_INVALID_HEX;
        uint16_t addr = (addr_high << 8) | addr_low;

        // Parse record type
        int rec_type = hex_to_byte(&line[7]);
        if (rec_type < 0) return IHEX_ERROR_INVALID_HEX;

        // Verify line length
        int expected_len = 11 + (byte_count * 2);  // :LLAAAATT + data + CC
        if (line_len != expected_len) {
            return IHEX_ERROR_INVALID_LENGTH;
        }

        // Parse data bytes
        for (int i = 0; i < byte_count; i++) {
            int byte_val = hex_to_byte(&line[9 + i * 2]);
            if (byte_val < 0) return IHEX_ERROR_INVALID_HEX;
            data[i] = (uint8_t)byte_val;
        }

        // Parse checksum
        int checksum = hex_to_byte(&line[9 + byte_count * 2]);
        if (checksum < 0) return IHEX_ERROR_INVALID_HEX;

        // Verify checksum
        uint8_t calc_sum = (uint8_t)byte_count;
        calc_sum += (uint8_t)(addr >> 8);
        calc_sum += (uint8_t)(addr & 0xFF);
        calc_sum += (uint8_t)rec_type;
        for (int i = 0; i < byte_count; i++) {
            calc_sum += data[i];
        }
        calc_sum = (~calc_sum + 1) & 0xFF;

        if (calc_sum != (uint8_t)checksum) {
            return IHEX_ERROR_CHECKSUM;
        }

        // Process record based on type
        switch (rec_type) {
            case IHEX_TYPE_DATA:
                // Write data to memory
                if (byte_count > 0) {
                    uint32_t full_addr = base_addr | addr;
                    callbacks->write(full_addr, data, (uint8_t)byte_count);
                }
                break;

            case IHEX_TYPE_EOF:
                // End of file - success!
                return IHEX_OK;

            case IHEX_TYPE_EXT_LINEAR_ADDR:
                // Extended linear address (upper 16 bits)
                if (byte_count != 2) return IHEX_ERROR;
                base_addr = ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16);
                break;

            default:
                // Unsupported record type
                return IHEX_ERROR_UNSUPPORTED;
        }
    }

    return IHEX_ERROR;  // Should never reach here
}

//===============================================================================
// Send Intel HEX
//===============================================================================

ihex_error_t ihex_send(ihex_callbacks_t *callbacks, uint32_t start_addr, uint32_t length) {
    char line[IHEX_MAX_LINE_LEN];
    uint8_t data[IHEX_BYTES_PER_LINE];
    uint32_t addr = start_addr;
    uint32_t remaining = length;
    uint32_t current_base = 0xFFFFFFFF;  // Force initial extended address record

    while (remaining > 0) {
        // Check if we need extended linear address record
        uint32_t base_addr = addr & 0xFFFF0000;
        if (base_addr != current_base) {
            current_base = base_addr;

            // Send extended linear address record
            uint8_t ext_addr[2];
            ext_addr[0] = (uint8_t)(base_addr >> 24);
            ext_addr[1] = (uint8_t)(base_addr >> 16);

            uint8_t checksum = 2 + 0 + 0 + IHEX_TYPE_EXT_LINEAR_ADDR + ext_addr[0] + ext_addr[1];
            checksum = (~checksum + 1) & 0xFF;

            // Format: :02000004XXXXCC
            callbacks->putc(':');
            callbacks->putc('0'); callbacks->putc('2');  // Byte count
            callbacks->putc('0'); callbacks->putc('0');  // Address 0000
            callbacks->putc('0'); callbacks->putc('0');
            callbacks->putc('0'); callbacks->putc('4');  // Type 04
            char hex[2];
            byte_to_hex(ext_addr[0], hex);
            callbacks->putc(hex[0]); callbacks->putc(hex[1]);
            byte_to_hex(ext_addr[1], hex);
            callbacks->putc(hex[0]); callbacks->putc(hex[1]);
            byte_to_hex(checksum, hex);
            callbacks->putc(hex[0]); callbacks->putc(hex[1]);
            callbacks->putc('\r'); callbacks->putc('\n');
        }

        // Read data for this line
        uint8_t bytes_this_line = (remaining >= IHEX_BYTES_PER_LINE) ? IHEX_BYTES_PER_LINE : (uint8_t)remaining;
        callbacks->read(addr, data, bytes_this_line);

        // Calculate checksum
        uint16_t line_addr = addr & 0xFFFF;
        uint8_t checksum = bytes_this_line;
        checksum += (uint8_t)(line_addr >> 8);
        checksum += (uint8_t)(line_addr & 0xFF);
        checksum += IHEX_TYPE_DATA;
        for (int i = 0; i < bytes_this_line; i++) {
            checksum += data[i];
        }
        checksum = (~checksum + 1) & 0xFF;

        // Send data record
        callbacks->putc(':');

        // Byte count
        char hex[2];
        byte_to_hex(bytes_this_line, hex);
        callbacks->putc(hex[0]); callbacks->putc(hex[1]);

        // Address
        byte_to_hex((uint8_t)(line_addr >> 8), hex);
        callbacks->putc(hex[0]); callbacks->putc(hex[1]);
        byte_to_hex((uint8_t)(line_addr & 0xFF), hex);
        callbacks->putc(hex[0]); callbacks->putc(hex[1]);

        // Record type (00 = data)
        callbacks->putc('0'); callbacks->putc('0');

        // Data bytes
        for (int i = 0; i < bytes_this_line; i++) {
            byte_to_hex(data[i], hex);
            callbacks->putc(hex[0]); callbacks->putc(hex[1]);
        }

        // Checksum
        byte_to_hex(checksum, hex);
        callbacks->putc(hex[0]); callbacks->putc(hex[1]);

        // Line ending
        callbacks->putc('\r'); callbacks->putc('\n');

        addr += bytes_this_line;
        remaining -= bytes_this_line;
    }

    // Send EOF record: :00000001FF
    callbacks->putc(':');
    callbacks->putc('0'); callbacks->putc('0');  // Byte count
    callbacks->putc('0'); callbacks->putc('0');  // Address
    callbacks->putc('0'); callbacks->putc('0');
    callbacks->putc('0'); callbacks->putc('1');  // Type 01 (EOF)
    callbacks->putc('F'); callbacks->putc('F');  // Checksum
    callbacks->putc('\r'); callbacks->putc('\n');

    return IHEX_OK;
}
