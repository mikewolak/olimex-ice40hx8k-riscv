//===============================================================================
// Minimal ZMODEM Protocol Implementation
//
// Copyright (c) 2025 Michael Wolak
// Licensed under MIT License (see zmodem.h for full text)
//===============================================================================

#include "zmodem.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

//==============================================================================
// CRC-16 Implementation (CCITT polynomial 0x1021, used for headers)
//==============================================================================

static uint16_t crc16_table[256];
static int crc16_table_initialized = 0;

static void zm_crc16_init(void) {
    if (crc16_table_initialized) return;

    for (uint16_t i = 0; i < 256; i++) {
        uint16_t crc = i << 8;
        for (int j = 0; j < 8; j++) {
            crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) : (crc << 1);
        }
        crc16_table[i] = crc;
    }
    crc16_table_initialized = 1;
}

static uint16_t zm_crc16(const uint8_t *data, size_t len) {
    zm_crc16_init();

    uint16_t crc = 0;
    for (size_t i = 0; i < len; i++) {
        crc = (crc << 8) ^ crc16_table[((crc >> 8) ^ data[i]) & 0xFF];
    }
    return crc;
}

//==============================================================================
// CRC-32 Implementation (CCITT polynomial 0xEDB88320, used for data)
//==============================================================================

static uint32_t crc32_table[256];
static int crc32_table_initialized = 0;

static void zm_crc32_init(void) {
    if (crc32_table_initialized) return;

    for (uint32_t i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (int j = 0; j < 8; j++) {
            crc = (crc & 1) ? ((crc >> 1) ^ 0xEDB88320) : (crc >> 1);
        }
        crc32_table[i] = crc;
    }
    crc32_table_initialized = 1;
}

uint32_t zm_crc32(const uint8_t *data, size_t len) {
    zm_crc32_init();

    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    }
    return ~crc;
}

//==============================================================================
// ZDLE Encoding/Decoding
//==============================================================================

// Check if character needs ZDLE escaping
static int zm_needs_escape(uint8_t c) {
    // Frame-end markers must be escaped to avoid confusion with control codes
    if (c == ZCRCE || c == ZCRCG || c == ZCRCQ || c == ZCRCW) {
        return 1;
    }
    return (c == ZDLE || c == 0x8D || c == 0x8D ||
            c == XON || c == XOFF || c == (XON | 0x80) || c == (XOFF | 0x80) ||
            c == CAN || c < 0x20);
}

// Send byte with ZDLE escaping if needed
static void zm_send_escaped(zm_ctx_t *ctx, uint8_t c) {
    if (zm_needs_escape(c)) {
        fprintf(stderr, "[ESC_SEND] %02X (escaped)\n", c);
        ctx->callbacks.putc(ZDLE);
        c ^= 0x40;
    } else {
        fprintf(stderr, "[ESC_SEND] %02X (raw)\n", c);
    }
    ctx->callbacks.putc(c);
}

// Receive byte with ZDLE de-escaping
static int zm_recv_escaped(zm_ctx_t *ctx, uint32_t timeout_ms) {
    int c = ctx->callbacks.getc(timeout_ms);
    fprintf(stderr, "[ESC_RECV] Got %02X\n", c & 0xFF);
    if (c < 0) return c;  // Timeout

    if (c == ZDLE) {
        c = ctx->callbacks.getc(timeout_ms);
        fprintf(stderr, "[ESC_RECV] After ZDLE: %02X\n", c & 0xFF);
        if (c < 0) return c;

        // Handle special sequences
        if (c == CAN || c == ZDLE || c == (CAN | 0x40)) {
            ctx->can_count++;
            if (ctx->can_count >= 5) return ZM_CANCEL;
        } else {
            ctx->can_count = 0;
        }

        // Frame end markers are NOT XOR'd, they're special control codes
        // Return them with 0x100 bit set to distinguish from escaped data
        if (c == ZCRCE || c == ZCRCG || c == ZCRCQ || c == ZCRCW) {
            return 0x100 | c;  // Flag as control code
        }

        // De-escape: ZDLE + (byte ^ 0x40) -> byte
        if (c == ZRUB0) return 0x7F;
        if (c == ZRUB1) return 0xFF;
        return c ^ 0x40;
    }

    ctx->can_count = 0;
    return c;
}

//==============================================================================
// Hex Encoding (for headers)
//==============================================================================

static const char hex_digits[] = "0123456789abcdef";

