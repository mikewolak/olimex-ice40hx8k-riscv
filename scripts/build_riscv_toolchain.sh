#!/bin/bash
# Build RISC-V toolchain from source

set -e

if [ ! -f .config ]; then
    echo "ERROR: .config not found"
    exit 1
fi

source .config

DOWNLOADS_DIR="downloads"
BUILD_DIR="$DOWNLOADS_DIR/riscv-toolchain-build"
INSTALL_DIR="build/toolchain"
NPROC=${NPROC:-$(nproc 2>/dev/null || echo 4)}

# Determine architecture from config
ARCH="rv32i"
if [ "${CONFIG_ENABLE_MUL}" = "y" ] && [ "${CONFIG_ENABLE_DIV}" = "y" ]; then
    ARCH="${ARCH}m"
fi
if [ "${CONFIG_COMPRESSED_ISA}" = "y" ]; then
    ARCH="${ARCH}c"
fi

ABI="ilp32"

echo "========================================="
echo "Building RISC-V Toolchain"
echo "========================================="
echo "Architecture: $ARCH"
echo "ABI:          $ABI"
echo "Install to:   $INSTALL_DIR"
echo "Parallel jobs: $NPROC"
echo ""
echo "⚠ WARNING: This will take 1-2 hours!"
echo ""

# Clone toolchain sources if needed
if [ ! -d "$DOWNLOADS_DIR/riscv-gnu-toolchain" ]; then
    echo "Cloning RISC-V GNU toolchain..."
    git clone --recursive https://github.com/riscv/riscv-gnu-toolchain.git \
        "$DOWNLOADS_DIR/riscv-gnu-toolchain"
fi

# Create build directory
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

cd "$BUILD_DIR"

# Configure
echo "Configuring toolchain..."
if [ ! -f Makefile ]; then
    ../riscv-gnu-toolchain/configure \
        --prefix=$(cd ../../$INSTALL_DIR && pwd) \
        --with-arch=$ARCH \
        --with-abi=$ABI \
        --enable-multilib=no
fi

# Build
echo ""
echo "Building toolchain (this will take a while)..."
echo "Started: $(date)"
make -j$NPROC

echo ""
echo "Installing toolchain..."
make install

echo ""
echo "========================================="
echo "✓ RISC-V Toolchain built successfully"
echo "========================================="
echo "Completed: $(date)"
echo ""
echo "Installed to: $INSTALL_DIR"
echo ""
echo "Binaries:"
ls -lh ../../$INSTALL_DIR/bin/ | grep riscv64
echo ""
echo "Test:"
../../$INSTALL_DIR/bin/riscv64-unknown-elf-gcc --version | head -1
