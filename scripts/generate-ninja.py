#!/usr/bin/env python3
#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Ninja Build Generator
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

import os
import subprocess
import glob

def get_nproc():
    """Get number of CPU cores"""
    try:
        return str(subprocess.check_output(['nproc']).decode().strip())
    except:
        return '4'

def detect_toolchain_prefix():
    """Detect RISC-V toolchain prefix"""
    prefixes = [
        'build/toolchain/bin/riscv64-unknown-elf-',
        'build/toolchain/bin/riscv32-unknown-elf-',
        'riscv64-unknown-elf-',
        'riscv32-unknown-elf-'
    ]

    for prefix in prefixes:
        if os.path.exists(prefix + 'gcc') or subprocess.call(['which', prefix + 'gcc'],
                                                             stdout=subprocess.DEVNULL,
                                                             stderr=subprocess.DEVNULL) == 0:
            return prefix
    return 'riscv64-unknown-elf-'

def detect_fpga_tools():
    """Detect FPGA tool paths"""
    tools = {}

    # Prefer downloaded tools
    if os.path.exists('downloads/oss-cad-suite/bin/yosys'):
        tools['yosys'] = 'downloads/oss-cad-suite/bin/yosys'
        tools['nextpnr'] = 'downloads/oss-cad-suite/bin/nextpnr-ice40'
        tools['icepack'] = 'downloads/oss-cad-suite/bin/icepack'
        tools['icetime'] = 'downloads/oss-cad-suite/bin/icetime'
    else:
        tools['yosys'] = 'yosys'
        tools['nextpnr'] = 'nextpnr-ice40'
        tools['icepack'] = 'icepack'
        tools['icetime'] = 'icetime'

    return tools

def get_firmware_targets():
    """Get list of firmware source files"""
    return glob.glob('firmware/*.c')

def categorize_firmware():
    """Categorize firmware into bare metal vs newlib based on includes"""
    bare = []
    newlib = []
    skip = ['timer_ms', 'timer_lib']  # Library files, not standalone programs

    for src in glob.glob('firmware/*.c'):
        basename = os.path.basename(src).replace('.c', '')

        # Skip library files
        if basename in skip:
            continue

        # Check if it uses standard library headers or syscalls
        with open(src, 'r') as f:
            content = f.read(2000)  # Read first 2000 chars
            # If uses stdlib headers or syscalls, needs newlib
            if any(hdr in content for hdr in ['<stdio.h>', '<stdlib.h>', '<string.h>', '<math.h>', '_write', '_read', '_sbrk']):
                newlib.append(basename)
            else:
                bare.append(basename)

    return bare, newlib