static void zm_send_hex_byte(zm_ctx_t *ctx, uint8_t b) {
    ctx->callbacks.putc(hex_digits[(b >> 4) & 0x0F]);
    ctx->callbacks.putc(hex_digits[b & 0x0F]);
}

static int zm_recv_hex_nibble(zm_ctx_t *ctx, uint32_t timeout_ms) {
    int c = ctx->callbacks.getc(timeout_ms);
    if (c < 0) return c;

    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;  // Invalid hex digit
}

static int zm_recv_hex_byte(zm_ctx_t *ctx, uint32_t timeout_ms) {
    int high = zm_recv_hex_nibble(ctx, timeout_ms);
    if (high < 0) return high;

    int low = zm_recv_hex_nibble(ctx, timeout_ms);
    if (low < 0) return low;

    return (high << 4) | low;
}

//==============================================================================
// Header Transmission
//==============================================================================

zm_error_t zm_send_header(zm_ctx_t *ctx, uint8_t type, uint32_t arg) {
    fprintf(stderr, "[TX] type=%02X arg=%08X\n", type, arg);
    // Send ZPAD * 2 + ZDLE + header type indicator (ZHEX for simplicity)
    ctx->callbacks.putc(ZPAD);
    ctx->callbacks.putc(ZPAD);
    ctx->callbacks.putc(ZDLE);
    ctx->callbacks.putc(ZHEX);

    // Send header type
    zm_send_hex_byte(ctx, type);

    // Send 4-byte argument (little endian)
    uint8_t header[5];
    header[0] = type;
    header[1] = arg & 0xFF;
    header[2] = (arg >> 8) & 0xFF;
    header[3] = (arg >> 16) & 0xFF;
    header[4] = (arg >> 24) & 0xFF;

    zm_send_hex_byte(ctx, header[1]);
    zm_send_hex_byte(ctx, header[2]);
    zm_send_hex_byte(ctx, header[3]);
    zm_send_hex_byte(ctx, header[4]);

    // Calculate and send CRC-16 of header
    uint16_t crc = zm_crc16(header, 5);
    zm_send_hex_byte(ctx, (crc >> 8) & 0xFF);
    zm_send_hex_byte(ctx, crc & 0xFF);

    // End with CR + LF (+ XON if requested)
    ctx->callbacks.putc('\r');
    ctx->callbacks.putc('\n');
    if (type != ZFIN && type != ZACK) {
        ctx->callbacks.putc(XON);  // Resume transmission
    }

    return ZM_OK;
}

zm_error_t zm_recv_header(zm_ctx_t *ctx, zm_header_t *header) {
    uint32_t start_time = ctx->callbacks.gettime();
    int c;

    // Wait for ZPAD
    while (1) {
        c = ctx->callbacks.getc(ZM_TIMEOUT_INIT);
        if (c < 0) {
            fprintf(stderr, "[RX_ERR] Timeout waiting for ZPAD\n");
            return ZM_TIMEOUT;
        }
        if (c == ZPAD) break;

        // Check timeout
        if ((ctx->callbacks.gettime() - start_time) > ZM_TIMEOUT_INIT) {
            fprintf(stderr, "[RX_ERR] Init timeout\n");
            return ZM_TIMEOUT;
        }
    }

    // Expect another ZPAD
    c = ctx->callbacks.getc(ZM_TIMEOUT_CHAR);
    if (c != ZPAD) {
        fprintf(stderr, "[RX_ERR] Expected 2nd ZPAD, got %02X\n", c);
        return ZM_PROTOCOL_ERROR;
    }

    // Expect ZDLE
    c = ctx->callbacks.getc(ZM_TIMEOUT_CHAR);
    if (c != ZDLE) {
        fprintf(stderr, "[RX_ERR] Expected ZDLE, got %02X\n", c);
        return ZM_PROTOCOL_ERROR;
    }

    // Get header format (ZHEX, ZBIN, or ZBIN32)
    c = ctx->callbacks.getc(ZM_TIMEOUT_CHAR);
    if (c < 0) {
        fprintf(stderr, "[RX_ERR] Timeout reading format\n");
        return ZM_TIMEOUT;
    }
    fprintf(stderr, "[RX_DEBUG] Format byte: %02X\n", c);
    if (c == ZHEX) {
        // Hex header - receive type + 4 bytes + 2 byte CRC
        int type = zm_recv_hex_byte(ctx, ZM_TIMEOUT_CHAR);
        if (type < 0) return ZM_TIMEOUT;

        uint8_t hdr[5];
        hdr[0] = type;
        for (int i = 1; i < 5; i++) {
            int b = zm_recv_hex_byte(ctx, ZM_TIMEOUT_CHAR);
            if (b < 0) return ZM_TIMEOUT;
            hdr[i] = b;
        }

        // Read CRC
        int crc_high = zm_recv_hex_byte(ctx, ZM_TIMEOUT_CHAR);
        int crc_low = zm_recv_hex_byte(ctx, ZM_TIMEOUT_CHAR);
        if (crc_high < 0 || crc_low < 0) return ZM_TIMEOUT;

        // Verify CRC
        uint16_t received_crc = (crc_high << 8) | crc_low;
        uint16_t calculated_crc = zm_crc16(hdr, 5);
        if (received_crc != calculated_crc) {
            return ZM_CRC_ERROR;
        }

        // Skip CR/LF
        ctx->callbacks.getc(ZM_TIMEOUT_CHAR);
        ctx->callbacks.getc(ZM_TIMEOUT_CHAR);

        // Parse header
        header->type = hdr[0];
        header->arg = hdr[1] | (hdr[2] << 8) | (hdr[3] << 16) | (hdr[4] << 24);

        // Skip XON if present (sent after most headers except ZFIN/ZACK)
        if (header->type != ZFIN && header->type != ZACK) {
            int xon = ctx->callbacks.getc(ZM_TIMEOUT_CHAR);
            if (xon != XON) {
                // Hmm, wasn't XON - this might be a problem, but continue
                fprintf(stderr, "[RX_WARN] Expected XON, got %02X\n", xon);
            }
        }

        fprintf(stderr, "[RX] type=%02X arg=%08X\n", header->type, header->arg);
        return ZM_OK;
    }

    return ZM_PROTOCOL_ERROR;  // Binary headers not yet implemented
}

