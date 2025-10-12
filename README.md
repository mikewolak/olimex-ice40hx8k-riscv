# Olimex iCE40HX8K-EVB RISC-V Platform

A complete RISC-V soft-core implementation for the Olimex iCE40HX8K-EVB FPGA development board, featuring the PicoRV32 CPU, 512KB external SRAM, UART communication, and a dual-mode firmware upload system.

**Copyright (c) October 2025 Michael Wolak**
Email: mikewolak@gmail.com, mike@epromfoundry.com
**NOT FOR COMMERCIAL USE** - Educational and research purposes only

---

## Table of Contents

- [Features](#features)
- [Hardware Requirements](#hardware-requirements)
- [System Architecture](#system-architecture)
- [Memory-Mapped I/O (MMIO) Register Map](#memory-mapped-io-mmio-register-map)
- [Build System](#build-system)
- [Quick Start](#quick-start)
- [Firmware Development](#firmware-development)
- [Simulation](#simulation)
- [Performance Metrics](#performance-metrics)
- [Known Limitations](#known-limitations)
- [Optimization Opportunities](#optimization-opportunities)
- [Troubleshooting](#troubleshooting)

---

## Features

- **PicoRV32 RISC-V CPU**: RV32E variant (16 registers), running at 41.79 MHz (target: 12 MHz)
- **512KB External SRAM**: K6R4016V1D-TC10 16-bit wide memory
- **Dual-Mode Operation**:
  - **SHELL Mode**: Interactive firmware upload via UART with CRC32 validation
  - **APP Mode**: RISC-V CPU execution with full peripheral access
- **UART Communication**: 115200 baud, 8N1, via FTDI FT2232H
- **Memory-Mapped Peripherals**: UART, LEDs, buttons, mode control
- **Bidirectional Mode Switching**: Switch between SHELL and APP modes on-the-fly
- **Cross-Platform Firmware Uploader**: Supports Windows, Linux, and macOS
- **ModelSim Simulation**: Complete testbench suite for verification

---

## Hardware Requirements

### Target Board: Olimex iCE40HX8K-EVB

- **FPGA**: Lattice iCE40HX8K-CT256
  - 7680 logic cells
  - Current utilization: **7595/7680 (98.9%)**
- **SRAM**: 512KB (K6R4016V1D-TC10)
  - 16-bit data bus
  - 18-bit address bus (256K x 16)
- **USB-UART**: FTDI FT2232H
  - Channel A: JTAG/SPI programming (COM5 - Windows only)
  - Channel B: UART communication (COM8 - all platforms)
- **User Interface**:
  - 2x push buttons (BUT1, BUT2) - active low
  - 2x LEDs (LED1, LED2)
- **Clock**: 100 MHz external oscillator

### Software Requirements

#### HDL Build Tools (Linux/macOS/Windows)
- **Yosys** (synthesis): Verilog → JSON
- **NextPNR-iCE40** (place and route): JSON → ASC
  - **Tested versions**: nextpnr-0.7 (recommended), nextpnr-0.9 (may require seed tuning)
  - **Note**: This design uses 98% of FPGA resources. Newer nextpnr versions (0.9+) may fail placement with default settings. Try different seeds or SA placer if build fails.
- **IcePack** (bitstream packer): ASC → BIN
- **IceTime** (timing analysis): optional

#### FPGA Programming (Windows Only)
- **WinIceprog.exe**: FPGA bitstream upload
- **IMPORTANT**: The board does NOT enumerate as a COM device on Linux/macOS for JTAG programming. FPGA bitstream upload requires Windows.

#### Firmware Build Tools (All Platforms)
- **RISC-V GCC Toolchain**: `riscv32-unknown-elf-gcc` or `riscv64-unknown-elf-gcc`
- **GNU Make**

#### Firmware Upload Tools (All Platforms)
- **GCC** (Linux/macOS) or **Visual Studio** (Windows)
- Uploader works via UART on all platforms

#### Simulation Tools (Optional)
- **ModelSim** or **Questa**: HDL simulation and verification

---

## System Architecture

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    ice40_picorv32_top                           │
│                                                                 │
│  ┌──────────────┐    ┌─────────────────┐    ┌───────────────┐   │
│  │ Mode         │───▶│ PicoRV32        │◀──▶│ Memory        │   │
│  │ Controller   │    │ RISC-V CPU      │    │ Controller    │   │
│  └──────────────┘    │ (RV32E)         │    │               │   │
│         │            └─────────────────┘    └───────┬───────┘   │
│         │                     │                     │           │
│    SHELL/APP              MMIO Bus               ┌──▼────┐      │
│      Mode                     │                  │ SRAM  │      │
│         │            ┌────────▼────────┐         │ 512KB │      │
│         │            │ MMIO            │         └───────┘      │
│         │            │ Peripherals     │                        │
│         │            └───────┬─────────┘                        │
│         │                    │                                  │
│    ┌────▼─────┐      ┌───────┼───────┐                          │
│    │ Shell /  │      │       │       │                          │
│    │ Firmware │      │       │       │                          │
│    │ Loader   │    UART    LEDs   Buttons                       │
│    └──────────┘      │       │       │                          │
└──────────┬───────────┼───────┼───────┼──────────────────────────┘
           │           │       │       │
      ┌────▼────┐  ┌───▼───┐   │       │
      │ FTDI    │  │ UART  │   │       │
      │ FT2232H │  │ TX/RX │   │       │
      └─────────┘  └───────┘   │       │
           │                   │       │
        USB/UART          LED1/LED2  BUT1/BUT2
```

### Operating Modes

#### SHELL Mode (Default on Reset)
- CPU held in reset
- Firmware loader active
- Accepts commands via UART:
  - `u <length>`: Upload firmware (with CRC32 validation)
  - `r`: Execute firmware (switch to APP mode)
  - `d <addr> <len>`: Dump memory
  - `s`: System status

#### APP Mode (CPU Running)
- CPU executes from SRAM (address 0x00000000)
- Full access to MMIO peripherals
- Can return to SHELL mode via MMIO write to MODE_CONTROL

---

## Memory-Mapped I/O (MMIO) Register Map

All MMIO registers are located at **base address 0x80000000**.

| Address      | Register Name      | Access | Width | Description                                    |
|--------------|-------------------|--------|-------|------------------------------------------------|
| `0x80000000` | UART_TX_DATA      | W      | 32    | UART transmit data register                    |
| `0x80000004` | UART_TX_STATUS    | R      | 32    | UART transmit status (bit 0: busy)             |
| `0x80000008` | UART_RX_DATA      | R      | 32    | UART receive data register                     |
| `0x8000000C` | UART_RX_STATUS    | R      | 32    | UART receive status (bit 0: data available)    |
| `0x80000010` | LED_CONTROL       | R/W    | 32    | LED control (bit 0: LED1, bit 1: LED2)         |
| `0x80000014` | MODE_CONTROL      | W      | 32    | Mode control (write 0: SHELL, write 1: APP)    |
| `0x80000018` | BUTTON_INPUT      | R      | 32    | Button status (bit 0: BUT1, bit 1: BUT2)       |
| `0x8000001C` | RESERVED          | -      | 32    | Reserved for future use                        |

### Register Details

#### UART_TX_DATA (0x80000000)
**Write Only** - Send a byte via UART

```c
#define UART_TX_DATA (*(volatile unsigned int *)0x80000000)

// Example: Send a character
UART_TX_DATA = 'A';
```

#### UART_TX_STATUS (0x80000004)
**Read Only** - Check if UART TX is busy

| Bit | Name | Description                          |
|-----|------|--------------------------------------|
| 0   | BUSY | 1 = TX busy, 0 = TX ready for data   |
| 31:1| -    | Reserved (read as 0)                 |

```c
#define UART_TX_STATUS (*(volatile unsigned int *)0x80000004)

// Example: Wait for TX ready
void putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while busy
    UART_TX_DATA = c;
}
```

#### UART_RX_DATA (0x80000008)
**Read Only** - Receive a byte from UART

```c
#define UART_RX_DATA (*(volatile unsigned int *)0x80000008)

// Example: Read received byte
unsigned char c = UART_RX_DATA & 0xFF;
```

#### UART_RX_STATUS (0x8000000C)
**Read Only** - Check if UART RX has data available

| Bit | Name  | Description                             |
|-----|-------|-----------------------------------------|
| 0   | AVAIL | 1 = data available, 0 = no data         |
| 31:1| -     | Reserved (read as 0)                    |

```c
#define UART_RX_STATUS (*(volatile unsigned int *)0x8000000C)

// Example: Check for received data
if (UART_RX_STATUS & 1) {
    char c = UART_RX_DATA;
}
```

#### LED_CONTROL (0x80000010)
**Read/Write** - Control user LEDs

| Bit | Name | Description                      |
|-----|------|----------------------------------|
| 0   | LED1 | 1 = LED1 on, 0 = LED1 off        |
| 1   | LED2 | 1 = LED2 on, 0 = LED2 off        |
| 31:2| -    | Reserved (write 0, read as 0)    |

```c
#define LED_CONTROL (*(volatile unsigned int *)0x80000010)

// Example: Turn on both LEDs
LED_CONTROL = 0x3;  // bits 0 and 1 set

// Example: Turn on LED1 only
LED_CONTROL = 0x1;
```

#### MODE_CONTROL (0x80000014)
**Write Only** - Switch between SHELL and APP modes

| Value | Mode  | Description                                   |
|-------|-------|-----------------------------------------------|
| 0     | SHELL | Return to SHELL mode (CPU reset, loader active)|
| 1     | APP   | Enter APP mode (CPU running)                  |

```c
#define MODE_CONTROL (*(volatile unsigned int *)0x80000014)

// Example: Return to SHELL mode for firmware upload
MODE_CONTROL = 0;  // Reset CPU, activate firmware loader
```

**Warning**: Writing 0 to MODE_CONTROL resets the CPU and clears all RAM. Save any critical data before switching to SHELL mode.

#### BUTTON_INPUT (0x80000018)
**Read Only** - Read button states (synchronized, debounced)

| Bit | Name | Description                          |
|-----|------|--------------------------------------|
| 0   | BUT1 | 1 = BUT1 pressed, 0 = released       |
| 1   | BUT2 | 1 = BUT2 pressed, 0 = released       |
| 31:2| -    | Reserved (read as 0)                 |

**Note**: Buttons are active-low in hardware but inverted by synchronizers (active-high in software).

```c
#define BUTTON_INPUT (*(volatile unsigned int *)0x80000018)
#define BUT1_MASK 0x01
#define BUT2_MASK 0x02

// Example: Check if BUT1 is pressed
if (BUTTON_INPUT & BUT1_MASK) {
    // BUT1 is pressed
}

// Example: Read both buttons
unsigned int buttons = BUTTON_INPUT;
int but1_pressed = (buttons & BUT1_MASK) ? 1 : 0;
int but2_pressed = (buttons & BUT2_MASK) ? 1 : 0;
```

---

## Build System

The project uses a unified Makefile supporting all build targets.

### Directory Structure

```
olimex-ice40hx8k-riscv/
├── hdl/                    # Verilog HDL source files
│   ├── ice40_picorv32_top.v
│   ├── picorv32.v
│   ├── uart.v
│   ├── sram_*.v
│   └── ...
├── firmware/               # RISC-V C firmware
│   ├── interactive.c       # Bidirectional mode switching demo
│   ├── button_demo.c       # Button input demonstration
│   ├── start.s             # Startup code
│   └── Makefile
├── tools/
│   └── uploader/           # Cross-platform firmware uploader
│       ├── fw_upload.c
│       └── Makefile
├── sim/                    # ModelSim testbenches
│   ├── tb_*.sv
│   └── run_*.sh
├── build/                  # Build artifacts (generated)
├── Makefile                # Master build system
└── README.md
```

### Make Targets

#### Main Targets

```bash
make all          # Build everything (HDL + firmware + uploader)
make synth        # Synthesize HDL (Verilog → JSON)
make pnr          # Place and route (JSON → ASC)
make bitstream    # Generate bitstream (ASC → BIN)
make time         # Run timing analysis
make prog         # Program FPGA (Windows only)
make clean        # Remove build artifacts
make distclean    # Remove all generated files
```

#### Firmware Targets

```bash
make firmware                 # Build all firmware
make firmware-interactive     # Build interactive.hex
make firmware-button-demo     # Build button_demo.hex
make firmware-clean           # Clean firmware build
```

#### Uploader Targets

```bash
make uploader         # Build firmware uploader (Linux)
make uploader-clean   # Clean uploader build
```

#### Simulation Targets

```bash
make sim              # Run main simulation
make sim-interactive  # Test interactive firmware
make sim-crc          # Test CRC32 calculation
make sim-cpu          # Test CPU execution
make sim-r            # Test shell 'r' command
```

---

## Quick Start

### 1. Build Everything

```bash
cd olimex-ice40hx8k-riscv
make all
```

This builds:
- FPGA bitstream: `build/ice40_picorv32.bin`
- Firmware: `firmware/interactive.hex`, `firmware/button_demo.hex`
- Uploader: `tools/uploader/fw_upload`

### 2. Program FPGA (Windows Only)

```bash
make prog
```

**Important**: FPGA programming only works on Windows. The board's FTDI FT2232H Channel A (JTAG interface) does not enumerate as a COM device on Linux/macOS.

If you're on Linux/macOS:
1. Transfer `build/ice40_picorv32.bin` to a Windows machine
2. Program using `WinIceprog.exe -I COM5 ice40_picorv32.bin`

### 3. Upload Firmware (All Platforms)

```bash
cd tools/uploader
./fw_upload -p /dev/ttyUSB1 ../../firmware/interactive.hex
```

On Windows:
```cmd
fw_upload.exe -p COM8 ..\..\firmware\interactive.hex
```

**Port Identification**:
- **Linux**: `/dev/ttyUSB0`, `/dev/ttyUSB1`, etc.
- **macOS**: `/dev/tty.usbserial-*`
- **Windows**: `COM8` (FTDI Channel B - UART)

### 4. Interact with Running Firmware

Use a serial terminal (115200 baud, 8N1):

```bash
# Linux/macOS
screen /dev/ttyUSB1 115200

# Windows
putty -serial COM8 -sercfg 115200,8,n,1,N
```

---

## Firmware Development

### Memory Map

| Region         | Start Address | End Address | Size   | Description                     |
|----------------|---------------|-------------|--------|---------------------------------|
| SRAM           | `0x00000000`  | `0x0007FFFF`| 512KB  | Code and data                   |
| MMIO           | `0x80000000`  | `0x8000001F`| 32B    | Memory-mapped peripherals       |

### Startup Sequence

1. CPU reset vector: `0x00000000`
2. Startup code (`start.s`) initializes stack pointer
3. Jump to `main()` function
4. Firmware executes from SRAM

### Example: Minimal Firmware

```c
//==============================================================================
// Minimal RISC-V Firmware Example
//==============================================================================

#define UART_TX_DATA   (*(volatile unsigned int *)0x80000000)
#define UART_TX_STATUS (*(volatile unsigned int *)0x80000004)
#define LED_CONTROL    (*(volatile unsigned int *)0x80000010)

void putc(char c) {
    while (UART_TX_STATUS & 1);  // Wait while busy
    UART_TX_DATA = c;
}

void puts(const char *s) {
    while (*s) putc(*s++);
}

void main() {
    LED_CONTROL = 0x1;  // Turn on LED1
    puts("Hello from RISC-V!\r\n");

    while (1) {
        // Main loop
    }
}
```

### Building Custom Firmware

1. Create your C source file in `firmware/`
2. Update `firmware/Makefile` if needed
3. Build:

```bash
cd firmware
make TARGET=your_firmware
```

This generates `your_firmware.hex` ready for upload.

### Linker Script

The linker script (`firmware/sections.lds` if exists, or default) places:
- `.text`: Code at `0x00000000`
- `.data`: Initialized data after code
- `.bss`: Uninitialized data (zero-initialized)
- `.stack`: Stack at top of SRAM

---

## Simulation

### Running Simulations

All simulations use ModelSim/Questa. The `sim/` directory contains:
- Testbenches: `tb_*.sv`
- Run scripts: `run_*.sh`

#### Interactive Firmware Test

```bash
cd sim
./run_interactive_test.sh
```

Tests:
- UART communication
- Mode switching (SHELL ↔ APP)
- LED control
- Firmware execution

#### CRC32 Validation Test

```bash
cd sim
./run_crc_test.sh
```

Tests:
- CRC32 calculation (IEEE 802.3 polynomial)
- Firmware upload protocol
- Error detection

#### CPU Execution Test

```bash
cd sim
./run_cpu_test.sh
```

Tests:
- RISC-V instruction execution
- SRAM read/write operations
- MMIO register access

### Viewing Waveforms

After running a simulation, open the waveform viewer:

```bash
vsim -view vsim.wlf
```

---

## Performance Metrics

### Resource Utilization

Based on NextPNR place-and-route report:

| Resource       | Used  | Total | Utilization |
|----------------|-------|-------|-------------|
| Logic Cells    | 7595  | 7680  | **98.9%**   |
| Flip-Flops     | ~3200 | 7680  | ~42%        |
| LUTs           | ~4400 | 7680  | ~57%        |
| Block RAM      | 0     | 32    | 0%          |
| PLL            | 1     | 2     | 50%         |

**Critical**: The design uses 98.9% of available logic cells, leaving minimal room for expansion.

### Timing

- **Target Clock Frequency**: 12 MHz (83.33 ns period)
- **Actual Max Frequency**: **41.79 MHz** (23.93 ns period)
- **Timing Margin**: **+247% slack**

The design meets timing with significant margin. The 12 MHz target was chosen conservatively for reliability.

### Synthesis Statistics

- **Yosys Synthesis Time**: ~45 seconds
- **NextPNR Place & Route Time**: ~120 seconds (heap placer)
- **Bitstream Size**: ~104 KB

---

## Known Limitations

### 1. FPGA Programming: Windows Only

**Problem**: The Olimex iCE40HX8K-EVB board does NOT enumerate as a COM/serial device on Linux or macOS for JTAG/SPI programming.

**Reason**: The FTDI FT2232H Channel A (used for FPGA bitstream upload) requires Windows-specific drivers and enumeration.

**Workaround**:
- Program the FPGA on Windows using `WinIceprog.exe`
- All other operations (firmware upload, serial communication) work on all platforms

### 2. High Resource Utilization

**Problem**: 98.9% logic cell utilization leaves no room for additional features.

**Impact**: Any changes to HDL may fail place-and-route.

**Solution**: See [Optimization Opportunities](#optimization-opportunities).

### 3. Button Debouncing

**Problem**: Physical buttons may bounce (generate multiple transitions).

**Current Behavior**: 2-stage synchronizers prevent metastability but don't debounce.

**Impact**: Fast button presses may register multiple times.

**Mitigation**: Add firmware-level debouncing (delay + re-check).

### 4. UART FIFO Depth

**Problem**: TX and RX FIFOs are only 16 bytes deep.

**Impact**: Firmware must poll UART status frequently to avoid overflow.

**Workaround**: Use interrupt-driven UART (requires custom implementation).

---

## Optimization Opportunities

To reduce resource utilization and increase performance:

### 1. Remove Interactive Shell

**Impact**: Save ~2000 logic cells (~26% reduction)

The SHELL mode with interactive commands (`u`, `r`, `d`, `s`) consumes significant resources for:
- Command parsing
- ASCII-to-binary conversion
- CRC32 calculation in hardware
- String formatting

**Alternative**: Implement a simpler firmware loader (binary upload only).

### 2. Optimize Binary-to-ASCII Conversion

**Impact**: Save ~500 logic cells (~7% reduction)

The shell's binary-to-ASCII hex formatting (for `d` command) is inefficient, converting in one cycle using large combinational logic.

**Alternative**:
- Convert iteratively (one nibble per cycle)
- Remove debug `d` command entirely

### 3. Reduce UART FIFO Depth

**Impact**: Save ~200 logic cells (~3% reduction)

Current 16-byte FIFOs may be excessive for this application.

**Alternative**: Use 8-byte or 4-byte FIFOs.

### 4. Use Block RAM for UART FIFOs

**Impact**: Save ~400 logic cells (~5% reduction)

Currently UART FIFOs are implemented in logic cells. The iCE40HX8K has 32 block RAMs (4 Kbit each) that are **completely unused**.

**Alternative**: Instantiate SB_RAM256x16 primitives for FIFO storage.

### 5. Simplify PicoRV32 Configuration

**Impact**: Save ~1000 logic cells (~13% reduction)

The PicoRV32 includes optional features that may not be needed:
- Multiply/divide instructions
- Compressed instructions (RV32EC)
- Debug interface

**Alternative**: Disable unused features via PicoRV32 parameters.

### Combined Optimizations

Implementing all optimizations above could reduce utilization to **~4000 logic cells (52%)**, providing ample room for expansion.

---

## Troubleshooting

### FPGA Programming Fails

**Symptom**: `WinIceprog.exe` reports error or no device found.

**Solutions**:
1. Verify USB cable is connected (FTDI Channel A)
2. Check Device Manager for "USB Serial Converter A" (COM5)
3. Try different USB port
4. Reinstall FTDI drivers from https://ftdichip.com/drivers/

### Firmware Upload Fails

**Symptom**: `fw_upload` reports CRC error or timeout.

**Solutions**:
1. Verify FPGA is programmed with correct bitstream
2. Check UART port (Channel B, not Channel A)
3. Verify 115200 baud rate
4. Reset board (re-program FPGA or power cycle)
5. Try a different USB cable

### UART Communication Not Working

**Symptom**: No response in serial terminal.

**Solutions**:
1. Verify UART settings: 115200 baud, 8N1, no flow control
2. Check correct port (Linux: `/dev/ttyUSB1`, Windows: `COM8`)
3. Ensure firmware was uploaded successfully
4. Check `MODE_CONTROL` is set to APP mode (CPU running)

### Buttons Not Responding

**Symptom**: `BUTTON_INPUT` register always reads 0.

**Solutions**:
1. Verify buttons are physically pressed
2. Check PCF file for correct pin assignments (BUT1: K11, BUT2: P13)
3. Buttons are active-low; ensure synchronizers invert correctly
4. Check global reset is deasserted

### LEDs Not Lighting

**Symptom**: LEDs don't respond to `LED_CONTROL` writes.

**Solutions**:
1. Verify PCF file pin assignments (LED1: M12, LED2: R16)
2. Check LED polarity (active-high)
3. Verify FPGA bitstream includes LED control logic
4. Test with known-good firmware (`button_demo.hex`)

### Build Fails: "No Space" or "Unable to find legal placement"

**Symptom**: NextPNR reports "cannot place", "no legal placement", or "design is probably at utilisation limit".

**Cause**: 98% utilization is extremely tight. Different nextpnr versions have different placement success rates.

**Version-Specific Notes**:
- **nextpnr-0.7** (Linux): Successfully builds with `--placer heap --seed 1`
- **nextpnr-0.9** (OSS CAD Suite): May fail with heap placer due to stricter algorithms

**Solutions**:

1. **Try different seeds** (most effective):
```bash
# Try seeds 1-20
for seed in {1..20}; do
  nextpnr-ice40 --hx8k --package ct256 \
    --json build/ice40_picorv32.json --pcf hdl/ice40_picorv32.pcf \
    --asc build/ice40_picorv32.asc --placer heap --seed $seed
  if [ $? -eq 0 ]; then echo "Success with seed $seed!"; break; fi
done
```

2. **Try SA placer** (often better for tight designs):
```bash
nextpnr-ice40 --hx8k --package ct256 \
  --json build/ice40_picorv32.json --pcf hdl/ice40_picorv32.pcf \
  --asc build/ice40_picorv32.asc --placer sa
```

3. **Reduce utilization**:
   - See [Optimization Opportunities](#optimization-opportunities)
   - Removing the shell could reduce to ~52% utilization

---

## Additional Resources

### Datasheets

- [Lattice iCE40 FPGA Family](https://www.latticesemi.com/iCE40)
- [Olimex iCE40HX8K-EVB Board Manual](https://www.olimex.com/Products/FPGA/iCE40/iCE40HX8K-EVB/)
- [K6R4016V1D SRAM](https://www.samsung.com/semiconductor/global.semi/file/resource/2017/11/K6R4016V1D_Rev10.pdf)
- [FTDI FT2232H](https://ftdichip.com/products/ft2232hq/)

### Open-Source Tools

- [PicoRV32 GitHub](https://github.com/YosysHQ/picorv32)
- [Yosys](https://github.com/YosysHQ/yosys)
- [NextPNR](https://github.com/YosysHQ/nextpnr)
- [Project IceStorm](http://bygone.clairexen.net/icestorm/)

### RISC-V Resources

- [RISC-V Specifications](https://riscv.org/technical/specifications/)
- [RISC-V GNU Toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)

---

## License

This project is licensed for **educational and research purposes only**.

**NOT FOR COMMERCIAL USE**

See the `LICENSE` file for complete terms and conditions.

---

## Contact

**Michael Wolak**
Email: mikewolak@gmail.com, mike@epromfoundry.com

For bug reports, questions, or contributions, please contact the author.

---

**Project Status**: Active Development
**Last Updated**: October 2025
