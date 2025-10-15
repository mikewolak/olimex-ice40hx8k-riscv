//===============================================================================
// XMODEM-1K Protocol Implementation
// Simple, reliable file transfer for embedded systems
//
// Copyright (c) October 2025 Michael Wolak
// Based on XMODEM specification by Ward Christensen
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include "xmodem.h"
#include <string.h>

//===============================================================================
// CRC-16 Calculation (CCITT polynomial: 0x1021)
//===============================================================================

static uint16_t crc16_ccitt(const uint8_t *data, uint32_t len) {
    uint16_t crc = 0;

    while (len--) {
        crc ^= ((uint16_t)*data++) << 8;

        for (int i = 0; i < 8; i++) {
            if (crc & 0x8000) {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc = crc << 1;
            }
        }
    }

    return crc;
}

//===============================================================================
// Initialize XMODEM Context
//===============================================================================

void xmodem_init(xmodem_ctx_t *ctx, xmodem_callbacks_t *callbacks) {
    memset(ctx, 0, sizeof(xmodem_ctx_t));
    ctx->callbacks = callbacks;
    ctx->block_num = 1;  // Blocks start at 1
}

//===============================================================================
// Flush input buffer
//===============================================================================

static void flush_input(xmodem_ctx_t *ctx) {
    // Drain any pending characters with short timeout
    while (ctx->callbacks->getc(10) >= 0) {
        // Discard
    }
}

//===============================================================================
// Receive File via XMODEM-1K
//===============================================================================

xmodem_error_t xmodem_receive(xmodem_ctx_t *ctx, uint8_t *buffer, uint32_t max_size, uint32_t *bytes_received) {
    uint8_t packet[XMODEM_PACKET_SIZE];
    uint8_t retries = 0;
    uint8_t expected_block = 1;
    uint32_t offset = 0;

    *bytes_received = 0;

    // Initiate transfer by sending 'C' for CRC mode
    for (int i = 0; i < 10; i++) {
        flush_input(ctx);
        ctx->callbacks->putc(XMODEM_CRC);

        // Wait for SOH/STX or EOT
        int c = ctx->callbacks->getc(XMODEM_TIMEOUT_INIT / 10);
        if (c == XMODEM_STX || c == XMODEM_SOH) {
            // Got start of first block, put it back by saving for next read
            packet[0] = (uint8_t)c;
            goto receive_block;
        } else if (c == XMODEM_EOT) {
            // Empty file
            ctx->callbacks->putc(XMODEM_ACK);
            return XMODEM_OK;
        }
    }

    // Timeout waiting for sender
    return XMODEM_TIMEOUT;

receive_block:
    // Main receive loop
    while (1) {
        // Read block header (already have first byte in packet[0] from initiation)
        uint8_t block_type = packet[0];

        if (block_type == XMODEM_EOT) {
            // End of transmission
            ctx->callbacks->putc(XMODEM_ACK);
            *bytes_received = offset;
            return XMODEM_OK;
        }

        if (block_type == XMODEM_CAN) {
            // Transfer cancelled
            return XMODEM_CANCEL;
        }

        if (block_type != XMODEM_STX && block_type != XMODEM_SOH) {
            // Invalid block start
            ctx->callbacks->putc(XMODEM_NAK);
            retries++;
            if (retries > XMODEM_MAX_RETRIES) {
                return XMODEM_TOO_MANY_ERRORS;
            }
            // Try to receive next block
            int c = ctx->callbacks->getc(XMODEM_TIMEOUT_BLOCK);
            if (c < 0) return XMODEM_TIMEOUT;
            packet[0] = (uint8_t)c;
            continue;
        }

        // Determine block size
        uint32_t block_size = (block_type == XMODEM_STX) ? 1024 : 128;
        uint32_t packet_len = block_size + 5;  // header(3) + data + CRC(2)

        // Read rest of packet: block#, ~block#, data, CRC-H, CRC-L
        for (uint32_t i = 1; i < packet_len; i++) {
            int c = ctx->callbacks->getc(XMODEM_TIMEOUT_CHAR);
            if (c < 0) {
                // Timeout reading packet
                ctx->callbacks->putc(XMODEM_NAK);
                retries++;
                if (retries > XMODEM_MAX_RETRIES) {
                    return XMODEM_TIMEOUT;
                }
                goto wait_next_block;
            }
            packet[i] = (uint8_t)c;
        }

        // Validate block numbers
        uint8_t block_num = packet[1];
        uint8_t block_num_inv = packet[2];

        if (block_num != (uint8_t)(~block_num_inv)) {
            // Block number mismatch
            ctx->callbacks->putc(XMODEM_NAK);
            retries++;
            if (retries > XMODEM_MAX_RETRIES) {
                return XMODEM_SYNC_ERROR;
            }
            goto wait_next_block;
        }

        // Check if this is a duplicate block (retransmission)
        if (block_num == (uint8_t)(expected_block - 1)) {
            // Duplicate block, ACK it and wait for next
            ctx->callbacks->putc(XMODEM_ACK);
            goto wait_next_block;
        }

        // Check if this is the expected block
        if (block_num != expected_block) {
            // Unexpected block number - synchronization lost
            flush_input(ctx);
            ctx->callbacks->putc(XMODEM_NAK);
            retries++;
            if (retries > XMODEM_MAX_RETRIES) {
                return XMODEM_SYNC_ERROR;
            }
            goto wait_next_block;
        }

        // Validate CRC
        uint16_t received_crc = ((uint16_t)packet[block_size + 3] << 8) | packet[block_size + 4];
        uint16_t calculated_crc = crc16_ccitt(&packet[3], block_size);

        if (received_crc != calculated_crc) {
            // CRC error
            ctx->callbacks->putc(XMODEM_NAK);
            retries++;
            if (retries > XMODEM_MAX_RETRIES) {
                return XMODEM_CRC_ERROR;
            }
            goto wait_next_block;
        }

        // Valid block! Copy data to buffer
        if (offset + block_size > max_size) {
            // Buffer overflow
            ctx->callbacks->putc(XMODEM_CAN);
            ctx->callbacks->putc(XMODEM_CAN);
            return XMODEM_ERROR;
        }

        memcpy(buffer + offset, &packet[3], block_size);
        offset += block_size;

        // Send ACK and advance to next block
        ctx->callbacks->putc(XMODEM_ACK);
        expected_block++;
        retries = 0;  // Reset retry counter on successful block

wait_next_block:
        ; // Empty statement required after label in C
        // Wait for next block
        int c = ctx->callbacks->getc(XMODEM_TIMEOUT_BLOCK);
        if (c < 0) {
            return XMODEM_TIMEOUT;
        }
        packet[0] = (uint8_t)c;
    }

    return XMODEM_ERROR;  // Should never reach here
}