//==============================================================================
// Data Transmission
//==============================================================================

zm_error_t zm_send_data(zm_ctx_t *ctx, const uint8_t *data, uint16_t len,
                        uint8_t frame_end) {
    fprintf(stderr, "[SEND_DATA] len=%d frame_end=%02X\n", len, frame_end);
    // Send data with ZDLE escaping
    for (uint16_t i = 0; i < len; i++) {
        zm_send_escaped(ctx, data[i]);
    }

    // Send frame end type
    fprintf(stderr, "[TX_FRAME_END] Sending ZDLE + %02X\n", frame_end);
    ctx->callbacks.putc(ZDLE);
    ctx->callbacks.putc(frame_end);

    // Calculate and send CRC-16 (data + frame_end)
    // In hex header mode, data subpackets use CRC-16
    zm_crc16_init();
    uint16_t crc = 0;
    for (uint16_t i = 0; i < len; i++) {
        crc = (crc << 8) ^ crc16_table[((crc >> 8) ^ data[i]) & 0xFF];
    }
    // Include frame_end in CRC
    crc = (crc << 8) ^ crc16_table[((crc >> 8) ^ frame_end) & 0xFF];

    fprintf(stderr, "[TX_CRC] Calculated CRC=%04X for %d bytes + frame_end %02X\n", crc, len, frame_end);
    zm_send_escaped(ctx, (crc >> 8) & 0xFF);
    zm_send_escaped(ctx, crc & 0xFF);

    return ZM_OK;
}

