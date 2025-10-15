//===============================================================================
// Minimal ZMODEM Protocol Implementation
//
// A clean-room implementation of the ZMODEM file transfer protocol optimized
// for embedded systems. Implements only essential features:
// - Auto-start capability (terminal detection)
// - Binary file send/receive
// - CRC-32 error checking
// - Timeout handling
//
// ZMODEM Protocol: Public Domain (Chuck Forsberg, 1986)
// This Implementation: Copyright (c) 2025 Michael Wolak
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//===============================================================================

#ifndef ZMODEM_H
#define ZMODEM_H

#include <stdint.h>
#include <stddef.h>

//==============================================================================
// ZMODEM Protocol Constants (from public domain specification)
//==============================================================================

// Frame characters
#define ZPAD        '*'     // 0x2A - Padding character
#define ZDLE        0x18    // Ctrl-X - Data Link Escape
#define ZDLEE       (ZDLE ^ 0x40)  // Escaped ZDLE

// Header types (first byte after ZDLE)
#define ZHEX        'B'     // HEX header follows
#define ZBIN        'A'     // Binary header follows
#define ZBIN32      'C'     // Binary header with CRC-32

// Frame types
#define ZRQINIT     0       // Request receive init (sent by sender)
#define ZRINIT      1       // Receive init (sent by receiver)
#define ZSINIT      2       // Send init sequence (optional)
#define ZACK        3       // ACK to ZRQINIT/ZRINIT/ZSINIT
#define ZFILE       4       // File name from sender
#define ZSKIP       5       // Skip this file
#define ZNAK        6       // Last packet was garbled
#define ZABORT      7       // Abort batch transfers
#define ZFIN        8       // Finish session
#define ZRPOS       9       // Resume file transmission at this position
#define ZDATA       10      // Data packet(s) follow
#define ZEOF        11      // End of file
#define ZFERR       12      // Fatal read or write error
#define ZCRC        13      // Request for file CRC and response
#define ZCHALLENGE  14      // Security challenge
#define ZCOMPL      15      // Request is complete
#define ZCAN        16      // Pseudo frame - Cancel (two CAN characters)
#define ZFREECNT    17      // Request free bytes on filesystem
#define ZCOMMAND    18      // Command from sending program

// ZRINIT flags (ZF0)
#define CANFDX      0x01    // Receiver can send and receive simultaneously
#define CANOVIO     0x02    // Receiver can receive data during disk I/O
#define CANBRK      0x04    // Receiver can send a break signal
#define CANCRY      0x08    // Receiver can decrypt
#define CANLZW      0x10    // Receiver can uncompress
#define CANFC32     0x20    // Receiver can use 32-bit CRC
#define ESCCTL      0x40    // Receiver expects control chars to be escaped
#define ESC8        0x80    // Receiver expects 8th bit to be escaped

// ZFILE transfer flags (ZF0)
#define ZCBIN       1       // Binary transfer
#define ZCNL        2       // Convert NL to local end of line convention
#define ZCRESUM     3       // Resume interrupted file transfer

// ZFILE management options (ZF1)
#define ZMNEW       1       // Transfer if source newer or longer
#define ZMCRC       2       // Transfer if different CRC or length
#define ZMAPND      3       // Append to existing file
#define ZMCLOB      4       // Replace existing file
#define ZMNEWL      5       // Transfer if source newer or longer
#define ZMDIFF      6       // Transfer if different
#define ZMPROT      7       // Protect: don't transfer if dest exists

// Data subpacket types
#define ZCRCE       'h'     // CRC next, frame ends, header follows
#define ZCRCG       'i'     // CRC next, frame continues nonstop
#define ZCRCQ       'j'     // CRC next, frame continues, ZACK expected
#define ZCRCW       'k'     // CRC next, frame ends, ZACK expected
#define ZRUB0       'l'     // Translate to rubout 0177
#define ZRUB1       'm'     // Translate to rubout 0377

// Escape sequences
#define XON         0x11    // Ctrl-Q
#define XOFF        0x13    // Ctrl-S
#define CAN         0x18    // Ctrl-X (same as ZDLE)

// Timeouts (milliseconds)
#define ZM_TIMEOUT_INIT     30000   // 30 seconds for init
#define ZM_TIMEOUT_DATA     5000    // 5 seconds for data
#define ZM_TIMEOUT_CHAR     1000    // 1 second between characters

