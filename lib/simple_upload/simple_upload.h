//===============================================================================
// Simple Upload Protocol - Proven Working Protocol from Bootloader
// Dead-simple binary upload with single CRC check at the end
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#ifndef SIMPLE_UPLOAD_H
#define SIMPLE_UPLOAD_H

#include <stdint.h>

//===============================================================================
// Protocol Constants
//===============================================================================

#define SIMPLE_CHUNK_SIZE   64      // Data sent in 64-byte chunks
#define SIMPLE_CMD_READY    'R'     // Host ready to send
#define SIMPLE_CMD_CRC      'C'     // CRC check command

//===============================================================================
// Callback Functions
//===============================================================================

typedef struct {
    void (*putc)(uint8_t c);        // Send one byte
    uint8_t (*getc)(void);          // Receive one byte (blocking)
} simple_callbacks_t;

//===============================================================================
// Error Codes
//===============================================================================

typedef enum {
    SIMPLE_OK = 0,
    SIMPLE_ERROR_CRC = 1,
    SIMPLE_ERROR_SIZE = 2,
    SIMPLE_ERROR_CANCEL = 3
} simple_error_t;

//===============================================================================
// API Functions
//===============================================================================

// Receive file from host
// Returns number of bytes received on success, negative error code on failure
int32_t simple_receive(simple_callbacks_t *callbacks, uint8_t *buffer, uint32_t max_size);

// Send file to host
// Returns 0 on success, negative error code on failure
simple_error_t simple_send(simple_callbacks_t *callbacks, const uint8_t *buffer, uint32_t size);

#endif // SIMPLE_UPLOAD_H