zm_error_t zm_recv_data(zm_ctx_t *ctx, uint8_t *buffer, uint16_t *len, uint8_t *frame_end) {
    uint16_t count = 0;
    uint8_t frame_end_byte = 0;

    fprintf(stderr, "[RECV_DATA] Starting...\n");
    while (count < ZM_MAX_BLOCK) {
        int c = zm_recv_escaped(ctx, ZM_TIMEOUT_DATA);
        if (c < 0) {
            fprintf(stderr, "[RECV_DATA] zm_recv_escaped returned %d\n", c);
            return (c == ZM_CANCEL) ? ZM_CANCEL : ZM_TIMEOUT;
        }

        // Check for frame end (control codes have 0x100 bit set)
        if (c & 0x100) {
            frame_end_byte = c & 0xFF;
            fprintf(stderr, "[RECV_DATA] Got frame_end control code: %02X\n", frame_end_byte);
            break;
        }

        buffer[count++] = c;
    }

    // If loop exited due to reaching max block size, read frame_end now
    if (frame_end_byte == 0) {
        int c = zm_recv_escaped(ctx, ZM_TIMEOUT_DATA);
        if (c < 0) return ZM_TIMEOUT;
        if (c & 0x100) {
            frame_end_byte = c & 0xFF;
            fprintf(stderr, "[RECV_DATA] Got frame_end after max block: %02X\n", frame_end_byte);
        } else {
            fprintf(stderr, "[RECV_DATA_ERR] Expected frame_end, got data: %02X\n", c);
            return ZM_PROTOCOL_ERROR;
        }
    }

    // Read CRC-16 (2 bytes)
    // In hex header mode, data subpackets use CRC-16
    int crc_high = zm_recv_escaped(ctx, ZM_TIMEOUT_DATA);
    int crc_low = zm_recv_escaped(ctx, ZM_TIMEOUT_DATA);
    if (crc_high < 0 || crc_low < 0) return ZM_TIMEOUT;
    uint16_t rx_crc = (crc_high << 8) | crc_low;

    // Verify CRC-16 (data + frame_end)
    fprintf(stderr, "[CRC_CHECK] count=%d frame_end=%02X\n", count, frame_end_byte);
    for (uint16_t i = 0; i < count && i < 20; i++) {
        fprintf(stderr, "  [%d]=%02X\n", i, buffer[i]);
    }

    zm_crc16_init();
    uint16_t calc_crc = 0;
    for (uint16_t i = 0; i < count; i++) {
        calc_crc = (calc_crc << 8) ^ crc16_table[((calc_crc >> 8) ^ buffer[i]) & 0xFF];
    }
    // Include frame_end in CRC
    calc_crc = (calc_crc << 8) ^ crc16_table[((calc_crc >> 8) ^ frame_end_byte) & 0xFF];

    if (rx_crc != calc_crc) {
        fprintf(stderr, "[DATA_CRC_ERR] Got %04X, expected %04X\n", rx_crc, calc_crc);
        return ZM_CRC_ERROR;
    }

    *len = count;
    *frame_end = frame_end_byte;
    return ZM_OK;
}

//==============================================================================
// Initialization
//==============================================================================

void zm_init(zm_ctx_t *ctx, const zm_callbacks_t *callbacks) {
    memset(ctx, 0, sizeof(zm_ctx_t));
    ctx->callbacks = *callbacks;
    ctx->flags = CANFDX | CANFC32 | ESCCTL;  // Our capabilities
    zm_crc32_init();
}

//==============================================================================
// Auto-start Sequence
//==============================================================================

void zm_send_autostart(zm_ctx_t *ctx) {
    // Send ZRQINIT to trigger terminal auto-start
    zm_send_header(ctx, ZRQINIT, 0);
}

//==============================================================================
// Cancel Transfer
//==============================================================================

void zm_cancel(zm_ctx_t *ctx) {
    // Send 8 CAN characters followed by 8 backspaces
    for (int i = 0; i < 8; i++) {
        ctx->callbacks.putc(CAN);
    }
    for (int i = 0; i < 8; i++) {
        ctx->callbacks.putc('\b');
    }
}

//==============================================================================
// High-level File Send
//==============================================================================

zm_error_t zm_send_file(zm_ctx_t *ctx, const uint8_t *data, uint32_t size,
                        const char *filename) {
    zm_header_t hdr;
    zm_error_t err;

    // Store file info
    ctx->file_size = size;
    ctx->file_pos = 0;

    // Send ZRQINIT to start session
    zm_send_autostart(ctx);

    // Wait for ZRINIT from receiver
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;
    if (hdr.type != ZRINIT) return ZM_PROTOCOL_ERROR;

    // Store receiver capabilities
    ctx->flags = hdr.arg & 0xFF;

    // Send ZFILE header with filename
    zm_send_header(ctx, ZFILE, 0);

    // Send filename + null + file size + null in data subpacket
    uint8_t file_info[ZM_MAX_FILENAME];
    int info_len = 0;

    if (filename) {
        strncpy((char*)file_info, filename, ZM_MAX_FILENAME - 20);
        info_len = strlen((char*)file_info) + 1;
    } else {
        file_info[info_len++] = 0;  // Empty filename
    }

    // Add file size as decimal string
    info_len += snprintf((char*)&file_info[info_len], 20, "%lu", (unsigned long)size) + 1;

    zm_send_data(ctx, file_info, info_len, ZCRCW);

    // Wait for ZRPOS or ZSKIP
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;

    if (hdr.type == ZSKIP) return ZM_OK;  // File skipped
    if (hdr.type != ZRPOS) return ZM_PROTOCOL_ERROR;

    // Send ZDATA header
    zm_send_header(ctx, ZDATA, ctx->file_pos);

    // Send file data in blocks
    while (ctx->file_pos < size) {
        uint32_t remaining = size - ctx->file_pos;
        uint16_t block_size = (remaining > ZM_MAX_BLOCK) ? ZM_MAX_BLOCK : remaining;

        // Determine frame end type
        uint8_t frame_end;
        if (ctx->file_pos + block_size >= size) {
            frame_end = ZCRCE;  // Last block
        } else {
            frame_end = ZCRCG;  // More blocks follow
        }

        err = zm_send_data(ctx, &data[ctx->file_pos], block_size, frame_end);
        if (err != ZM_OK) return err;

        ctx->file_pos += block_size;
    }

    // Send ZEOF
    zm_send_header(ctx, ZEOF, size);

    // Wait for ZRINIT (receiver ready for next file)
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;

    // Send ZFIN to end session
    zm_send_header(ctx, ZFIN, 0);

    // Wait for ZFIN from receiver
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;

    // Send OO to complete
    ctx->callbacks.putc('O');
    ctx->callbacks.putc('O');

    return ZM_OK;
}

