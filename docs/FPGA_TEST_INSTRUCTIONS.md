# Testing Timer Interrupts on FPGA

## Overview

This guide walks through building and testing the timer interrupt firmware on the Olimex iCE40HX8K-EVB FPGA board.

## Prerequisites

- Olimex iCE40HX8K-EVB board
- RISC-V toolchain (riscv64-unknown-elf-gcc)
- iCE40 FPGA tools (Yosys, nextpnr-ice40, icepack, iceprog)
- UART terminal (minicom, screen, or PuTTY) at 115200 baud

## What the Test Does

The `irq_timer_test` firmware:
1. Enables interrupts in the CPU
2. Configures timer for 100μs period (10kHz)
3. Waits for 10 timer interrupts
4. Disables timer after 10 interrupts
5. Sets LEDs to 0x3 to signal completion

**Expected behavior:** LEDs should turn on after ~1ms (10 × 100μs)

## Step-by-Step Build Instructions

### Step 1: Build the Timer Test Firmware

```bash
cd firmware

# Compile the firmware with fixed IRQ wrapper
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 -g \
    -nostartfiles -nostdlib -nodefaultlibs -Wall -Wextra \
    -ffreestanding -fno-builtin -T linker.ld -Wl,--gc-sections \
    -Wl,-Map=irq_timer_test.map start.S irq_timer_test.c \
    -o irq_timer_test.elf

# Convert to Verilog hex format for FPGA
riscv64-unknown-elf-objcopy -O verilog irq_timer_test.elf irq_timer_test.hex

# Verify the hex file was created
ls -lh irq_timer_test.hex
```

### Step 2: Rebuild Bootloader ROM

The bootloader ROM needs to be regenerated with the new firmware:

```bash
cd ../bootloader

# Rebuild bootloader (if needed)
make clean
make

cd ..
```

### Step 3: Regenerate Bootloader ROM Verilog Module

```bash
# This embeds the bootloader hex into the Verilog module
cd hdl
# (Your existing script or method to regenerate bootloader_rom.v)
cd ..
```

### Step 4: Run Full Synthesis Build

```bash
# From project root directory
make clean
TARGET=irq_timer_test make

# This will:
# 1. Build firmware (irq_timer_test.hex)
# 2. Build bootloader
# 3. Run Yosys synthesis
# 4. Run nextpnr place & route
# 5. Generate bitstream (build/ice40_picorv32.bin)
```

**Expected output:**
- `firmware/irq_timer_test.hex` - Firmware for FPGA
- `bootloader/bootloader.hex` - Bootloader ROM
- `build/ice40_picorv32.bin` - FPGA bitstream

### Step 5: Program the FPGA

```bash
# Program the bitstream to FPGA SRAM
iceprog build/ice40_picorv32.bin

# Or program to flash (survives power cycle):
iceprog -w build/ice40_picorv32.bin
```

## Alternative: Quick Build for Existing Firmware

If you just want to rebuild with the timer_clock firmware (which also tests timers):

```bash
TARGET=timer_clock make
iceprog build/ice40_picorv32.bin
```

## Expected Results on FPGA

### Visual Indicators

1. **During test (first ~1ms):**
   - LEDs OFF or blinking rapidly (depending on implementation)

2. **After test completes:**
   - Both LEDs ON (LED1 + LED2 = 0x3)
   - This indicates 10 interrupts were successfully handled

### UART Output (if enabled)

If you've enabled UART debugging in the firmware, you should see:
```
Timer test starting...
IRQ count: 1
IRQ count: 2
IRQ count: 3
...
IRQ count: 10
Test complete! LEDs = 0x3
```

Connect to UART at 115200 baud:
```bash
minicom -D /dev/ttyUSB0 -b 115200
# or
screen /dev/ttyUSB0 115200
```

## Troubleshooting

### Build Fails

**Problem:** Compilation errors in firmware
- **Solution:** Ensure start.S has the IRQ wrapper fix (saves a0-a7, t0-t6)

**Problem:** Yosys/nextpnr not found
- **Solution:** Install iCE40 toolchain or add to PATH

**Problem:** RISC-V toolchain not found
- **Solution:** Install riscv64-unknown-elf-gcc or add to PATH

### FPGA Programming Issues

**Problem:** `iceprog: can't find iCE FTDI USB device`
- **Solution:** Check USB cable, install FTDI drivers, or run with sudo

**Problem:** Bitstream loads but nothing happens
- **Solution:**
  - Press reset button on board
  - Check that bootloader ROM was rebuilt with correct firmware
  - Verify firmware hex file is not empty

### Test Doesn't Complete

**Problem:** LEDs never turn on
- **Possible causes:**
  1. Timer peripheral not generating interrupts → Check timer configuration
  2. IRQ wrapper not preserving registers → Verify start.S fix is applied
  3. Bootloader not loading firmware correctly → Check bootloader_rom.v

**Problem:** System appears hung
- **Solution:**
  - Check that interrupt counter is at correct address (0xFC)
  - Verify IRQ handler is being called
  - Use UART debugging to trace execution

## Verification

To verify the test ran successfully:

1. **Visual:** Both LEDs should be ON after ~1ms
2. **UART:** Should show "IRQ count" messages 1-10 (if debug enabled)
3. **Timing:** LEDs should turn on almost immediately after reset

## Files Modified for This Test

- `firmware/start.S` - **CRITICAL FIX:** Now saves all caller-saved registers
- `firmware/irq_timer_test.c` - Test firmware (waits for 10 timer IRQs)
- `hdl/timer_peripheral.v` - Timer peripheral with interrupt generation

## Next Steps

After successful FPGA testing:
- Try different timer periods (modify PSC/ARR registers)
- Add UART output to track interrupt count in real-time
- Implement more complex interrupt handling (multiple peripherals)

## Build Targets Reference

```bash
# Build with specific firmware
TARGET=led_blink make         # Simple LED blink test
TARGET=timer_clock make       # Timer clock with interrupts
TARGET=irq_timer_test make    # 10-interrupt test (this one!)
TARGET=interactive make       # Interactive UART shell
TARGET=button_demo make       # Button press detection

# Clean build
make clean

# Full rebuild
make clean && TARGET=irq_timer_test make
```

## Important Notes

⚠️ **The IRQ wrapper fix in start.S is CRITICAL** - Without it, the firmware will crash or exit prematurely due to register corruption during interrupt handling.

✓ **All firmware on this platform** now benefits from the robust interrupt handling (not just timer test)

📝 See `docs/INTERRUPT_BUG_FIX.md` for detailed analysis of the fix
