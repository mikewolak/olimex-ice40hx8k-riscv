# Olimex iCE40HX8K PicoRV32 RISC-V System

A complete RISC-V soft-core processor system for the Olimex iCE40HX8K-EVB FPGA board featuring the PicoRV32 CPU, bootloader with firmware upload capability, comprehensive peripheral set, and rich firmware examples.

## NOT FOR COMMERCIAL USE
**EDUCATIONAL AND RESEARCH PURPOSES ONLY**

This project is provided for educational and research purposes. Commercial use is strictly prohibited without explicit written permission.

Copyright (c) October 2025 Michael Wolak
Email: mikewolak@gmail.com, mike@epromfoundry.com

---

## Overview

This project implements a fully functional RISC-V RV32IM processor system on the Lattice iCE40HX8K FPGA. The system includes:

- **PicoRV32 CPU Core** - 32-bit RISC-V processor running at 50 MHz
- **Bootloader** - Serial firmware uploader with CRC32 verification
- **512KB External SRAM** - High-performance 5-cycle SRAM controller
- **MMIO Peripherals** - UART, Timer, GPIO, and more
- **Rich Firmware Library** - Over 20 example applications
- **Professional Build System** - Automatic toolchain management and reproducible builds

## Key Features

### Hardware Architecture
- **FPGA**: Lattice iCE40HX8K-CT256 (7680 LUTs, 90% utilization)
- **CPU**: PicoRV32 RV32IM @ 50 MHz (multiply/divide, no compressed instructions)
- **Memory**: 512KB external SRAM (K6R4016V1D-TC10)
- **Clock**: 100 MHz crystal, divided to 50 MHz system clock
- **Timing**: Meets 50 MHz requirement with 27.9% margin (63.95 MHz achieved)

### Peripherals (MMIO)
- **UART**: 115200 baud, 8N1, with 64-byte circular buffers
- **Timer**: 32-bit timer with millisecond resolution
- **GPIO**: Configurable I/O pins
- **SRAM Controller**: Optimized 5-cycle access pattern
- **CRC32**: Hardware CRC32 for firmware verification

### Bootloader
- Firmware upload protocol over UART
- CRC32 verification of uploaded firmware
- Automatic execution after successful upload
- LED status indicators for upload progress
- Halts on CRC mismatch for safety

### Build System
- **Automatic toolchain management** - Downloads and builds required tools
- **Platform verification** - Ensures correct build environment (x86-64 Linux)
- **Reproducible builds** - Version-pinned dependencies
- **Comprehensive reports** - Gate utilization, timing, tool versions
- **Artifact packaging** - Creates release tarballs with git tags

## Quick Start

### Prerequisites

The build system requires **x86-64 Linux**. Ubuntu, Debian, Fedora, RHEL, Arch, and other distributions are supported.

Run platform verification to check your system:
```bash
bash scripts/verify-platform.sh
```

If build tools are missing, the script will provide distribution-specific installation commands.

**Minimum requirements:**
- gcc, g++, make
- git
- wget or curl
- tar

**All other dependencies** (FPGA tools, RISC-V toolchain) are automatically downloaded by the Makefile.

### Building

```bash
# Clone the repository
git clone https://github.com/mikewolak/olimex-ice40hx8k-picorv32.git
cd olimex-ice40hx8k-picorv32

# Build everything (toolchain, gateware, firmware, host tools)
make

# This will:
# 1. Verify platform requirements
# 2. Download oss-cad-suite (Yosys, NextPNR, icetime)
# 3. Download and build RISC-V GCC toolchain
# 4. Build bootloader
# 5. Synthesize FPGA bitstream
# 6. Build all firmware examples
# 7. Build host uploader tool
# 8. Generate artifacts and build report
```

**Build time:** Approximately 30-45 minutes on a modern system (first build includes toolchain compilation).

### Artifacts

After building, all outputs are collected in the `artifacts/` directory:

```
artifacts/
├── host/
│   └── fw_upload              # Firmware uploader tool
├── gateware/
│   └── ice40_picorv32.bin     # FPGA bitstream
├── firmware/
│   ├── led_blink.bin          # LED blink demo
│   ├── timer_clock.bin        # Real-time clock
│   ├── hexedit.bin            # Interactive hex editor
│   ├── mandelbrot_float.bin   # Mandelbrot set (floating point)
│   ├── mandelbrot_fixed.bin   # Mandelbrot set (fixed point)
│   ├── algo_test.bin          # Algorithm tests
│   ├── heap_test.bin          # Dynamic memory test
│   └── ...                    # More examples
└── build-report.txt           # Comprehensive build report
```

