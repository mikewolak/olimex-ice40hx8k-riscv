# Olimex iCE40HX8K RISC-V Bootloader System

A complete RISC-V embedded system for the Olimex iCE40HX8K-EVB board featuring a BRAM-based bootloader, UART firmware upload, and field-updatable application code.

**Copyright (c) October 2025 Michael Wolak**
Email: mikewolak@gmail.com, mike@epromfoundry.com
**NOT FOR COMMERCIAL USE** - Educational and research purposes only

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Hardware Architecture](#hardware-architecture)
- [Boot Sequence](#boot-sequence)
- [Firmware Upload Protocol](#firmware-upload-protocol)
- [Build Instructions](#build-instructions)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Design Rationale](#design-rationale)
- [Resource Utilization](#resource-utilization)
- [Simulation](#simulation)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

This project implements a two-stage boot architecture on the iCE40HX8K FPGA:

1. **Stage 1**: Bootloader in read-only BRAM (initialized at synthesis time)
2. **Stage 2**: Application firmware in SRAM (uploaded via UART or pre-loaded)

The bootloader enables **field updates** without reprogramming the FPGA bitstream, making it ideal for embedded development and deployment.

---

## Key Features

- **PicoRV32 CPU**: Full RV32IM (32-register) RISC-V processor @ 50 MHz
  - Hardware multiply/divide instructions
  - Barrel shifter for single-cycle shifts
  - Interrupt support (IRQ)
- **Timer Peripheral**: STM32-style 32-bit down-counter ✅ Validated on hardware
  - Configurable prescaler for clock division (PSC register)
  - Auto-reload register for period control (ARR register)
  - Interrupt generation on counter expiry (10kHz rate tested)
  - Memory-mapped control registers (CR, SR, PSC, ARR)
- **Bootloader ROM**: 8KB BRAM initialized from `bootloader.hex` at synthesis
- **Firmware Upload**: UART-based protocol with CRC32 verification (PKZIP/IEEE 802.3)
- **Memory Controller**: Unified interface for SRAM, BRAM, and MMIO
- **512KB External SRAM**: K6R4016V1D-TC10 for application code and data
- **MMIO Peripherals**: UART, LEDs, buttons via memory-mapped registers
- **Efficient Design**: 61% logic utilization, 50% BRAM, capable of 60MHz

---

## Interrupt Handling

### Overview

This platform implements **hardware interrupt support** using PicoRV32's LATCHED_IRQ mode. The system includes:
- Timer peripheral generating periodic interrupts
- Assembly IRQ wrapper preserving CPU state
- Custom instructions for interrupt control
- Validated on FPGA hardware and in simulation

### IRQ Wrapper (firmware/start.S)

**Location**: `firmware/start.S:49-77`

The IRQ wrapper is a critical piece of assembly code that preserves CPU state when an interrupt fires. It **must save ALL caller-saved registers** to prevent register corruption.

**Assembly Implementation:**

```asm
.global irq_vec
.align 4
irq_vec:
    /* CRITICAL: Save ALL caller-saved registers (a0-a7, t0-t6, ra) */
    /* Interrupts can occur at any point - compiler may be using any register! */
    addi sp, sp, -64
    sw ra,  0(sp)
    sw a0,  4(sp)
    sw a1,  8(sp)
    sw a2, 12(sp)
    sw a3, 16(sp)   // CRITICAL: Don't skip any registers!
    sw a4, 20(sp)
    sw a5, 24(sp)
    sw a6, 28(sp)
    sw a7, 32(sp)
    sw t0, 36(sp)
    sw t1, 40(sp)
    sw t2, 44(sp)
    sw t3, 48(sp)
    sw t4, 52(sp)
    sw t5, 56(sp)
    sw t6, 60(sp)

    /* Call C interrupt handler */
    call irq_handler

    /* Restore ALL registers */
    lw ra,  0(sp)
    lw a0,  4(sp)
    lw a1,  8(sp)
    lw a2, 12(sp)
    lw a3, 16(sp)
    lw a4, 20(sp)
    lw a5, 24(sp)
    lw a6, 28(sp)
    lw a7, 32(sp)
    lw t0, 36(sp)
    lw t1, 40(sp)
    lw t2, 44(sp)
    lw t3, 48(sp)
    lw t4, 52(sp)
    lw t5, 56(sp)
    lw t6, 60(sp)
    addi sp, sp, 64

    /* Return from interrupt - re-enables IRQs */
    retirq
```

**Why This Matters:**

RISC-V has two classes of registers:
- **Caller-saved** (a0-a7, t0-t6, ra): Must be saved by interrupt handler
- **Callee-saved** (s0-s11): Preserved by called functions, not needed in IRQ wrapper

**The compiler can use any caller-saved register** during program execution. If the IRQ wrapper doesn't save them all, interrupts will corrupt register values and cause crashes.

**Bug Example**: Early implementation only saved 7 registers (ra, a0-a2, t0-t2). When the compiler used register `a3` for a loop variable, interrupts corrupted it, causing firmware to exit prematurely.

**Stack Frame**: 64 bytes (17 registers × 4 bytes, aligned)

### Custom PicoRV32 Instructions

PicoRV32 implements custom instructions for interrupt control using the RISC-V "custom-0" opcode space.

#### 1. Enable Interrupts (q0/q1/q2/q3)

**Instruction**: `.insn r 0x0B, 6, 3, %0, x0, x0`

**Usage in C:**
```c
static inline void irq_enable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, x0, x0" : "=r"(dummy));
}
```

**What it does:**
- Sets internal CPU flag to enable interrupt processing
- Must be called during firmware initialization
- Interrupts remain masked until this is called

**Details:**
- Opcode: `0x0B` (custom-0)
- Function codes: funct3=6, funct7=3
- This maps to PicoRV32's `q0` (getq/setq) instruction
- Result written to destination register (can be ignored)

#### 2. Return from Interrupt (retirq)

**Instruction**: `0x0400000b` (custom encoding)

**Usage in Assembly:**
```asm
retirq   # Automatically restores PC and re-enables interrupts
```

**What it does:**
- Restores program counter (PC) to pre-interrupt value
- Re-enables interrupts (single instruction, atomic)
- Must be the last instruction in IRQ wrapper

**Details:**
- Custom instruction recognized by PicoRV32 core
- Equivalent to: restore PC + enable IRQ flag
- In LATCHED_IRQ mode, IRQ line must be cleared before `retirq` or interrupt will immediately fire again

**Assembly Macro** (defined in `start.S`):
```asm
.macro retirq
    .word 0x0400000b
.endm
```

### Typical Interrupt Flow

```
1. Hardware asserts IRQ line (e.g., timer expires)
   └─→ CPU latches interrupt request

2. CPU finishes current instruction
   └─→ PC saved internally

3. CPU jumps to irq_vec (defined in start.S)
   └─→ IRQ wrapper saves all caller-saved registers to stack

4. IRQ wrapper calls C function irq_handler()
   └─→ Handler clears interrupt source (e.g., TIMER_SR = 1)
   └─→ Handler updates state (e.g., interrupt_count++)

5. C function returns to IRQ wrapper
   └─→ IRQ wrapper restores all registers from stack

6. IRQ wrapper executes 'retirq' instruction
   └─→ PC restored, interrupts re-enabled
   └─→ Execution continues from interrupted point
```

### Hardware Requirements

For interrupts to work, firmware must:

1. **Enable interrupts globally**: Call `irq_enable()` during init
2. **Configure peripheral**: Set timer PSC, ARR, enable bit
3. **Clear interrupt flags**: Write to peripheral status register in handler
4. **Use proper IRQ wrapper**: Save/restore all caller-saved registers

### Testing and Validation

See documentation for detailed test results:
- `docs/INTERRUPT_BUG_FIX.md` - Root cause analysis of register corruption bug
- `docs/FPGA_TEST_INSTRUCTIONS.md` - Hardware testing guide
- `sim/README_TIMER_TEST.md` - Simulation test instructions

**Status**: ✅ Timer interrupts validated at 100μs period (10kHz) on FPGA hardware

---

## Hardware Architecture

### Memory Map

| Address Range          | Region                  | Size   | Description                          |
|------------------------|-------------------------|--------|--------------------------------------|
| `0x00000000-0x0003FFFF`| Application SRAM        | 256KB  | Main firmware code and data          |
| `0x00040000-0x00041FFF`| Bootloader ROM          | 8KB    | BRAM, read-only, synthesis-init      |
| `0x00042000-0x00042FFF`| Bootloader BSS          | 4KB    | SRAM for CRC32 lookup table          |
| `0x00043000-0x0007FFFF`| Stack/Heap              | ~240KB | Available for application use        |
| `0x80000000-0x800000FF`| MMIO Peripherals        | 256B   | UART, LEDs, Buttons                  |

### MMIO Register Map

| Address      | Register       | Access | Description                      |
|--------------|----------------|--------|----------------------------------|
| `0x80000000` | UART_TX_DATA   | W      | Write byte to UART TX            |
| `0x80000004` | UART_TX_STATUS | R      | Bit 0: TX busy flag              |
| `0x80000008` | UART_RX_DATA   | R      | Read byte from circular buffer   |
| `0x8000000C` | UART_RX_STATUS | R      | Bit 0: RX buffer empty           |
| `0x80000010` | LED_CONTROL    | R/W    | Bit 0: LED1, Bit 1: LED2         |
| `0x80000014` | BUTTON_STATUS  | R      | Bit 0: BUT1, Bit 1: BUT2 (inverted) |

### Board Pinout (Olimex iCE40HX8K-EVB)

- **Clock**: 100MHz external crystal → divided to 50MHz system clock
- **UART**: 115200 baud, 8N1 via FTDI FT2232H USB-Serial
- **SRAM**: 16-bit data bus, 256K × 16-bit (512KB total), K6R4016V1D-TC10
- **LEDs**: Active-high (1 = ON, 0 = OFF)
- **Buttons**: Active-low with internal pull-ups (pressed = 0, released = 1)

---

## Peripheral Drivers

### LED Controller

**Base Address**: `0x80000010`

**Register**: LED_CONTROL (R/W, 32-bit)

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | LED1 | R/W | LED1 control (1 = ON, 0 = OFF) |
| 1 | LED2 | R/W | LED2 control (1 = ON, 0 = OFF) |
| 31:2 | - | - | Reserved (read as 0) |

**Usage Example:**
```c
#define LED_CONTROL (*(volatile uint32_t*)0x80000010)

// Turn on LED1, turn off LED2
LED_CONTROL = 0x00000001;

// Toggle LED1
LED_CONTROL ^= 0x00000001;

// Turn on both LEDs
LED_CONTROL = 0x00000003;
```

---

### Button Controller

**Base Address**: `0x80000014`

**Register**: BUTTON_STATUS (R, 32-bit)

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | BUT1 | R | Button 1 status (0 = pressed, 1 = released) |
| 1 | BUT2 | R | Button 2 status (0 = pressed, 1 = released) |
| 31:2 | - | - | Reserved (read as 0) |

**Usage Example:**
```c
#define BUTTON_STATUS (*(volatile uint32_t*)0x80000014)

// Poll for button press (active-low)
while (BUTTON_STATUS & 0x01); // Wait for BUT1 press
while (!(BUTTON_STATUS & 0x01)); // Wait for BUT1 release

// Check button state
if ((BUTTON_STATUS & 0x01) == 0) {
    // Button 1 is pressed
}
```

---

### UART Controller

**Base Address**: `0x80000000`

**Registers:**

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| +0x00 | UART_TX_DATA | W | Transmit data register (8-bit) |
| +0x04 | UART_TX_STATUS | R | Transmit status (bit 0 = busy) |
| +0x08 | UART_RX_DATA | R | Receive data register (8-bit) |
| +0x0C | UART_RX_STATUS | R | Receive status (bit 0 = empty) |

**Configuration:**
- **Baud rate**: 115200 (fixed)
- **Data bits**: 8
- **Parity**: None
- **Stop bits**: 1
- **RX buffer**: 256-byte circular buffer (hardware FIFO)

**Usage Example:**
```c
#define UART_TX_DATA   (*(volatile uint32_t*)0x80000000)
#define UART_TX_STATUS (*(volatile uint32_t*)0x80000004)
#define UART_RX_DATA   (*(volatile uint32_t*)0x80000008)
#define UART_RX_STATUS (*(volatile uint32_t*)0x8000000C)

// Send character
void uart_putc(char c) {
    while (UART_TX_STATUS & 0x01); // Wait for TX ready
    UART_TX_DATA = c;
}

// Receive character (blocking)
char uart_getc(void) {
    while (UART_RX_STATUS & 0x01); // Wait for data
    return UART_RX_DATA & 0xFF;
}

// Check for available data
int uart_available(void) {
    return !(UART_RX_STATUS & 0x01);
}
```

---

### Timer Peripheral (STM32-style)

**Base Address**: `0x80000020`

**Registers:**

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| +0x00 | TIMER_CR | R/W | Control register |
| +0x04 | TIMER_SR | R/W | Status register |
| +0x08 | TIMER_PSC | R/W | Prescaler register (16-bit) |
| +0x0C | TIMER_ARR | R/W | Auto-reload register (32-bit) |

#### TIMER_CR (Control Register)

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | CEN | R/W | Counter enable (1 = enabled, 0 = disabled) |
| 31:1 | - | - | Reserved (read as 0) |

#### TIMER_SR (Status Register)

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | UIF | R/W | Update interrupt flag (1 = overflow occurred) |
| 31:1 | - | - | Reserved (read as 0) |

**Note**: Write 1 to UIF to clear the interrupt flag.

#### TIMER_PSC (Prescaler Register)

| Bits | Name | Access | Description |
|------|------|--------|-------------|
| 15:0 | PSC | R/W | Prescaler value (0-65535) |
| 31:16 | - | - | Reserved (read as 0) |

**Clock Division**: `f_counter = f_clk / (PSC + 1)`

#### TIMER_ARR (Auto-Reload Register)

| Bits | Name | Access | Description |
|------|------|--------|-------------|
| 31:0 | ARR | R/W | Auto-reload value (32-bit down-counter) |

**Counter Behavior**: Counts down from ARR to 0, then generates interrupt and reloads ARR.

---

### Timer Configuration Equations

**System Parameters:**
- System clock: `f_clk = 50 MHz`
- Timer resolution: 32-bit counter
- Prescaler resolution: 16-bit (0-65535)

**Fundamental Equation:**

```
IRQ_frequency = f_clk / ((PSC + 1) × (ARR + 1))
```

Or equivalently:

```
IRQ_period = ((PSC + 1) × (ARR + 1)) / f_clk
```

**Simplified for 50 MHz clock:**

```
IRQ_frequency [Hz] = 50,000,000 / ((PSC + 1) × (ARR + 1))
```

**Design Process:**

1. **Determine desired interrupt frequency** (f_irq)
2. **Calculate total divisor**: `N_total = f_clk / f_irq`
3. **Factor N_total into PSC and ARR**:
   - If `N_total ≤ 2^32`: Set `PSC = 0`, `ARR = N_total - 1`
   - If `N_total > 2^32`: Choose `PSC` to bring counter range to 32-bit

**Configuration Examples:**

| Target Frequency | PSC | ARR | Calculation | Actual Frequency |
|------------------|-----|-----|-------------|------------------|
| **10 kHz** (100 μs) | 0 | 4999 | 50MHz / (1 × 5000) | 10.000 kHz ✅ |
| **1 kHz** (1 ms) | 0 | 49999 | 50MHz / (1 × 50000) | 1.000 kHz ✅ |
| **100 Hz** (10 ms) | 0 | 499999 | 50MHz / (1 × 500000) | 100.000 Hz ✅ |
| **10 Hz** (100 ms) | 0 | 4999999 | 50MHz / (1 × 5000000) | 10.000 Hz ✅ |
| **1 Hz** (1 second) | 9 | 4999999 | 50MHz / (10 × 5000000) | 1.000 Hz ✅ |

**Code Example (10 kHz timer interrupt):**

```c
#define TIMER_CR  (*(volatile uint32_t*)0x80000020)
#define TIMER_SR  (*(volatile uint32_t*)0x80000024)
#define TIMER_PSC (*(volatile uint32_t*)0x80000028)
#define TIMER_ARR (*(volatile uint32_t*)0x8000002C)

void timer_init_10khz(void) {
    // Disable timer during configuration
    TIMER_CR = 0;

    // Clear any pending interrupt
    TIMER_SR = 1;

    // Configure for 10 kHz (100 μs period)
    // f_irq = 50 MHz / ((0 + 1) × (4999 + 1)) = 10 kHz
    TIMER_PSC = 0;        // No prescaler division
    TIMER_ARR = 4999;     // 5000 cycles per interrupt

    // Enable interrupts globally
    irq_enable();

    // Start timer
    TIMER_CR = 1;
}

void irq_handler(void) {
    // Check if timer interrupt
    if (TIMER_SR & 0x01) {
        // Clear interrupt flag (MUST do this!)
        TIMER_SR = 1;

        // Your interrupt code here
        // (executes every 100 μs)
    }
}
```

**Advanced: Calculating PSC and ARR for any frequency:**

```c
void timer_set_frequency(uint32_t freq_hz) {
    uint64_t n_total = 50000000ULL / freq_hz;

    uint32_t psc, arr;

    if (n_total <= 0xFFFFFFFFULL) {
        // Fits in 32-bit counter without prescaler
        psc = 0;
        arr = (uint32_t)n_total - 1;
    } else {
        // Need prescaler - find optimal factorization
        // Start with sqrt(n_total) as first guess
        psc = (uint32_t)sqrt((double)n_total) - 1;

        // Adjust to fit arr in 32-bit
        while (psc < 65535) {
            arr = (uint32_t)(n_total / (psc + 1)) - 1;
            if (arr <= 0xFFFFFFFF) break;
            psc++;
        }
    }

    TIMER_CR = 0;      // Disable
    TIMER_PSC = psc;
    TIMER_ARR = arr;
    TIMER_CR = 1;      // Re-enable
}
```

**Hardware Validation:** ✅ Tested at 10 kHz (100 μs period) on FPGA

---

## Boot Sequence

### FPGA Power-On Flow

```
┌──────────────────────────────────────────────────┐
│ 1. FPGA Configuration                            │
│    • Bitstream loads from flash                  │
│    • bootloader.hex embedded in BRAM             │
│    • Global reset released (~256 clocks)         │
└──────────────────────────────────────────────────┘
                      ↓
┌──────────────────────────────────────────────────┐
│ 2. CPU Boots from 0x40000 (Bootloader ROM)      │
│    • Initialize UART (115200 baud)               │
│    • Build CRC32 table in BSS @ 0x42000          │
│    • Turn on LED1 (bootloader ready signal)      │
└──────────────────────────────────────────────────┘
                      ↓
┌──────────────────────────────────────────────────┐
│ 3. Wait for UART Command                         │
│    Option A: User sends 'R'                      │
│         → Upload firmware via protocol           │
│    Option B: Timeout (optional)                  │
│         → Jump to 0x0 if firmware exists         │
└──────────────────────────────────────────────────┘
                      ↓
┌──────────────────────────────────────────────────┐
│ 4. After Upload: Jump to 0x0                     │
│    • Application firmware executes from SRAM     │
│    • Full access to MMIO peripherals             │
└──────────────────────────────────────────────────┘
```

### Timing
- FPGA config: ~100ms (from flash)
- Bootloader init: ~1ms
- Firmware upload: ~2 seconds (for 10KB firmware @ 115200 baud)

---

## Firmware Upload Protocol

### Protocol Specification

```
┌──────────┐                  ┌────────────┐
│   Host   │                  │ Bootloader │
│(fw_upload)│                  │  (RISC-V)  │
└────┬─────┘                  └─────┬──────┘
     │                              │
     │  Step 1: Handshake           │
     │  'R' (request upload)        │
     ├─────────────────────────────>│
     │                              │
     │        'A' (ack)             │
     │<─────────────────────────────┤
     │                              │
     │  Step 2: Send Size           │
     │  4 bytes (little-endian)     │
     ├─────────────────────────────>│
     │                              │
     │        'B' (ack)             │
     │<─────────────────────────────┤
     │                              │
     │  Step 3: Send Data           │
     │  64-byte chunks              │
     ├─────────────────────────────>│
     │                              │
     │  'C','D','E',...,'Z'         │
     │<─────────────────────────────┤
     │  (ack rotates A-Z)           │
     │                              │
     │  ... repeat for all chunks...│
     │                              │
     │  Step 4: CRC Verification    │
     │  'C' (CRC command)           │
     ├─────────────────────────────>│
     │                              │
     │  CRC32 (4 bytes LE)          │
     ├─────────────────────────────>│
     │                              │
     │  ACK + bootloader CRC        │
     │  (4 bytes calculated)        │
     │<─────────────────────────────┤
     │                              │
     │  [If match: jump to 0x0]     │
     │  [If fail: stay in bootloader]
     └──────────────────────────────┘
```

### CRC32 Algorithm

- **Polynomial**: `0xEDB88320` (reversed PKZIP/IEEE 802.3)
- **Initial value**: `0xFFFFFFFF`
- **Table-based**: 256-entry lookup table built at boot
- **Final XOR**: `0xFFFFFFFF`

---

## Build Instructions

### Prerequisites

#### FPGA Tools
- **Yosys** (0.9+): HDL synthesis
- **NextPNR-iCE40**: Place and route
- **IcePack**: Bitstream generation
- **IceProg** or **WinIceprog**: FPGA programming

#### Software Tools
- **RISC-V GCC**: `riscv64-unknown-elf-gcc` cross-compiler
- **Make**: Build automation
- **fw_upload**: C-based firmware uploader

#### Optional
- **ModelSim**: Simulation (Intel FPGA Edition)

### Quick Build

```bash
# Complete build (bootloader + HDL + firmware + uploader)
make all

# Individual targets
make bootloader   # Build bootloader.hex (700 bytes)
make synth        # Yosys synthesis
make pnr          # NextPNR place and route
make bitstream    # IcePack bitstream generation
make firmware     # Build all firmware examples
```

### Build Output

```
build/
├── ice40_picorv32.json    # Yosys netlist
├── ice40_picorv32.asc     # NextPNR placed design
└── ice40_picorv32.bin     # FPGA bitstream (program this!)

bootloader/
└── bootloader.hex         # Embedded in BRAM (700 bytes)

firmware/
├── led_blink.hex          # LED animation demo
├── interactive.hex        # UART echo server
├── button_demo.hex        # Button polling example
├── timer_clock.hex        # Real-time clock demo
└── irq_timer_test.hex     # Timer interrupt validation (10kHz IRQ)
```

### Programming the FPGA

**Windows:**
```bash
make prog
# Uses WinIceprog.exe via FTDI COM port
```

**Linux/macOS:**
```bash
iceprog build/ice40_picorv32.bin
```

---

## Usage

### 1. Initial Programming

```bash
# Build and program FPGA
make all
make prog

# Expected: LED1 turns ON (bootloader ready)
```

### 2. Upload Firmware

```bash
cd tools/uploader
./fw_upload -p COM8 ../../firmware/led_blink.hex
```

**Expected Output:**
```
Firmware Upload Tool
Connecting to bootloader on COM8...
✓ Handshake successful
Uploading firmware (436 bytes)...
[====================] 100%
✓ Upload complete
Verifying CRC32...
  Host:       0xe975cf52
  Bootloader: 0xe975cf52
✓ CRC MATCH - Upload successful!
Firmware executing!
```

### 3. Observe Firmware Running

**LED Blink Example:**
- LED1 and LED2 alternate every ~1 second
- UART outputs: `1`, `2`, `3`, `0` pattern
- Demonstrates MMIO register access

---

## Project Structure

```
olimex-ice40hx8k-riscv-intr/
│
├── hdl/                          # Verilog HDL sources
│   ├── ice40_picorv32_top.v     # Top-level FPGA design
│   ├── picorv32.v                # PicoRV32 CPU core
│   ├── bootloader_rom.v          # BRAM bootloader ROM (8KB)
│   ├── mem_controller.v          # Memory routing logic
│   ├── sram_driver_new.v         # External SRAM driver
│   ├── sram_proc_new.v           # SRAM protocol FSM
│   ├── uart.v                    # UART transceiver
│   ├── circular_buffer.v         # UART RX FIFO (256 bytes)
│   ├── crc32_gen.v               # CRC32 hardware accelerator
│   ├── mmio_peripherals.v        # Memory-mapped I/O
│   └── ice40_picorv32.pcf        # Pin constraints
│
├── bootloader/                   # Stage 1 bootloader (C)
│   ├── bootloader.c              # Main bootloader logic (~700 bytes)
│   ├── linker.ld                 # Linker script (ROM @ 0x40000)
│   ├── Makefile                  # Build bootloader.hex
│   └── bootloader.hex            # Output (embedded in BRAM)
│
├── firmware/                     # Stage 2 application firmware
│   ├── led_blink.c               # LED animation example
│   ├── interactive.c             # UART echo server
│   ├── button_demo.c             # Button polling demo
│   ├── timer_clock.c             # Real-time clock demo
│   ├── irq_timer_test.c          # Timer interrupt validation (10kHz IRQ)
│   ├── start.S                   # Startup assembly (RV32I)
│   ├── linker.ld                 # Linker script (SRAM @ 0x0)
│   ├── sections.lds              # Section definitions
│   └── Makefile                  # Build *.hex files
│
├── sim/                          # ModelSim simulation
│   ├── tb_bootloader_complete.sv # Complete system testbench
│   └── run_bootloader_test.sh    # Automated simulation script
│
├── tools/                        # Development utilities
│   └── uploader/                 # Firmware upload tool
│       ├── fw_upload             # C-based UART uploader
│       └── README.md             # Usage instructions
│
├── build/                        # Synthesis outputs (generated)
│   ├── ice40_picorv32.json      # Yosys netlist
│   ├── ice40_picorv32.asc       # NextPNR placed design
│   └── ice40_picorv32.bin       # FPGA bitstream
│
├── Makefile                      # Master build script
└── README.md                     # This file
```

---

## Design Rationale

### Why BRAM for Bootloader?

**Problem**: SPRAM (Single-Port RAM) on iCE40 cannot be initialized during synthesis. Using `$readmemh()` in Verilog only works in simulation.

**Solution**: Use BRAM (Block RAM) instead:

| Feature                  | SPRAM          | BRAM          |
|--------------------------|----------------|---------------|
| Synthesis initialization | ❌ Not supported | ✅ Supported via `$readmemh()` |
| Runtime writes           | ✅ Yes          | ⚠️ Breaks inference if used |
| Size per block           | 16KB           | 4KB           |
| Best use case            | Runtime RAM    | Read-only ROM |

**Result**:
- Bootloader stored in BRAM (read-only after synthesis)
- No runtime copying needed
- Yosys infers 16× `SB_RAM40_4K` blocks automatically

### Memory Controller Architecture

The `mem_controller.v` provides a unified memory interface:

```
┌──────────────────────────────────────┐
│         PicoRV32 CPU                 │
│    (mem_addr, mem_wdata, ...)        │
└──────────────┬───────────────────────┘
               │
         ┌─────┴─────┐
         │ Address   │
         │  Decode   │
         └─────┬─────┘
               │
      ┌────────┼────────┐
      │        │        │
      ↓        ↓        ↓
   ┌─────┐ ┌──────┐ ┌──────┐
   │ SRAM│ │ BRAM │ │ MMIO │
   │     │ │ ROM  │ │      │
   └─────┘ └──────┘ └──────┘
    0x0     0x40000  0x80000000
```

Benefits:
- **No bank switching**: Simplified software
- **Single address space**: Code and data intermixed
- **Fast peripheral access**: Memory-mapped I/O

---

## Resource Utilization

### iCE40HX8K-CT256 FPGA

| Resource             | Used  | Total | Utilization | Notes                              |
|----------------------|-------|-------|-------------|------------------------------------|
| Logic Cells (LCs)    | 4,678 | 7,680 | **61%**     | RV32IM CPU + timer + peripherals   |
| Block RAM (BRAM)     | 16    | 32    | **50%**     | Bootloader ROM (8KB)               |
| I/O Pins             | 44    | 256   | 17%         | SRAM + UART + LEDs                 |
| Global Buffers       | 8     | 8     | 100%        | Clock distribution                 |

**Note**: Upgrade from RV32E (16 registers) to RV32IM (32 registers + MUL/DIV + barrel shifter + interrupts + timer) increased LC usage from 3,551 (46%) to 4,678 (61%).

### Timing Analysis

- **Target frequency**: 50 MHz (20 ns period)
- **Achieved frequency**: 59.58 MHz (16.78 ns period)
- **Timing margin**: +19% (3.22 ns slack)
- **Critical path**: 16.78 ns (CPU divide unit → compare logic)

### Memory Performance

**SRAM Access Cycles** (at 50 MHz, 20 ns/cycle):

| Operation | Cycles | Time | Details |
|-----------|--------|------|---------|
| 16-bit SRAM read | 2 | 40 ns | 2-cycle driver (IDLE→ACTIVE→COMPLETE) |
| 16-bit SRAM write | 2 | 40 ns | 2-cycle driver |
| 32-bit READ | ~6 | 120 ns | Two 16-bit reads + controller overhead |
| 32-bit WRITE (word) | ~5 | 100 ns | Two 16-bit writes + controller overhead |
| 32-bit WRITE (byte) | ~11 | 220 ns | Read-modify-write: read(6) + merge(1) + write(5) |

**State Machine Flow (per 16-bit access):**
```
Cycle 0: IDLE     - Valid arrives, latch address/data
Cycle 1: ACTIVE   - CS/WE/OE + address asserted, data becomes valid (reads)
Cycle 2: COMPLETE - Sample data (read) / WE rising edge (write), assert ready
```

**SRAM Performance:**
- **40 MB/s peak bandwidth**
- **Hardware validated** on Olimex iCE40HX8K-EVB ✅
- See `docs/SRAM_CYCLE_TIMING_COMPARISON.md` for detailed timing analysis

**Datasheet Compliance:**
- K6R4016V1D-TC10: 10ns access time at 3.3V
- All timing specifications met with **2-4× safety margins**
- No COOLDOWN state needed (datasheet allows back-to-back access)

**Module Details:**
- `sram_driver_new.v` - Physical SRAM interface (2 cycles per 16-bit access)
- `sram_proc_new.v` - 32-bit to 16-bit converter with RMW support

### Bootloader Size

- **Binary size**: 700 bytes
- **BRAM usage**: 8KB (176 words × 32 bits)
- **Stack**: 256 bytes (at 0x00042F00)
- **CRC32 table**: 1KB (runtime-generated in BSS @ 0x42000)

---

## Simulation

### ModelSim Complete System Test

```bash
cd sim
./run_bootloader_test.sh
```

**What the testbench does:**

1. ✅ Boot bootloader from BRAM
2. ✅ Wait for LED1 = HIGH (ready signal)
3. ✅ Send firmware upload via UART protocol
4. ✅ Verify CRC32 match (0xe975cf52)
5. ✅ Confirm firmware execution (LED blinking)

**Runtime**: ~10 minutes (simulates 97+ seconds of hardware time)

**Expected output:**
```
[BOOTROM] Loaded bootloader.hex for simulation
[TB] Phase 1: Bootloader initialization
[TB] LED1 is ON - bootloader ready!
[TB] Phase 2: Loading test firmware
[TB] Phase 3: Uploading firmware via UART
[TB] ✓ CRC MATCH - Upload successful!
[TB] Phase 4: Waiting for bootloader to jump to 0x0...
[TB] Phase 5: Monitoring firmware execution
TEST COMPLETE
```

---

## Troubleshooting

### FPGA Won't Boot (No LED1)

**Symptoms**: After programming, LED1 stays OFF

**Possible causes:**
1. Bitstream not programmed correctly
2. Clock divider issue (100MHz → 25MHz)
3. Reset not releasing

**Debug steps:**
```bash
# Re-program FPGA
make prog

# Check UART output (bootloader may be running)
screen /dev/ttyUSB1 115200

# Try power cycle
# Unplug USB, wait 5 seconds, replug
```

### Firmware Upload Fails

**Symptoms**: Upload tool times out or gets wrong ACKs

**Possible causes:**
1. Wrong COM port
2. Bootloader not waiting (LED1 OFF)
3. Corrupted .hex file

**Debug steps:**
```bash
# List COM ports (Linux)
ls /dev/ttyUSB*

# List COM ports (Windows)
# Check Device Manager → Ports (COM & LPT)

# Verify .hex file format
head firmware/led_blink.hex
# Should start with: @00000000

# Try slower upload (add delays)
./fw_upload -p COM8 --slow firmware/led_blink.hex
```

### Synthesis Fails with 800%+ Utilization

**Symptoms**: NextPNR fails with "Unable to place cell"

**Cause**: BRAM inference failed, design synthesized as flip-flops

**Fix:**
```bash
# Check bootloader_rom.v has:
grep "ram_style" hdl/bootloader_rom.v
# Should show: (* ram_style = "block" *)

# Ensure no write ports on ROM
grep "init_wen\|init_wdata" hdl/bootloader_rom.v
# Should return: (nothing - no write ports)

# Clean and rebuild
make clean
make all
```

### CRC Mismatch During Upload

**Symptoms**: Host CRC ≠ Bootloader CRC

**Possible causes:**
1. UART data corruption
2. CRC32 table generation error
3. Size mismatch

**Debug steps:**
```bash
# Check firmware size
ls -l firmware/led_blink.hex

# Verify CRC locally
python3 -c "
import zlib
data = open('firmware/led_blink.bin', 'rb').read()
print(f'CRC32: 0x{zlib.crc32(data) & 0xffffffff:08x}')
"

# Try re-uploading
./fw_upload -p COM8 firmware/led_blink.hex
```

---

## References

### Documentation

- [PicoRV32 GitHub Repository](https://github.com/YosysHQ/picorv32)
- [iCE40 FPGA Family Datasheet](https://www.latticesemi.com/iCE40)
- [Olimex iCE40HX8K-EVB Hardware](https://www.olimex.com/Products/FPGA/iCE40/iCE40HX8K-EVB/)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)

### Tools

- [Yosys Open Synthesis Suite](https://yosyshq.net/yosys/)
- [NextPNR Place and Route](https://github.com/YosysHQ/nextpnr)
- [Project IceStorm (iCE40 Tools)](http://www.clifford.at/icestorm/)

### Related Projects

- [PicoSoC](https://github.com/YosysHQ/picorv32/tree/master/picosoc) - Reference SoC
- [Fomu Workshop](https://workshop.fomu.im/) - iCE40 FPGA tutorials

---

## License

**NOT FOR COMMERCIAL USE**

This project is for educational and research purposes only.

**Component Licenses:**
- **PicoRV32**: Copyright (c) Claire Xenia Wolf (ISC License)
- **UART Core**: Based on GitHub nandland/uart-serial-verilog
- **Project**: Copyright (c) 2025 Michael Wolak

---

## Acknowledgments

- **Claire Xenia Wolf**: PicoRV32 RISC-V core and Yosys synthesis tools
- **Olimex**: iCE40HX8K-EVB hardware platform
- **Lattice Semiconductor**: iCE40 FPGA architecture and development tools
- **RISC-V Foundation**: Open and free ISA specification

---

**Project Status**: ✅ Verified on hardware • ✅ Tested in simulation • ✅ Production ready

**Last Updated**: October 2025
