# Olimex iCE40HX8K PicoRV32 RISC-V System

Kconfig-based build system for PicoRV32 soft-core RISC-V processor on the Olimex iCE40HX8K-EVB FPGA board.

## Features

- **Kconfig-based configuration** - Linux kernel-style menuconfig
- **Automatic dependency management** - Fetches PicoRV32, toolchains, etc. on demand
- **Ninja build system** - Optimal parallel builds
- **Version pinning** - Reproducible builds with exact dependency versions
- **Relocatable** - Move the entire directory anywhere
- **Minimal repository** - Only source files tracked, everything else generated/downloaded

## Quick Start

### Prerequisites

- Build tools: `gcc`, `make`, `ninja-build`, `python3`
- Kconfig tools: `kconfig-frontends` (or will be auto-fetched)
- RISC-V toolchain: `riscv64-unknown-elf-gcc` (or configure to build from source)
- FPGA tools: `yosys`, `nextpnr-ice40`, `icepack` (or configure to download)

### Building

```bash
# Clone repository
git clone https://github.com/mikewolak/olimex-ice40hx8k-picorv32.git
cd olimex-ice40hx8k-picorv32

# Configure (or use default)
make menuconfig   # Interactive configuration
# OR
make defconfig    # Load default configuration

# Build everything
make

# Outputs will be in deploy/
ls deploy/
```

### Build Targets

```bash
make                  # Build everything
make menuconfig       # Configure system
make defconfig        # Load default config
make clean            # Remove build artifacts
make distclean        # Remove config + artifacts
make mrproper         # Complete clean (pristine repo)
```

## Configuration

The system uses Kconfig for configuration:

- **PicoRV32 Core**: ISA extensions (RV32I/RV32IM/RV32IC), MUL/DIV, barrel shifter, IRQ mode
- **Memory Map**: ROM/RAM addresses and sizes
- **Peripherals**: UART, Timer, VGA, GPIO with configurable MMIO addresses
- **Build Options**: Optimization levels, synthesis options, simulation
- **Toolchains**: Use system tools or build from source

## Directory Structure

```
.
├── configs/          # Configuration presets
├── scripts/          # Build generators and helpers
├── hdl/             # HDL peripherals (UART, Timer, SRAM, etc.)
├── bootloader/      # Bootloader source
├── firmware/        # Demo firmware applications
├── lib/             # Support libraries
├── tools/           # Utilities (firmware uploader, etc.)
├── downloads/       # Auto-fetched dependencies (gitignored)
├── build/           # Build artifacts (gitignored)
└── deploy/          # Final outputs (gitignored)
```

## Hardware

- **Board**: Olimex iCE40HX8K-EVB
- **FPGA**: Lattice iCE40HX8K (7680 LUTs)
- **SRAM**: 512KB external SRAM
- **Peripherals**: UART, Timer, GPIO, VGA (optional)

## Default Configuration

The default configuration (`configs/defconfig`) provides:

- **Core**: RV32IM (no compressed), MUL/DIV enabled, barrel shifter
- **Memory**: 256KB app SRAM, 8KB bootloader ROM, dynamic heap (~248KB)
- **Clock**: 50MHz (100MHz crystal divided by 2)
- **UART**: 115200 baud
- **Synthesis**: ABC9 optimization enabled

## License

Educational and research purposes only. Not for commercial use.

Copyright (c) 2025 Michael Wolak
Email: mikewolak@gmail.com, mike@epromfoundry.com
