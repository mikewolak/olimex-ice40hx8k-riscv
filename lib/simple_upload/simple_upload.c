//===============================================================================
// Simple Upload Protocol - Proven Working Protocol from Bootloader
// Dead-simple binary upload with single CRC check at the end
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include "simple_upload.h"
#include <string.h>

//===============================================================================
// CRC32 Calculation (matches bootloader and fw_upload.c)
//===============================================================================

static uint32_t crc32_table[256];
static int crc32_initialized = 0;

static void crc32_init(void) {
    if (crc32_initialized) return;

    for (uint32_t i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
        }
        crc32_table[i] = crc;
    }
    crc32_initialized = 1;
}

static uint32_t crc32_update(uint32_t crc, uint8_t byte) {
    return (crc >> 8) ^ crc32_table[(crc ^ byte) & 0xFF];
}

//===============================================================================
// Receive File (Device acts as bootloader)
//===============================================================================

int32_t simple_receive(simple_callbacks_t *callbacks, uint8_t *buffer, uint32_t max_size) {
    uint32_t packet_size = 0;
    uint32_t bytes_received = 0;
    uint32_t expected_crc;
    uint32_t calculated_crc = 0xFFFFFFFF;  // CRC32 initial value
    uint8_t ack_char = 'A';

    // Initialize CRC32 lookup table
    crc32_init();

    // Step 1: Wait for 'R' (Ready) command
    while (1) {
        uint8_t cmd = callbacks->getc();
        if (cmd == 'R' || cmd == 'r') {
            break;
        }
        // Check for Ctrl-C cancel
        if (cmd == 0x03) {
            return -SIMPLE_ERROR_CANCEL;
        }
    }

    // Step 2: Send ACK 'A' for Ready
    callbacks->putc('A');
    ack_char = 'B';

    // Step 3: Receive 4-byte packet size (little-endian)
    for (int i = 0; i < 4; i++) {
        uint8_t byte = callbacks->getc();
        packet_size |= ((uint32_t)byte) << (i * 8);
    }

    // Step 4: Send ACK 'B' for size received
    callbacks->putc('B');
    ack_char = 'C';

    // Validate size
    if (packet_size == 0 || packet_size > max_size) {
        return -SIMPLE_ERROR_SIZE;
    }

    // Step 5: Receive firmware data in 64-byte chunks
    while (bytes_received < packet_size) {
        uint32_t chunk_bytes = 0;

        // Receive up to 64 bytes for this chunk
        while (chunk_bytes < SIMPLE_CHUNK_SIZE && bytes_received < packet_size) {
            uint8_t byte = callbacks->getc();
            buffer[bytes_received] = byte;

            // Update CRC32 incrementally
            calculated_crc = crc32_update(calculated_crc, byte);

            bytes_received++;
            chunk_bytes++;
        }

        // Send ACK after each chunk (C, D, E, ... Z, then wrap to A)
        callbacks->putc(ack_char);
        ack_char++;
        if (ack_char > 'Z') ack_char = 'A';  // Wrap around
    }

    // Finalize CRC32
    calculated_crc = ~calculated_crc;

    // Step 6: Wait for 'C' (CRC command)
    uint8_t crc_cmd = callbacks->getc();
    if (crc_cmd != 'C') {
        return -SIMPLE_ERROR_CRC;
    }

    // Step 7: Receive 4-byte expected CRC (little-endian)
    expected_crc = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t byte = callbacks->getc();
        expected_crc |= ((uint32_t)byte) << (i * 8);
    }

    // Step 8: Send ACK + calculated CRC back to host
    callbacks->putc(ack_char);  // Final ACK

    // Send calculated CRC (little-endian)
    callbacks->putc((calculated_crc >> 0) & 0xFF);
    callbacks->putc((calculated_crc >> 8) & 0xFF);
    callbacks->putc((calculated_crc >> 16) & 0xFF);
    callbacks->putc((calculated_crc >> 24) & 0xFF);

    // Step 9: Verify CRC match
    if (calculated_crc != expected_crc) {
        return -SIMPLE_ERROR_CRC;
    }

    // Success! Return number of bytes received
    return (int32_t)bytes_received;
}

//===============================================================================
// Send File (Device acts as sender, PC acts as bootloader)
//===============================================================================

simple_error_t simple_send(simple_callbacks_t *callbacks, const uint8_t *buffer, uint32_t size) {
    uint32_t calculated_crc = 0xFFFFFFFF;  // CRC32 initial value
    uint8_t expected_ack = 'A';
    uint32_t bytes_sent = 0;

    // Initialize CRC32 lookup table
    crc32_init();

    // Step 1: Send 'R' (Ready) to initiate transfer
    callbacks->putc('R');

    // Step 2: Wait for ACK 'A'
    uint8_t ack = callbacks->getc();
    if (ack != 'A') {
        return SIMPLE_ERROR_CANCEL;
    }
    expected_ack = 'B';

    // Step 3: Send 4-byte packet size (little-endian)
    callbacks->putc((size >> 0) & 0xFF);
    callbacks->putc((size >> 8) & 0xFF);
    callbacks->putc((size >> 16) & 0xFF);
    callbacks->putc((size >> 24) & 0xFF);

    // Step 4: Wait for ACK 'B'
    ack = callbacks->getc();
    if (ack != 'B') {
        return SIMPLE_ERROR_CANCEL;
    }
    expected_ack = 'C';

    // Step 5: Send data in 64-byte chunks
    while (bytes_sent < size) {
        uint32_t chunk_bytes = 0;

        // Send up to 64 bytes for this chunk
        while (chunk_bytes < SIMPLE_CHUNK_SIZE && bytes_sent < size) {
            uint8_t byte = buffer[bytes_sent];
            callbacks->putc(byte);

            // Update CRC32 incrementally
            calculated_crc = crc32_update(calculated_crc, byte);

            bytes_sent++;
            chunk_bytes++;
        }

        // Wait for ACK after each chunk (C, D, E, ... Z, then wrap to A)
        ack = callbacks->getc();
        if (ack != expected_ack) {
            return SIMPLE_ERROR_CANCEL;
        }

        expected_ack++;
        if (expected_ack > 'Z') expected_ack = 'A';  // Wrap around
    }

    // Finalize CRC32
    calculated_crc = ~calculated_crc;

    // Step 6: Send 'C' (CRC command)
    callbacks->putc('C');

    // Step 7: Send 4-byte calculated CRC (little-endian)
    callbacks->putc((calculated_crc >> 0) & 0xFF);
    callbacks->putc((calculated_crc >> 8) & 0xFF);
    callbacks->putc((calculated_crc >> 16) & 0xFF);
    callbacks->putc((calculated_crc >> 24) & 0xFF);

    // Step 8: Wait for final ACK
    ack = callbacks->getc();
    if (ack != expected_ack) {
        return SIMPLE_ERROR_CRC;
    }

    // Step 9: Receive 4-byte CRC from device (little-endian)
    uint32_t device_crc = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t byte = callbacks->getc();
        device_crc |= ((uint32_t)byte) << (i * 8);
    }

    // Step 10: Verify CRC match
    if (calculated_crc != device_crc) {
        return SIMPLE_ERROR_CRC;
    }

    // Success!
    return SIMPLE_OK;
}
