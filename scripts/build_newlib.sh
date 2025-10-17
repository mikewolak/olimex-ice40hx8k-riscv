#!/bin/bash
# Build newlib C library for configured ISA

set -e

if [ ! -f .config ]; then
    echo "ERROR: .config not found"
    exit 1
fi

source .config

# Derive arch/abi from config
ARCH="rv32i"
if [ "${CONFIG_ENABLE_MUL}" = "y" ] && [ "${CONFIG_ENABLE_DIV}" = "y" ]; then
    ARCH="${ARCH}m"
fi
if [ "${CONFIG_COMPRESSED_ISA}" = "y" ]; then
    ARCH="${ARCH}c"
fi
ABI="ilp32"

DOWNLOADS_DIR="downloads"
NEWLIB_SRC="$DOWNLOADS_DIR/newlib"
NEWLIB_BUILD="$DOWNLOADS_DIR/newlib-build"
NEWLIB_INSTALL="build/sysroot"
NPROC=${NPROC:-$(nproc 2>/dev/null || echo 4)}

echo "========================================="
echo "Building Newlib"
echo "========================================="
echo "Architecture: $ARCH"
echo "ABI:          $ABI"
echo "Install to:   $NEWLIB_INSTALL"
echo ""
echo "⚠ Build time: ~30-45 minutes"
echo ""

# Clone newlib if needed
if [ ! -d "$NEWLIB_SRC" ]; then
    echo "Cloning newlib..."
    mkdir -p "$DOWNLOADS_DIR"
    git clone --depth 1 ${CONFIG_NEWLIB_REPO:-https://sourceware.org/git/newlib-cygwin.git} "$NEWLIB_SRC"
fi

# Create build directory
mkdir -p "$NEWLIB_BUILD"
mkdir -p "$NEWLIB_INSTALL"

cd "$NEWLIB_BUILD"

# Configure newlib
echo "Configuring newlib..."
if [ ! -f Makefile ]; then
    CFLAGS_FOR_TARGET="-march=$ARCH -mabi=$ABI -O2 -g"

    CONFIG_OPTS=""
    if [ "${CONFIG_NEWLIB_NANO}" = "y" ]; then
        CONFIG_OPTS="$CONFIG_OPTS --enable-newlib-nano-malloc"
        CONFIG_OPTS="$CONFIG_OPTS --enable-newlib-nano-formatted-io"
        CONFIG_OPTS="$CONFIG_OPTS --enable-newlib-reent-small"
    fi

    if [ "${CONFIG_NEWLIB_IO_FLOAT}" = "y" ]; then
        CONFIG_OPTS="$CONFIG_OPTS --enable-newlib-io-float"
    fi

    ../newlib/configure \
        --target=riscv64-unknown-elf \
        --prefix=$(cd ../../$NEWLIB_INSTALL && pwd) \
        --with-arch=$ARCH \
        --with-abi=$ABI \
        --disable-newlib-fvwrite-in-streamio \
        --disable-newlib-fseek-optimization \
        --disable-newlib-wide-orient \
        --disable-newlib-unbuf-stream-opt \
        --disable-newlib-supplied-syscalls \
        --disable-nls \
        --disable-multilib \
        $CONFIG_OPTS \
        CFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET"
fi

# Build newlib
echo ""
echo "Building newlib (this will take a while)..."
echo "Started: $(date)"
make -j$NPROC

# Install newlib
echo ""
echo "Installing newlib..."
make install

echo ""
echo "========================================="
echo "✓ Newlib built successfully"
echo "========================================="
echo "Completed: $(date)"
echo ""
echo "Installed to: $NEWLIB_INSTALL"
echo ""
echo "Libraries:"
find ../../$NEWLIB_INSTALL -name "*.a" | head -10