A versioned tarball is also created: `artifacts/olimex-ice40hx8k-picorv32-<tag>-<timestamp>.tar.gz`

## Usage

### Programming the FPGA

Use the Olimex programmer tool to load the bitstream:

```bash
# Program FPGA with bitstream
olimexino-32u4 -p artifacts/gateware/ice40_picorv32.bin

# Or use iceprog if available
iceprog artifacts/gateware/ice40_picorv32.bin
```

### Bootloader Operation

The bootloader runs automatically after FPGA configuration. It implements a simple firmware upload protocol (not an interactive shell):

**Protocol:**
1. Waits for 'R' (Ready) command from fw_upload tool
2. Receives firmware size (4 bytes, little-endian)
3. Receives firmware data in 64-byte chunks with ACK handshake
4. Verifies CRC32 checksum
5. Automatically jumps to uploaded firmware at address 0x0

**LED indicators:**
- LED1 on: Waiting for upload
- LED2 on: Downloading firmware
- Both LEDs: Download in progress
- LEDs off: Success (firmware running) or CRC error

The bootloader is not interactive - use the `fw_upload` host tool to upload firmware.

### Uploading Firmware

Use the `fw_upload` host tool to send firmware to the bootloader:

```bash
# List available serial ports
artifacts/host/fw_upload --list

# Upload firmware
artifacts/host/fw_upload -p /dev/ttyUSB0 artifacts/firmware/led_blink.bin

# Upload with verbose output
artifacts/host/fw_upload -p /dev/ttyUSB0 artifacts/firmware/timer_clock.bin -v
```

The uploader features:
- Beautiful progress bar with speed/ETA
- Rotating ACK protocol for reliability
- CRC32 verification
- Cross-platform (Linux, macOS, Windows)

## Firmware Examples

The project includes over 20 example firmware applications:

### Basic Examples
- **led_blink.c** - Simple LED blinker
- **uart_echo_test.c** - UART echo test
- **button_demo.c** - Button input handling

### Newlib C Standard Library
- **printf_test.c** - Interactive printf/scanf test menu
- **stdio_test.c** - Basic stdio operations
- **heap_test.c** - Dynamic memory allocation (malloc/free)
- **math_test.c** - Standard math library functions

### Advanced Applications
- **timer_clock.c** - Real-time clock with timer peripheral
- **hexedit.c** - Interactive hex editor with curses-like interface
- **mandelbrot_float.c** - Mandelbrot set with floating-point math
- **mandelbrot_fixed.c** - Mandelbrot set with fixed-point math
- **algo_test.c** - Algorithm tests (sorting, searching)

### Testing & Verification
- **interactive.c** - Interactive peripheral test
- **irq_timer_test.c** - Timer interrupt test
- **syscall_test.c** - Syscall bridge verification
- **verify_algo.c** - Algorithm verification suite
- **verify_math.c** - Math library verification

## Project Structure

```
.
├── hdl/                    # HDL source files
│   ├── ice40_picorv32_top.v      # Top-level module
│   ├── picorv32.v                # PicoRV32 CPU core
│   ├── sram_driver_new.v         # 5-cycle SRAM controller
│   ├── uart.v                    # UART peripheral
│   ├── timer_peripheral.v        # Timer peripheral
│   ├── mmio_peripherals.v        # MMIO controller
│   ├── firmware_loader.v         # Firmware upload state machine
│   ├── bootloader_rom.v          # Bootloader ROM
│   ├── ice40_picorv32.pcf        # Pin constraints
│   └── ice40_picorv32.sdc        # Timing constraints
│
├── bootloader/             # Bootloader source
│   ├── bootloader.c              # Main bootloader
│   └── Makefile
│
├── firmware/               # Firmware examples
│   ├── *.c                       # Example applications
│   └── Makefile
│
├── lib/                    # Support libraries
│   ├── syscalls/                 # Newlib syscalls (UART I/O)
│   ├── simple_upload/            # Firmware upload protocol
│   ├── microrl/                  # Command-line parser
│   └── incurses/                 # Curses-like terminal library
│
├── tools/                  # Host utilities
│   └── uploader/
│       ├── fw_upload.c           # Cross-platform uploader
│       └── Makefile
│
├── scripts/                # Build scripts
│   ├── verify-platform.sh        # Platform verification
│   └── ...
│
├── configs/                # Configuration files
├── build/                  # Build artifacts (gitignored)
├── downloads/              # Downloaded dependencies (gitignored)
├── artifacts/              # Final outputs (gitignored)
├── Makefile                # Main build system
└── README.md               # This file
```

