# C Library Syscalls Implementation

## Overview

Complete syscalls implementation for UART-based I/O, enabling standard C library functions on bare-metal RISC-V.

## Files

### Core Library
- **`lib/syscalls.c`** - Complete syscalls implementation
  - `_write()` - UART TX (for printf, puts, etc.)
  - `_read()` - UART RX (for scanf, getchar, etc.)
  - `_sbrk()` - Heap management (for malloc/free)
  - `_fstat()`, `_isatty()`, `_lseek()`, `_close()` - File operations
  - `_exit()`, `_kill()`, `_getpid()` - Process control stubs

### Test Programs

#### `firmware/interactive_test.c` - **RECOMMENDED**
Interactive menu-driven test that waits for terminal connection before starting.

**Features:**
- Waits for user keypress before starting (ensures terminal is connected)
- Interactive menu with 6 test options
- Tests: string output, number formatting, character echo, line input, performance
- Proper UART flow control

**Usage:**
```bash
# Build
cd firmware
make interactive_test

# Upload
fw_upload interactive_test.bin

# Connect terminal
minicom -D /dev/ttyUSB0 -b 115200
# Press any key to start
```

#### `firmware/syscall_test.c` - Quick Test
Non-interactive test that runs automatically on boot. Good for quick verification but output may be missed if terminal connects late.

## Build Requirements

### Verified Configuration ✓

```makefile
CC = riscv64-unknown-elf-gcc
ARCH = rv32im
ABI = ilp32
CFLAGS = -march=$(ARCH) -mabi=$(ABI) -O2 -g -nostartfiles -nostdlib -ffreestanding -fno-builtin
LDFLAGS = -T linker.ld -static -Wl,-Map=$(TARGET).map
LIBS = -lgcc
```

### Build Command
```bash
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 -g \
    -nostartfiles -nostdlib -ffreestanding -fno-builtin \
    -T linker.ld start.S interactive_test.c syscalls.o \
    -static -lgcc -Wl,-Map=interactive_test.map \
    -o interactive_test.elf

riscv64-unknown-elf-objcopy -O binary interactive_test.elf interactive_test.bin
riscv64-unknown-elf-objdump -D -S interactive_test.elf > interactive_test.lst
```

## Memory Layout Verification

### Symbol Table (from `nm -n`)
```
00000000 T _start           # Entry point
00000010 T irq_vec          # IRQ handler (MUST be at 0x10)
000000a4 t init_start       # Initialization
000000cc W irq_handler      # Weak IRQ handler
00001a40 B __bss_start      # BSS section
00001a44 B __bss_end
00001a44 B __heap_start     # Heap: 0x1a44 - 0x42000 (262KB)
00042000 B __heap_end
00080000 B __stack_top      # Stack: 0x42000 - 0x80000 (248KB)
```

### Program Size
```
text:   6716 bytes  (code + rodata)
data:      4 bytes  (initialized data)
bss:       4 bytes  (uninitialized data)
Total:  6724 bytes  (~6.6 KB)
```

## Start.S Interrupt Handler

**✓ Verified:** Full register preservation

The IRQ handler saves and restores ALL caller-saved registers:
- `ra` - Return address
- `a0-a7` - Argument/return registers
- `t0-t6` - Temporary registers

**Critical:** The handler is positioned at 0x00000010 (PROGADDR_IRQ) as required by PicoRV32.

```assembly
irq_vec:
    # Save registers (64 bytes on stack)
    addi sp, sp, -64
    sw ra,  0(sp)
    sw a0,  4(sp)
    ...
    sw t6, 60(sp)

    # Get IRQ mask and call C handler
    .insn r 0x0B, 4, 0, a0, x1, x0  # getq a0, q1
    call irq_handler

    # Restore registers
    lw ra,  0(sp)
    ...
    addi sp, sp, 64

    # Return from interrupt
    .insn r 0x0B, 0, 2, x0, x0, x0  # retirq
```

## Linker Script Review

**✓ Verified:** Correct memory regions and section placement

