# Testing the Build System

## Quick Test on Fresh Machine

```bash
# Clone repository
git clone https://github.com/mikewolak/olimex-ice40hx8k-picorv32.git
cd olimex-ice40hx8k-picorv32

# Test 1: Load default configuration
make defconfig

# Test 2: Generate platform files
make generate

# Test 3: Verify generated files
ls -lh build/generated/
head -20 build/generated/start.S
grep MEMORY build/generated/linker.ld
grep "#define" build/generated/platform.h

# Test 4: Run test suite
make test-generators
```

## What Works Now

✅ **Configuration System**
- `make defconfig` - Loads working configuration
- `.config` created with all parameters

✅ **Generator Scripts**
- `build/generated/start.S` - IRQ handlers, BSS init, stack setup
- `build/generated/linker.ld` - Memory layout (256KB app, dynamic heap)
- `build/generated/platform.h` - MMIO addresses, helper functions
- `build/generated/config.vh` - Verilog parameters

✅ **Source Files**
- HDL: 21 Verilog files (peripherals + top-level)
- Bootloader: bootloader.c
- Firmware: 21 demo applications
- Libraries: syscalls, microrl, incurses, simple_upload
- Tools: fw_upload (UART uploader)

## What's TODO

⚠ **Build System** (not yet implemented)
- Bootloader compilation
- Firmware compilation
- HDL synthesis (Yosys)
- Place & route (NextPNR)
- Bitstream generation
- Ninja build generator

⚠ **Dependency Management** (not yet implemented)
- PicoRV32 auto-fetch from GitHub
- Toolchain download/build options
- Kconfig frontends (menuconfig)

## Expected Behavior

When complete, this should work:
```bash
make menuconfig   # Configure (if kconfig-mconf installed)
make              # Build everything
make mrproper     # Clean to pristine state
```

## Current Status

Repository is **buildable for testing generators only**.
Full build system coming next.

Generated files match the reference system's memory map and configuration.
