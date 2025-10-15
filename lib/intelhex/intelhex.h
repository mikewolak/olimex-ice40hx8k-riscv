//===============================================================================
// Intel HEX Format Parser/Generator
// Simple, reliable text-based data transfer for embedded systems
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#ifndef INTELHEX_H
#define INTELHEX_H

#include <stdint.h>

//===============================================================================
// Intel HEX Record Types
//===============================================================================

#define IHEX_TYPE_DATA              0x00    // Data record
#define IHEX_TYPE_EOF               0x01    // End of file
#define IHEX_TYPE_EXT_SEG_ADDR      0x02    // Extended segment address
#define IHEX_TYPE_START_SEG_ADDR    0x03    // Start segment address
#define IHEX_TYPE_EXT_LINEAR_ADDR   0x04    // Extended linear address
#define IHEX_TYPE_START_LINEAR_ADDR 0x05    // Start linear address

//===============================================================================
// Configuration
//===============================================================================

#define IHEX_BYTES_PER_LINE     16      // Standard: 16 bytes per line
#define IHEX_MAX_LINE_LEN       128     // Max line length including \n

//===============================================================================
// Error Codes
//===============================================================================

typedef enum {
    IHEX_OK = 0,                // Success
    IHEX_ERROR = -1,            // Generic error
    IHEX_ERROR_INVALID_START = -2,  // Line doesn't start with ':'
    IHEX_ERROR_INVALID_LENGTH = -3, // Line too short or byte count wrong
    IHEX_ERROR_INVALID_HEX = -4,    // Invalid hex characters
    IHEX_ERROR_CHECKSUM = -5,       // Checksum mismatch
    IHEX_ERROR_UNSUPPORTED = -6,    // Unsupported record type
    IHEX_ERROR_EOF = -7             // End of file record received
} ihex_error_t;

//===============================================================================
// Callbacks
//===============================================================================

typedef struct {
    // Get one character (blocking or with timeout)
    // Returns character 0-255, or -1 on timeout/error
    int (*getc)(void);

    // Put one character
    void (*putc)(uint8_t c);

    // Write data to memory (for receive)
    void (*write)(uint32_t addr, const uint8_t *data, uint8_t len);

    // Read data from memory (for send)
    void (*read)(uint32_t addr, uint8_t *data, uint8_t len);
} ihex_callbacks_t;

//===============================================================================
// Public API
//===============================================================================

// Receive Intel HEX data and write to memory
// Returns IHEX_OK when EOF record received, or error code
ihex_error_t ihex_receive(ihex_callbacks_t *callbacks);

// Send memory region as Intel HEX
// Returns IHEX_OK on success, or error code
ihex_error_t ihex_send(ihex_callbacks_t *callbacks, uint32_t start_addr, uint32_t length);

#endif // INTELHEX_H