## Memory Map

```
0x00000000 - 0x00001FFF  (8KB)    Bootloader ROM
0x00002000 - 0x0007FFFF  (504KB)  Application SRAM
0x10000000 - 0x100000FF           MMIO Peripherals
  0x10000000                      UART data
  0x10000004                      UART status
  0x10000010                      Timer control
  0x10000014                      Timer value
  0x10000020                      GPIO
  0x10000030                      CRC32
  0x10000040                      Firmware upload control
```

## Build Targets

```bash
make                    # Build everything
make toolchain-check    # Verify platform and tools
make toolchain-download # Download FPGA tools
make toolchain          # Build RISC-V GCC (if needed)
make bootloader         # Build bootloader
make synthesis          # Synthesize HDL
make pnr                # Place and route
make bitstream          # Generate bitstream
make firmware           # Build all firmware
make uploader           # Build host uploader tool
make timing             # Run timing analysis
make artifacts          # Collect all outputs
make clean              # Remove build artifacts
make distclean          # Clean build/ and artifacts/
```

## Timing and Performance

The system meets all timing requirements with margin:

- **Target frequency**: 50.00 MHz (20.0 ns period)
- **Achieved frequency**: 63.95 MHz (15.64 ns period)
- **Timing margin**: 13.95 MHz (27.9%)

**FPGA utilization:**
- DFFs: 3080
- LUTs: 7054 / 7680 (92%)
- BRAMs: 18 / 32 (56%)
- Carry chains: 744

## Known Issues and Notes

### Yosys 0.58+ ABC9 Optimization
Yosys 0.58 and later have an ABC9 optimization issue that can cause CRC32 state machine corruption. The current build uses optimized SRAM controller with ABC9 disabled for stability. See `YOSYS_ABC9_ISSUE.md` for details.

### SRAM Controller
The system uses a 5-cycle SRAM access pattern for reliability. A 4-cycle optimized version exists but may have timing issues on some boards. The stable 5-cycle version is default.

## Development

### Adding New Firmware

1. Create your `.c` file in `firmware/`
2. Add your target to `firmware/Makefile`
3. Build with: `make TARGET=yourapp firmware`
4. Upload with: `artifacts/host/fw_upload -p /dev/ttyUSB0 firmware/yourapp.bin`

### Modifying HDL

1. Edit files in `hdl/`
2. Rebuild bitstream: `make synthesis pnr bitstream`
3. Program FPGA with new bitstream

### Using Newlib C Standard Library

Firmware applications can use standard C library functions (printf, scanf, malloc, etc.) by building with `USE_NEWLIB=1`:

```bash
make TARGET=yourapp USE_NEWLIB=1 firmware
```

The syscalls bridge in `lib/syscalls/` provides UART-based I/O for newlib.

## Credits and License

**Copyright (c) October 2025 Michael Wolak**
Email: mikewolak@gmail.com, mike@epromfoundry.com

**NOT FOR COMMERCIAL USE**
**EDUCATIONAL AND RESEARCH PURPOSES ONLY**

This project is provided as-is for educational and research purposes. Commercial use, redistribution for profit, or incorporation into commercial products is strictly prohibited without explicit written permission from the copyright holder.

### Third-Party Components

This project incorporates the following third-party components under their respective licenses:

- **PicoRV32** - Copyright (c) Clifford Wolf, ISC License
- **Newlib** - Various authors, BSD-style licenses
- **microrl** - Eugene Samoylov, BSD 3-Clause License

See individual component directories for their specific license terms.

## Support and Contact

For questions, bug reports, or inquiries about commercial licensing:

Michael Wolak
mikewolak@gmail.com
mike@epromfoundry.com

GitHub: https://github.com/mikewolak/olimex-ice40hx8k-picorv32

## Acknowledgments

- Clifford Wolf for PicoRV32 and the open-source FPGA toolchain (Yosys, nextpnr, icestorm)
- Olimex for the iCE40HX8K-EVB development board
- The RISC-V community for the open ISA and toolchain support
