#!/bin/bash
# Build minimal FPGA toolchain (Yosys + NextPNR-ice40 + IceStorm)
# Optimized for iCE40 only

set -e

DOWNLOADS_DIR="downloads"
BUILD_DIR="$DOWNLOADS_DIR/fpga-tools-build"
INSTALL_DIR="build/toolchain"
NPROC=${NPROC:-$(nproc 2>/dev/null || echo 4)}

echo "========================================="
echo "Building FPGA Toolchain (iCE40 only)"
echo "========================================="
echo "Components:"
echo "  - IceStorm (iCE40 tools)"
echo "  - NextPNR-ice40 (place & route)"
echo "  - Yosys (synthesis)"
echo ""
echo "Install to:   $INSTALL_DIR"
echo "Parallel jobs: $NPROC"
echo ""
echo "⚠ Building minimal iCE40-only toolchain (~30-45 min)"
echo ""

mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"
PREFIX=$(cd "$INSTALL_DIR" && pwd)

cd "$BUILD_DIR"

# ============================================================================
# IceStorm - iCE40 FPGA bitstream tools
# ============================================================================

if [ ! -d icestorm ]; then
    echo "Cloning IceStorm..."
    git clone https://github.com/YosysHQ/icestorm.git
fi

echo ""
echo "[1/3] Building IceStorm..."
cd icestorm
make -j$NPROC
make install PREFIX="$PREFIX"
cd ..
echo "✓ IceStorm installed"

# ============================================================================
# NextPNR-ice40 - Place and route (iCE40 only)
# ============================================================================

if [ ! -d nextpnr ]; then
    echo ""
    echo "Cloning NextPNR..."
    git clone https://github.com/YosysHQ/nextpnr.git
fi

echo ""
echo "[2/3] Building NextPNR-ice40..."
cd nextpnr
mkdir -p build-ice40
cd build-ice40

cmake .. \
    -DARCH=ice40 \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DICESTORM_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_GUI=OFF \
    -DBUILD_PYTHON=OFF

make -j$NPROC
make install
cd ../..
echo "✓ NextPNR-ice40 installed"

# ============================================================================
# Yosys - Synthesis
# ============================================================================

if [ ! -d yosys ]; then
    echo ""
    echo "Cloning Yosys..."
    git clone https://github.com/YosysHQ/yosys.git
fi

echo ""
echo "[3/3] Building Yosys..."
cd yosys
make -j$NPROC CONFIG=gcc
make install PREFIX="$PREFIX"
cd ..

echo ""
echo "========================================="
echo "✓ FPGA Toolchain built successfully"
echo "========================================="
echo ""
echo "Installed to: $PREFIX"
echo ""
echo "Binaries:"
ls -lh "$PREFIX/bin/" | grep -E '(yosys|nextpnr-ice40|ice)'
echo ""
echo "Test:"
"$PREFIX/bin/yosys" -V | head -1
"$PREFIX/bin/nextpnr-ice40" --version 2>&1 | head -1
"$PREFIX/bin/icepack" --version 2>&1 | head -1 || echo "icepack (no version flag)"
