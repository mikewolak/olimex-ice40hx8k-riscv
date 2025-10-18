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

def has_newlib():
    """Check if toolchain has newlib support"""
    # Try to compile a simple test that uses stdio.h
    prefix = detect_toolchain_prefix()
    try:
        # Check if the include path exists
        result = subprocess.run(
            [f'{prefix}gcc', '-march=rv32im', '-mabi=ilp32', '-E', '-x', 'c', '-'],
            input=b'#include <stdio.h>\nint main() { return 0; }',
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5
        )
        return result.returncode == 0
    except:
        return False

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
    """Categorize firmware into bare metal, simple newlib, and complex (with libs)"""
    bare = []
    newlib = []
    complex_fw = []
    complex_deps = {}  # Maps firmware name to list of (lib_name, lib_sources, include_path) tuples
    skip = ['timer_ms', 'timer_lib']  # Library files, not standalone programs

    # Library definitions: name -> (sources glob, include path)
    libraries = {
        'incurses': (glob.glob('lib/incurses/*.c'), 'lib/incurses'),
        'microrl': (glob.glob('lib/microrl/*.c'), 'lib/microrl'),
        'simple_upload': (glob.glob('lib/simple_upload/*.c'), 'lib/simple_upload'),
    }

    for src in glob.glob('firmware/*.c'):
        basename = os.path.basename(src).replace('.c', '')

        # Skip library files
        if basename in skip:
            continue

        # Read source to check for dependencies
        with open(src, 'r') as f:
            content = f.read(2000)  # Read first 2000 chars

        # Check if it uses external libraries
        uses_libs = []
        for lib_name, (lib_sources, lib_include) in libraries.items():
            if f'lib/{lib_name}/' in content or f'{lib_name}.h' in content:
                uses_libs.append((lib_name, lib_sources, lib_include))

        if uses_libs:
            # Complex firmware with library dependencies
            complex_fw.append(basename)
            complex_deps[basename] = uses_libs
        elif any(hdr in content for hdr in ['<stdio.h>', '<stdlib.h>', '<string.h>', '<math.h>', '_write', '_read', '_sbrk']):
            # Simple newlib firmware
            newlib.append(basename)
        else:
            # Bare metal firmware
            bare.append(basename)

    return bare, newlib, complex_fw, complex_deps

def generate_ninja():
    """Generate build.ninja file"""

    nproc = get_nproc()
    prefix = detect_toolchain_prefix()
    tools = detect_fpga_tools()
    bare_targets, newlib_targets, complex_targets, complex_deps = categorize_firmware()

    # Check if newlib is available
    newlib_available = has_newlib()
    if not newlib_available:
        if len(newlib_targets) > 0:
            print(f"⚠ Warning: Newlib not found - skipping {len(newlib_targets)} newlib targets")
            newlib_targets = []
        if len(complex_targets) > 0:
            print(f"⚠ Warning: Newlib not found - skipping {len(complex_targets)} complex targets")
            complex_targets = []
            complex_deps = {}

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

rule cc_newlib_with_flags
  command = ${prefix}gcc $newlib_cflags $cflags_extra -c $in -o $out
  description = Compiling (newlib+libs) $in

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

        # Firmware builds (complex with libraries)
        f.write("# Firmware (with libraries)\n")

        # First, build all library object files
        built_libs = set()
        for target, deps in complex_deps.items():
            for lib_name, lib_sources, lib_include in deps:
                if lib_name not in built_libs:
                    # Build all .c files in this library
                    for lib_src in lib_sources:
                        lib_obj = f"$builddir/lib_{lib_name}_{os.path.basename(lib_src).replace('.c', '.o')}"
                        f.write(f"build {lib_obj}: cc_newlib_with_flags {lib_src}\n")
                        f.write(f"  cflags_extra = -I{lib_include}\n\n")
                    built_libs.add(lib_name)

        # Now build complex firmware
        for target in complex_targets:
            deps = complex_deps[target]

            # Collect all include paths
            include_paths = ' '.join([f'-I{lib_include}' for lib_name, lib_sources, lib_include in deps])

            # Collect all library object files
            lib_objs = []
            for lib_name, lib_sources, lib_include in deps:
                for lib_src in lib_sources:
                    lib_obj = f"$builddir/lib_{lib_name}_{os.path.basename(lib_src).replace('.c', '.o')}"
                    lib_objs.append(lib_obj)

            # Compile firmware with library includes
            f.write(f"build $builddir/{target}.o: cc_newlib_with_flags $firmdir/{target}.c\n")
            f.write(f"  cflags_extra = {include_paths}\n\n")

            # Link firmware with library objects
            all_objs = ' '.join(['$builddir/fw_start.o', f'$builddir/{target}.o'] + lib_objs)
            f.write(f"build $firmdir/{target}.elf: ld_newlib {all_objs}\n")
            f.write(f"  ldscript = $firmdir/linker.ld\n")
            f.write(f"build $firmdir/{target}.bin: objcopy $firmdir/{target}.elf\n\n")

        if complex_targets:
            f.write(f"build firmware-complex: phony {' '.join([f'$firmdir/{t}.bin' for t in complex_targets])}\n\n")
        else:
            f.write("build firmware-complex: phony\n\n")

        f.write("build firmware-all: phony firmware-bare firmware-newlib firmware-complex\n\n")

        # HDL synthesis
        hdl_sources = glob.glob('hdl/*.v')
        # Exclude alternative/backup versions that would cause duplicate module definitions
        hdl_sources = [f for f in hdl_sources if '_2cycle' not in f and '.3state' not in f]
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
    print(f"  Complex firmware (with libs): {len(complex_targets)} targets")

if __name__ == '__main__':
    generate_ninja()