```ld
MEMORY {
    APPSRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
    STACK (rw)    : ORIGIN = 0x00042000, LENGTH = 248K
}

SECTIONS {
    .text : { *(.text.start) *(.text*) } > APPSRAM
    .rodata : { *(.rodata*) } > APPSRAM
    .data : { *(.data*) } > APPSRAM
    .bss : { *(.bss*) } > APPSRAM

    __heap_start = ALIGN(., 4);
    __heap_end = ORIGIN(STACK);
    __stack_top = ORIGIN(STACK) + LENGTH(STACK);
}
```

## Static Linking

**✓ Libraries Linked:**
- `syscalls.o` - Our syscalls implementation
- `libgcc.a` - GCC runtime support (integer division, etc.)

**Note:** We do NOT link full newlib (`-lc`) because:
1. Avoids 30+ minute build time
2. Only need syscalls, not full libc
3. Our minimal syscalls are sufficient for basic I/O
4. Can add printf later by building newlib separately if needed

## UART Register Map

```c
#define UART_TX_DATA   (*(volatile uint32_t*)0x80000000)
#define UART_TX_STATUS (*(volatile uint32_t*)0x80000004)  // bit 0: busy
#define UART_RX_DATA   (*(volatile uint32_t*)0x80000008)
#define UART_RX_STATUS (*(volatile uint32_t*)0x8000000C)  // bit 0: empty
```

## Testing Procedure

1. **Build:**
   ```bash
   cd firmware
   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 -g \
       -nostartfiles -nostdlib -ffreestanding -fno-builtin \
       -T linker.ld start.S interactive_test.c syscalls.o \
       -static -lgcc -Wl,-Map=interactive_test.map \
       -o interactive_test.elf

   riscv64-unknown-elf-objcopy -O binary interactive_test.elf interactive_test.bin
   ```

2. **Upload:**
   ```bash
   fw_upload interactive_test.bin
   ```

3. **Connect Terminal:**
   ```bash
   minicom -D /dev/ttyUSB0 -b 115200
   # or
   screen /dev/ttyUSB0 115200
   ```

4. **Run Tests:**
   - Press any key to start
   - Follow menu prompts
   - Test string output, numbers, echo, line input, performance

## Expected Output

```
========================================
  Interactive Syscall Test
  UART I/O via _read/_write syscalls
========================================

Press any key to start...
[user presses key]

Terminal connected!

========================================
  Interactive Syscall Test Menu
========================================
1. String Output Test
2. Number Output Test
3. Character Echo Test
4. Line Input Test
5. Performance Test
6. Show this menu
q. Quit (infinite loop)
========================================
Select option:
```

## Future Enhancements

To enable full `printf()/scanf()` support:

1. **Option A:** Use pre-built newlib (if available for rv32im)
2. **Option B:** Build newlib from source (completed clone in `lib/newlib/`)
   ```bash
   cd lib/newlib-build
   ../newlib/configure --target=riscv64-unknown-elf \
       --prefix=$PWD/../riscv-newlib \
       --enable-newlib-nano-malloc \
       --enable-newlib-nano-formatted-io \
       --disable-newlib-supplied-syscalls \
       CFLAGS_FOR_TARGET="-march=rv32im -mabi=ilp32 -O2 -g"
   make -j4
   make install
   ```

3. **Link with newlib:**
   ```bash
   CFLAGS += -isystem ../lib/riscv-newlib/riscv64-unknown-elf/include
   LDFLAGS += -L../lib/riscv-newlib/riscv64-unknown-elf/lib/rv32im/ilp32
   LIBS = -lc -lm -lgcc
   ```

## Verification Checklist

- ✅ `.bin` file generated for fw_upload
- ✅ `.lst` disassembly listing generated
- ✅ `.map` linker map generated
- ✅ Static linking with libgcc.a
- ✅ start.S IRQ handler preserves all registers
- ✅ IRQ vector at 0x00000010 (verified in listing)
- ✅ Linker script memory layout correct
- ✅ Interactive menu waits for terminal connection
- ✅ Heap and stack regions properly defined
- ✅ All syscalls implemented (read/write/sbrk/etc.)

## Success Criteria

Program is ready for hardware testing when:
1. Binary size < 10KB ✓ (6.6KB)
2. Memory layout verified ✓
3. Static linking complete ✓
4. Listings generated ✓
5. Interactive menu implemented ✓
6. IRQ handler verified ✓

**Status: READY FOR HARDWARE TESTING** 🚀