//===============================================================================
// Send File via XMODEM-1K
//===============================================================================

xmodem_error_t xmodem_send(xmodem_ctx_t *ctx, const uint8_t *buffer, uint32_t size) {
    uint8_t packet[XMODEM_PACKET_SIZE];
    uint8_t block_num = 1;
    uint32_t offset = 0;
    uint8_t retries;

    // Wait for receiver to send 'C' (CRC mode request)
    for (int i = 0; i < 60; i++) {  // 60 seconds timeout
        int c = ctx->callbacks->getc(1000);
        if (c == XMODEM_CRC) {
            break;  // Receiver ready
        }
        if (c == XMODEM_CAN) {
            return XMODEM_CANCEL;
        }
        if (i == 59) {
            return XMODEM_TIMEOUT;
        }
    }

    // Send all blocks
    while (offset < size) {
        retries = 0;

retry_block:
        ; // Empty statement required after label in C
        // Build packet
        uint32_t remaining = size - offset;
        uint32_t block_size = (remaining >= 1024) ? 1024 : remaining;

        // Use STX for 1K blocks, SOH for smaller blocks
        packet[0] = (block_size == 1024) ? XMODEM_STX : XMODEM_SOH;
        packet[1] = block_num;
        packet[2] = (uint8_t)(~block_num);

        // Copy data and pad if necessary
        memcpy(&packet[3], buffer + offset, block_size);
        if (block_size < 1024) {
            // Pad with XMODEM_PAD (Ctrl-Z)
            memset(&packet[3 + block_size], XMODEM_PAD, 1024 - block_size);
            block_size = 1024;
        }

        // Calculate CRC
        uint16_t crc = crc16_ccitt(&packet[3], block_size);
        packet[block_size + 3] = (uint8_t)(crc >> 8);    // CRC high byte
        packet[block_size + 4] = (uint8_t)(crc & 0xFF);  // CRC low byte

        // Send packet
        for (uint32_t i = 0; i < block_size + 5; i++) {
            ctx->callbacks->putc(packet[i]);
        }

        // Wait for ACK/NAK
        int response = ctx->callbacks->getc(XMODEM_TIMEOUT_BLOCK);

        if (response == XMODEM_ACK) {
            // Block accepted, move to next
            offset += (size - offset >= 1024) ? 1024 : (size - offset);
            block_num++;
            continue;
        } else if (response == XMODEM_NAK) {
            // Retransmit block
            retries++;
            if (retries > XMODEM_MAX_RETRIES) {
                return XMODEM_TOO_MANY_ERRORS;
            }
            goto retry_block;
        } else if (response == XMODEM_CAN) {
            return XMODEM_CANCEL;
        } else {
            // Timeout or garbage
            retries++;
            if (retries > XMODEM_MAX_RETRIES) {
                return XMODEM_TIMEOUT;
            }
            goto retry_block;
        }
    }

    // Send EOT
    for (retries = 0; retries < XMODEM_MAX_RETRIES; retries++) {
        ctx->callbacks->putc(XMODEM_EOT);

        int response = ctx->callbacks->getc(XMODEM_TIMEOUT_BLOCK);
        if (response == XMODEM_ACK) {
            return XMODEM_OK;
        }
        // Retry EOT if no ACK
    }

    return XMODEM_TIMEOUT;
}
