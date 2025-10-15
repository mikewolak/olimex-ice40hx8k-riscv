//===============================================================================
// XMODEM-1K Protocol Implementation
// Simple, reliable file transfer for embedded systems
//
// Copyright (c) October 2025 Michael Wolak
// Based on XMODEM specification by Ward Christensen
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#ifndef XMODEM_H
#define XMODEM_H

#include <stdint.h>

//===============================================================================
// Protocol Constants
//===============================================================================

// XMODEM control characters
#define XMODEM_SOH  0x01    // Start of 128-byte block
#define XMODEM_STX  0x02    // Start of 1024-byte block (XMODEM-1K)
#define XMODEM_EOT  0x04    // End of transmission
#define XMODEM_ACK  0x06    // Acknowledge
#define XMODEM_NAK  0x15    // Negative acknowledge
#define XMODEM_CAN  0x18    // Cancel (Ctrl-X)
#define XMODEM_CRC  'C'     // Request CRC mode (0x43)
#define XMODEM_PAD  0x1A    // Ctrl-Z padding

// Timeouts and retries
#define XMODEM_TIMEOUT_INIT     1800000 // 30 minutes to start transfer (manual testing)
#define XMODEM_TIMEOUT_BLOCK    1800000 // 30 minutes per block
#define XMODEM_TIMEOUT_CHAR     1000    // 1 second between characters
#define XMODEM_MAX_RETRIES      10      // Max retransmissions per block

// Block sizes
#define XMODEM_BLOCK_SIZE       1024    // XMODEM-1K block size
#define XMODEM_PACKET_SIZE      1029    // STX + block# + ~block# + 1024 data + CRC-H + CRC-L

//===============================================================================
// Error Codes
//===============================================================================

typedef enum {
    XMODEM_OK = 0,              // Success
    XMODEM_ERROR = -1,          // Generic error
    XMODEM_TIMEOUT = -2,        // Timeout waiting for data
    XMODEM_CANCEL = -3,         // Transfer cancelled
    XMODEM_CRC_ERROR = -4,      // CRC check failed
    XMODEM_SYNC_ERROR = -5,     // Lost synchronization
    XMODEM_TOO_MANY_ERRORS = -6 // Exceeded retry limit
} xmodem_error_t;

//===============================================================================
// Callback Functions
//===============================================================================

typedef struct {
    // Get character with timeout (returns -1 on timeout)
    int (*getc)(uint32_t timeout_ms);

    // Put character
    void (*putc)(uint8_t c);

    // Get current time in milliseconds
    uint32_t (*gettime)(void);
} xmodem_callbacks_t;

//===============================================================================
// XMODEM Context
//===============================================================================

typedef struct {
    xmodem_callbacks_t *callbacks;
    uint8_t block_num;          // Current block number (1-255, wraps)
    uint32_t total_bytes;       // Total bytes transferred
    uint32_t errors;            // Error counter
} xmodem_ctx_t;

//===============================================================================
// Public API
//===============================================================================

// Initialize XMODEM context
void xmodem_init(xmodem_ctx_t *ctx, xmodem_callbacks_t *callbacks);

// Receive file via XMODEM-1K
// Returns number of bytes received, or negative error code
xmodem_error_t xmodem_receive(xmodem_ctx_t *ctx, uint8_t *buffer, uint32_t max_size, uint32_t *bytes_received);

// Send file via XMODEM-1K
// Returns 0 on success, negative error code on failure
xmodem_error_t xmodem_send(xmodem_ctx_t *ctx, const uint8_t *buffer, uint32_t size);

#endif // XMODEM_H