//==============================================================================
// High-level File Receive
//==============================================================================

zm_error_t zm_receive_file(zm_ctx_t *ctx, uint8_t *buffer, uint32_t max_size,
                           uint32_t *bytes_received, char *filename) {
    zm_header_t hdr;
    zm_error_t err;

    *bytes_received = 0;
    ctx->file_pos = 0;

    // Wait for ZRQINIT from sender
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;
    if (hdr.type != ZRQINIT) return ZM_PROTOCOL_ERROR;

    // Send ZRINIT with our capabilities
    zm_send_header(ctx, ZRINIT, ctx->flags);

    // Wait for ZFILE
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;
    if (hdr.type != ZFILE) return ZM_PROTOCOL_ERROR;

    // Receive filename and file info
    uint8_t file_info[ZM_MAX_FILENAME];
    uint16_t info_len;
    uint8_t file_info_frame_end;
    err = zm_recv_data(ctx, file_info, &info_len, &file_info_frame_end);
    if (err != ZM_OK) return err;

    // Parse filename if requested
    if (filename) {
        strncpy(filename, (char*)file_info, ZM_MAX_FILENAME);
    }

    // Send ZRPOS to start at beginning
    zm_send_header(ctx, ZRPOS, 0);

    // Wait for ZDATA
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;
    if (hdr.type != ZDATA) return ZM_PROTOCOL_ERROR;

    // Receive data blocks
    while (1) {
        uint16_t block_len;
        uint8_t block_frame_end;
        err = zm_recv_data(ctx, &buffer[ctx->file_pos], &block_len, &block_frame_end);
        if (err != ZM_OK) return err;

        ctx->file_pos += block_len;
        if (ctx->file_pos > max_size) return ZM_FILE_ERROR;

        fprintf(stderr, "[RECV_FILE] Got block len=%u frame_end=%02X pos=%u\n",
                block_len, block_frame_end, ctx->file_pos);

        // Check frame_end to determine next action
        if (block_frame_end == ZCRCG) {
            // Frame continues nonstop - continue receiving data
            continue;
        } else if (block_frame_end == ZCRCE || block_frame_end == ZCRCW) {
            // Frame ends, header follows
            err = zm_recv_header(ctx, &hdr);
            if (err != ZM_OK) return err;

            if (hdr.type == ZEOF) break;
            if (hdr.type == ZDATA) continue;  // More data follows
            return ZM_PROTOCOL_ERROR;
        } else {
            fprintf(stderr, "[RECV_FILE_ERR] Unknown frame_end: %02X\n", block_frame_end);
            return ZM_PROTOCOL_ERROR;
        }
    }

    *bytes_received = ctx->file_pos;

    // Send ZRINIT to acknowledge
    zm_send_header(ctx, ZRINIT, ctx->flags);

    // Wait for ZFIN
    err = zm_recv_header(ctx, &hdr);
    if (err != ZM_OK) return err;
    if (hdr.type != ZFIN) return ZM_PROTOCOL_ERROR;

    // Send ZFIN to confirm
    zm_send_header(ctx, ZFIN, 0);

    // Wait for OO
    int c1 = ctx->callbacks.getc(ZM_TIMEOUT_CHAR);
    int c2 = ctx->callbacks.getc(ZM_TIMEOUT_CHAR);
    if (c1 != 'O' || c2 != 'O') return ZM_PROTOCOL_ERROR;

    return ZM_OK;
}