// Buffer sizes
#define ZM_MAX_BLOCK        1024    // Maximum data block size
#define ZM_HEADER_LEN       5       // Header: type + 4 bytes
#define ZM_MAX_FILENAME     256     // Maximum filename length

//==============================================================================
// ZMODEM Error Codes
//==============================================================================

typedef enum {
    ZM_OK = 0,              // Success
    ZM_ERROR = -1,          // Generic error
    ZM_TIMEOUT = -2,        // Timeout waiting for data
    ZM_CANCEL = -3,         // Transfer cancelled by remote
    ZM_CRC_ERROR = -4,      // CRC check failed
    ZM_FILE_ERROR = -5,     // File I/O error
    ZM_PROTOCOL_ERROR = -6, // Protocol violation
    ZM_NO_CARRIER = -7,     // Lost connection
    ZM_ABORTED = -8         // Aborted by user
} zm_error_t;

//==============================================================================
// ZMODEM Header Structure
//==============================================================================

typedef struct {
    uint8_t type;           // Frame type (ZRQINIT, ZFILE, etc.)
    uint32_t arg;           // 4-byte argument (position, flags, etc.)
} zm_header_t;

//==============================================================================
// ZMODEM Callbacks
//
// These must be implemented by the application to provide UART I/O
// and timeout handling.
//==============================================================================

// Get one byte with timeout (return -1 on timeout)
typedef int (*zm_getc_fn)(uint32_t timeout_ms);

// Send one byte
typedef void (*zm_putc_fn)(uint8_t c);

// Get current time in milliseconds (for timeouts)
typedef uint32_t (*zm_gettime_fn)(void);

// Callback structure
typedef struct {
    zm_getc_fn getc;        // Get byte with timeout
    zm_putc_fn putc;        // Put byte
    zm_gettime_fn gettime;  // Get timestamp
} zm_callbacks_t;

//==============================================================================
// ZMODEM Transfer Context
//==============================================================================

typedef struct {
    zm_callbacks_t callbacks;   // I/O callbacks
    uint32_t file_size;         // Size of file being transferred
    uint32_t file_pos;          // Current position in file
    uint8_t last_rx;            // Last received character
    uint8_t can_count;          // Count of consecutive CAN characters
    uint8_t flags;              // Receiver capability flags
} zm_ctx_t;

//==============================================================================
// ZMODEM API Functions
//==============================================================================

// Initialize ZMODEM context
void zm_init(zm_ctx_t *ctx, const zm_callbacks_t *callbacks);

// Send a file via ZMODEM
// data: pointer to file data in memory
// size: size of data in bytes
// filename: name to send (can be NULL for memory transfer)
// Returns: ZM_OK on success, error code on failure
zm_error_t zm_send_file(zm_ctx_t *ctx, const uint8_t *data, uint32_t size,
                        const char *filename);

// Receive a file via ZMODEM
// buffer: buffer to store received data
// max_size: maximum size of buffer
// bytes_received: output - actual number of bytes received
// filename: output - filename from sender (can be NULL)
// Returns: ZM_OK on success, error code on failure
zm_error_t zm_receive_file(zm_ctx_t *ctx, uint8_t *buffer, uint32_t max_size,
                           uint32_t *bytes_received, char *filename);

// Send auto-start sequence (ZRQINIT) to trigger terminal
void zm_send_autostart(zm_ctx_t *ctx);

// Cancel current transfer
void zm_cancel(zm_ctx_t *ctx);

//==============================================================================
// Low-level Protocol Functions (internal use)
//==============================================================================

// Send a header
zm_error_t zm_send_header(zm_ctx_t *ctx, uint8_t type, uint32_t arg);

// Receive a header
zm_error_t zm_recv_header(zm_ctx_t *ctx, zm_header_t *header);

// Send data block
zm_error_t zm_send_data(zm_ctx_t *ctx, const uint8_t *data, uint16_t len,
                        uint8_t frame_end);

// Receive data block
zm_error_t zm_recv_data(zm_ctx_t *ctx, uint8_t *buffer, uint16_t *len, uint8_t *frame_end);

// CRC-32 calculation
uint32_t zm_crc32(const uint8_t *data, size_t len);

#endif // ZMODEM_H