def generate_ninja():
    """Generate build.ninja file"""

    nproc = get_nproc()
    prefix = detect_toolchain_prefix()
    tools = detect_fpga_tools()
    bare_targets, newlib_targets = categorize_firmware()

    with open('build.ninja', 'w') as f:
        f.write("""#===============================================================================
# Olimex iCE40HX8K PicoRV32 RISC-V System
# Ninja Build File (Auto-generated)
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

""")

        # Variables
        f.write(f"""# Build configuration
nproc = {nproc}
prefix = {prefix}
yosys = {tools['yosys']}
nextpnr = {tools['nextpnr']}
icepack = {tools['icepack']}
icetime = {tools['icetime']}

# Directories
builddir = build
bootdir = bootloader
firmdir = firmware
hdldir = hdl
toolsdir = tools/uploader
artifactsdir = artifacts

# Compiler flags (bare metal)
bare_cflags = -march=rv32im -mabi=ilp32 -O2 -Wall -Wextra -ffreestanding -nostdlib
bare_ldflags = -march=rv32im -mabi=ilp32 -nostdlib -Wl,--gc-sections

# Compiler flags (with newlib)
newlib_cflags = -march=rv32im -mabi=ilp32 -O2 -Wall -Wextra
newlib_ldflags = -march=rv32im -mabi=ilp32 -Wl,--gc-sections -static

# Newlib library path
newlib_lib = build/toolchain/riscv64-unknown-elf/lib/rv32im/ilp32

""")

        # Rules
        f.write("""# Build rules
rule cc_bare
  command = ${prefix}gcc $bare_cflags -c $in -o $out
  description = Compiling (bare) $in

rule cc_newlib
  command = ${prefix}gcc $newlib_cflags -c $in -o $out
  description = Compiling (newlib) $in

rule ld_bare
  command = ${prefix}gcc $bare_ldflags -T $ldscript $in -o $out
  description = Linking (bare) $out

rule ld_newlib
  command = ${prefix}gcc $newlib_ldflags -T $ldscript $in -L$newlib_lib -lm -lc -lgcc -o $out
  description = Linking (newlib) $out

rule objcopy
  command = ${prefix}objcopy -O binary $in $out
  description = Creating binary $out

rule hexdump
  command = ${prefix}objdump -D $in > $out
  description = Creating hexdump $out

rule synthesis
  command = $yosys -q -p "read_verilog $in; synth_ice40 -abc9 -device hx8k -top ice40_picorv32_top -json $out"
  description = Synthesizing $in

rule pnr
  command = $nextpnr --hx8k --package ct256 --json $in --pcf $pcf --asc $out --placer heap --seed 1
  description = Place and route $in

rule pack
  command = $icepack $in $out
  description = Packing bitstream $out

rule timing
  command = $icetime -d hx8k -t -m -r $out $in
  description = Timing analysis $in

rule host_cc
  command = gcc -O2 -Wall -Wextra $in -o $out
  description = Compiling host tool $out

rule copy
  command = cp $in $out
  description = Copying $in

rule mkdir
  command = mkdir -p $out
  description = Creating directory $out

""")

        # Bootloader build
        f.write("""# Bootloader
rule as_bare
  command = ${prefix}gcc $bare_cflags -c $in -o $out
  description = Assembling $in

build $builddir/bootloader.o: cc_bare $bootdir/bootloader.c
build $builddir/start.o: as_bare $bootdir/start.S

build $bootdir/bootloader.elf: ld_bare $builddir/start.o $builddir/bootloader.o
  ldscript = $bootdir/linker.ld

build $bootdir/bootloader.bin: objcopy $bootdir/bootloader.elf

build $bootdir/bootloader.hex: hexdump $bootdir/bootloader.elf

build bootloader: phony $bootdir/bootloader.bin $bootdir/bootloader.hex

""")

        # Firmware builds (bare metal)
        f.write("# Firmware (bare metal)\n")
        # Build firmware start.S once, shared by all bare-metal firmware
        f.write("build $builddir/fw_start.o: as_bare $firmdir/start.S\n\n")
        for target in bare_targets:
            f.write(f"""build $builddir/{target}.o: cc_bare $firmdir/{target}.c
build $firmdir/{target}.elf: ld_bare $builddir/fw_start.o $builddir/{target}.o
  ldscript = $firmdir/linker.ld
build $firmdir/{target}.bin: objcopy $firmdir/{target}.elf

""")

        if bare_targets:
            f.write(f"build firmware-bare: phony {' '.join([f'$firmdir/{t}.bin' for t in bare_targets])}\n\n")
        else:
            f.write("build firmware-bare: phony\n\n")

        # Firmware builds (newlib)
        f.write("# Firmware (with newlib)\n")
        for target in newlib_targets:
            f.write(f"""build $builddir/{target}.o: cc_newlib $firmdir/{target}.c
build $firmdir/{target}.elf: ld_newlib $builddir/fw_start.o $builddir/{target}.o
  ldscript = $firmdir/linker.ld
build $firmdir/{target}.bin: objcopy $firmdir/{target}.elf

""")

        if newlib_targets:
            f.write(f"build firmware-newlib: phony {' '.join([f'$firmdir/{t}.bin' for t in newlib_targets])}\n\n")
        else:
            f.write("build firmware-newlib: phony\n\n")

        f.write("build firmware-all: phony firmware-bare firmware-newlib\n\n")

        # HDL synthesis
        hdl_sources = glob.glob('hdl/*.v')
        hdl_list = ' '.join(hdl_sources)

        f.write(f"""# FPGA Gateware
build $builddir/ice40_picorv32.json: synthesis {hdl_list}
  in = {hdl_list}

build $builddir/ice40_picorv32.asc: pnr $builddir/ice40_picorv32.json
  pcf = $hdldir/ice40_picorv32.pcf

build $builddir/ice40_picorv32.bin: pack $builddir/ice40_picorv32.asc

build $builddir/timing.rpt: timing $builddir/ice40_picorv32.asc

build bitstream: phony $builddir/ice40_picorv32.bin

build gateware: phony bitstream $builddir/timing.rpt

""")

        # Host tools
        f.write("""# Host Tools
build $toolsdir/fw_upload: host_cc $toolsdir/fw_upload.c

build uploader: phony $toolsdir/fw_upload

""")

        # Artifacts collection
        f.write("""# Artifacts
build $artifactsdir/host/fw_upload: copy $toolsdir/fw_upload | $artifactsdir/host
build $artifactsdir/gateware/ice40_picorv32.bin: copy $builddir/ice40_picorv32.bin | $artifactsdir/gateware
build $artifactsdir/firmware: phony

rule collect_firmware
  command = mkdir -p $artifactsdir/firmware && cp $firmdir/*.bin $artifactsdir/firmware/ 2>/dev/null || true
  description = Collecting firmware artifacts

build collect-firmware: collect_firmware | firmware-all

build $artifactsdir/host: mkdir
build $artifactsdir/gateware: mkdir

build artifacts: phony $artifactsdir/host/fw_upload $artifactsdir/gateware/ice40_picorv32.bin collect-firmware

""")

        # Top-level targets
        f.write("""# Top-level targets
build all: phony bootloader firmware-all gateware uploader artifacts

default all

""")

    print("Generated build.ninja successfully!")
    print(f"  CPU cores: {nproc}")
    print(f"  RISC-V toolchain: {prefix}")
    print(f"  Yosys: {tools['yosys']}")
    print(f"  NextPNR: {tools['nextpnr']}")
    print(f"  Bare-metal firmware: {len(bare_targets)} targets")
    print(f"  Newlib firmware: {len(newlib_targets)} targets")

if __name__ == '__main__':
    generate_ninja()
