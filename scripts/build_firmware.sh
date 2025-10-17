#!/bin/bash
# Build firmware target

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <target> [USE_NEWLIB=0|1]"
    exit 1
fi

TARGET=$1
USE_NEWLIB=${2:-0}

if [ ! -f .config ]; then
    echo "ERROR: .config not found"
    exit 1
fi

source .config

# Toolchain
if [ -x "build/toolchain/bin/riscv64-unknown-elf-gcc" ]; then
    PREFIX="build/toolchain/bin/riscv64-unknown-elf-"
elif [ -x "build/toolchain/bin/riscv32-unknown-elf-gcc" ]; then
    PREFIX="build/toolchain/bin/riscv32-unknown-elf-"
else
    PREFIX="riscv64-unknown-elf-"
fi

GCC="${PREFIX}gcc"
OBJCOPY="${PREFIX}objcopy"
OBJDUMP="${PREFIX}objdump"

# Derive arch from config
ARCH="rv32i"
if [ "${CONFIG_ENABLE_MUL}" = "y" ] && [ "${CONFIG_ENABLE_DIV}" = "y" ]; then
    ARCH="${ARCH}m"
fi
if [ "${CONFIG_COMPRESSED_ISA}" = "y" ]; then
    ARCH="${ARCH}c"
fi
ABI="ilp32"

# Build directories
BUILD_DIR="build/firmware/$TARGET"
GENERATED="build/generated"

mkdir -p "$BUILD_DIR"

# Base flags
CFLAGS="-march=$ARCH -mabi=$ABI -O2 -g -Wall -Wextra"
CFLAGS="$CFLAGS -ffreestanding -fno-builtin"
CFLAGS="$CFLAGS -I$GENERATED"

LDFLAGS="-T $GENERATED/linker.ld -nostartfiles -Wl,--gc-sections"
LDFLAGS="$LDFLAGS -Wl,-Map=$BUILD_DIR/$TARGET.map"

LIBS="-lgcc"

# Source files
SOURCES="firmware/$TARGET.c"
ASM_SOURCES="$GENERATED/start.S"

# Extra sources and libraries based on target
case "$TARGET" in
    mandelbrot_fixed|mandelbrot_float)
        SOURCES="$SOURCES firmware/timer_ms.c"
        CFLAGS="$CFLAGS -Ilib/incurses"
        if [ "$USE_NEWLIB" = "1" ]; then
            EXTRA_OBJS="lib/incurses/incurses.c"
        fi
        ;;
    hexedit)
        CFLAGS="$CFLAGS -Ilib/simple_upload -Ilib/microrl -Ilib/incurses"
        if [ "$USE_NEWLIB" = "1" ]; then
            EXTRA_OBJS="lib/simple_upload/simple_upload.c lib/microrl/microrl.c lib/incurses/incurses.c"
        fi
        ;;
esac

# Newlib configuration
if [ "$USE_NEWLIB" = "1" ]; then
    SYSROOT="build/sysroot"

    if [ ! -d "$SYSROOT" ]; then
        echo "ERROR: Newlib not found at $SYSROOT"
        echo "Run: make build-newlib"
        exit 1
    fi

    CFLAGS="$CFLAGS --sysroot=$SYSROOT"
    LDFLAGS="$LDFLAGS --sysroot=$SYSROOT -static"
    LIBS="lib/syscalls.c $LIBS -lc -lm"

    # Add extra object files
    if [ -n "$EXTRA_OBJS" ]; then
        SOURCES="$SOURCES $EXTRA_OBJS"
    fi
fi

echo "========================================="
echo "Building: $TARGET"
echo "========================================="
echo "Arch:    $ARCH / $ABI"
echo "Newlib:  $([ "$USE_NEWLIB" = "1" ] && echo "yes" || echo "no")"
echo "Sources: $(echo $SOURCES | tr ' ' '\n' | wc -l) files"
echo ""

# Compile
echo "Compiling..."
$GCC $CFLAGS $LDFLAGS $ASM_SOURCES $SOURCES $LIBS -o "$BUILD_DIR/$TARGET.elf"

# Generate outputs
echo "Generating hex..."
$OBJCOPY -O verilog "$BUILD_DIR/$TARGET.elf" "$BUILD_DIR/$TARGET.hex"

echo "Generating binary..."
$OBJCOPY -O binary "$BUILD_DIR/$TARGET.elf" "$BUILD_DIR/$TARGET.bin"

echo "Generating disassembly..."
$OBJDUMP -D -S "$BUILD_DIR/$TARGET.elf" > "$BUILD_DIR/$TARGET.lst"

echo ""
echo "✓ Built: $TARGET"
echo "  ELF: $BUILD_DIR/$TARGET.elf"
echo "  HEX: $BUILD_DIR/$TARGET.hex"
echo "  BIN: $BUILD_DIR/$TARGET.bin"
echo ""
echo "Size:"
${PREFIX}size "$BUILD_DIR/$TARGET.elf"
