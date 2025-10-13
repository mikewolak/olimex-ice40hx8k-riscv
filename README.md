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

- **PicoRV32 CPU**: Compact RV32E (16-register) RISC-V processor @ 25 MHz
- **Bootloader ROM**: 8KB BRAM initialized from `bootloader.hex` at synthesis
- **Firmware Upload**: UART-based protocol with CRC32 verification (PKZIP/IEEE 802.3)
- **Memory Controller**: Unified interface for SRAM, BRAM, and MMIO
- **512KB External SRAM**: K6R4016V1D-TC10 for application code and data
- **MMIO Peripherals**: UART, LEDs, buttons via memory-mapped registers
- **Efficient Design**: 46% logic utilization, 50% BRAM, capable of 67MHz

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

- **Clock**: 100MHz external crystal → divided to 25MHz system clock
- **UART**: 115200 baud, 8N1 via FTDI FT2232H USB-Serial
- **SRAM**: 16-bit data bus, 256K × 16-bit (512KB total), K6R4016V1D-TC10
- **LEDs**: Active-high (1 = ON, 0 = OFF)
- **Buttons**: Active-low with internal pull-ups (pressed = 0, released = 1)

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
│ (Python) │                  │  (RISC-V)  │
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
- **Python 3**: Firmware uploader script

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
└── button_demo.hex        # Button polling example
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
│   ├── start.S                   # Startup assembly (RV32E)
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
│       ├── fw_upload             # Python UART uploader
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

| Resource             | Used  | Total | Utilization | Notes                    |
|----------------------|-------|-------|-------------|--------------------------|
| Logic Cells (LCs)    | 3,551 | 7,680 | **46%**     | PicoRV32 + peripherals   |
| Block RAM (BRAM)     | 16    | 32    | **50%**     | Bootloader ROM (8KB)     |
| I/O Pins             | 44    | 256   | 17%         | SRAM + UART + LEDs       |
| Global Buffers       | 8     | 8     | 100%        | Clock distribution       |

### Timing Analysis

- **Target frequency**: 25 MHz (40 ns period)
- **Achieved frequency**: 67.84 MHz (14.74 ns period)
- **Timing margin**: +170% (2.7× margin)
- **Critical path**: 14.74 ns (CPU ALU carry chain)

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
