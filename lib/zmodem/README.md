# Minimal ZMODEM Protocol Implementation

A clean-room implementation of the ZMODEM file transfer protocol optimized for embedded systems.

## Features

- ✅ **Auto-start capability** - Sends ZRQINIT sequence that modern terminals detect automatically
- ✅ **Binary file transfer** - Send and receive files in memory
- ✅ **CRC-32 error checking** - Robust error detection
- ✅ **Minimal footprint** - Only 728 lines of code total
- ✅ **No dynamic allocation** - Works in resource-constrained environments
- ✅ **Callback-based I/O** - Easy integration with UART or any serial port
- ✅ **MIT License** - Use freely in any project

## Code Size

```
zmodem.h: 232 lines (API + protocol constants)
zmodem.c: 496 lines (implementation)
Total:    728 lines
```

Compiled size: ~5-6KB (with -O2 optimization)

## Usage

### 1. Initialize Context

```c
#include "zmodem/zmodem.h"

// Implement callbacks for your UART
int my_getc(uint32_t timeout_ms) {
    // Return byte or -1 on timeout
}

void my_putc(uint8_t c) {
    // Send byte via UART
}

uint32_t my_gettime(void) {
    // Return current time in milliseconds
}

// Set up callbacks
zm_callbacks_t callbacks = {
    .getc = my_getc,
    .putc = my_putc,
    .gettime = my_gettime
};

// Initialize context
zm_ctx_t ctx;
zm_init(&ctx, &callbacks);
```

### 2. Send a File

```c
// Send memory buffer as file
const uint8_t *data = ...;  // Your data
uint32_t size = ...;         // Data size
const char *filename = "test.bin";

zm_error_t err = zm_send_file(&ctx, data, size, filename);
if (err == ZM_OK) {
    printf("Transfer complete!\n");
} else {
    printf("Transfer failed: %d\n", err);
}
```

**Terminal side:** Your terminal (minicom, TeraTerm, etc.) will auto-detect the ZMODEM transfer and prompt to save the file!

### 3. Receive a File

```c
// Receive file into buffer
uint8_t buffer[64*1024];  // 64KB buffer
uint32_t bytes_received;
char filename[256];

zm_error_t err = zm_receive_file(&ctx, buffer, sizeof(buffer),
                                  &bytes_received, filename);
if (err == ZM_OK) {
    printf("Received %u bytes: %s\n", bytes_received, filename);
} else {
    printf("Receive failed: %d\n", err);
}
```

## Auto-Start Feature

The key advantage of ZMODEM over XMODEM is **automatic terminal detection**:

```c
// This sends ZRQINIT which terminals automatically detect
zm_send_autostart(&ctx);

// Terminal will automatically:
// 1. Detect ZMODEM transfer
// 2. Prompt user for filename
// 3. Start receiving
// NO manual "Receive File" clicking required!
```

## Error Codes

```c
ZM_OK              // Success
ZM_ERROR           // Generic error
ZM_TIMEOUT         // Timeout waiting for data
ZM_CANCEL          // Transfer cancelled by remote
ZM_CRC_ERROR       // CRC check failed
ZM_FILE_ERROR      // File I/O error
ZM_PROTOCOL_ERROR  // Protocol violation
ZM_NO_CARRIER      // Lost connection
ZM_ABORTED         // Aborted by user
```

## Protocol Details

### Implemented Features:
- ZRQINIT/ZRINIT - Session initialization
- ZFILE - Filename transfer
- ZDATA - Data transfer with CRC-32
- ZEOF - End of file
- ZFIN - Session termination
- Hex headers (easy to debug)
- ZDLE escape encoding
- Auto-start sequence

### Not Implemented (for simplicity):
- Binary headers (hex only)
- File resume (crash recovery)
- Compression
- Encryption
- Multiple file batch transfer
- ZSINIT frames

## Integration with Hex Editor

Example usage in a hex editor with UART:

```c
// Upload memory range to PC
void hexedit_upload(uint32_t addr, uint32_t len) {
    zm_ctx_t ctx;
    zm_init(&ctx, &uart_callbacks);

    uint8_t *data = (uint8_t*)addr;
    char filename[32];
    snprintf(filename, sizeof(filename), "dump_%08X.bin", addr);

    zm_error_t err = zm_send_file(&ctx, data, len, filename);
    if (err != ZM_OK) {
        printf("Upload failed: %d\n", err);
    }
}

// Download file from PC to memory
void hexedit_download(uint32_t addr) {
    zm_ctx_t ctx;
    zm_init(&ctx, &uart_callbacks);

    uint32_t bytes_received;
    zm_error_t err = zm_receive_file(&ctx, (uint8_t*)addr, 256*1024,
                                      &bytes_received, NULL);
    if (err == ZM_OK) {
        printf("Downloaded %u bytes to 0x%08X\n", bytes_received, addr);
    } else {
        printf("Download failed: %d\n", err);
    }
}
```

## Testing

Compile for your host machine to test:

```bash
gcc -c zmodem.c -o zmodem.o
# Link with your test application
```

Test with standard ZMODEM tools:
- **Send**: `sz file.bin` (on PC) → Embedded receives
- **Receive**: Embedded sends → `rz` (on PC)

## License

MIT License - see zmodem.h for full text.

Copyright (c) 2025 Michael Wolak

**ZMODEM Protocol**: Public Domain (Chuck Forsberg, 1986)
**This Implementation**: Clean-room, original code

## References

- ZMODEM Protocol Specification (public domain)
- Chuck Forsberg's original rzsz (public domain version)
- No code copied from GPL implementations
