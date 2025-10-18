#!/bin/bash
#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Ninja Build Wrapper
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

set -e

# Detect Ninja binary
detect_ninja() {
    if command -v ninja >/dev/null 2>&1; then
        echo "ninja"
    elif [ -f "downloads/ninja/ninja" ]; then
        echo "downloads/ninja/ninja"
    else
        echo ""
    fi
}

# Install Ninja if needed
ensure_ninja() {
    NINJA=$(detect_ninja)
    if [ -z "$NINJA" ]; then
        echo "Ninja not found. Installing..."
        bash scripts/install-ninja.sh
        NINJA=$(detect_ninja)
        if [ -z "$NINJA" ]; then
            echo "ERROR: Failed to install Ninja"
            exit 1
        fi
    fi
    echo "$NINJA"
}

# Check for RISC-V toolchain
check_toolchain() {
    # Try different prefixes
    for prefix in "build/toolchain/bin/riscv64-unknown-elf-" "build/toolchain/bin/riscv32-unknown-elf-" "riscv64-unknown-elf-" "riscv32-unknown-elf-"; do
        if command -v ${prefix}gcc >/dev/null 2>&1 || [ -f "${prefix}gcc" ]; then
            return 0
        fi
    done

    echo "ERROR: RISC-V toolchain not found"
    echo ""
    echo "Please install the toolchain first:"
    echo "  make toolchain-check     # Check and auto-download"
    echo "  make toolchain-download  # Download prebuilt toolchain"
    echo "  make toolchain-riscv     # Or build from source (1-2 hours)"
    echo ""
    exit 1
}

# Main
echo "========================================="
echo "Ninja Parallel Build System"
echo "========================================="
echo ""

# Check for toolchain
check_toolchain

# Ensure Ninja is available
NINJA=$(ensure_ninja)
echo "Using Ninja: $NINJA"
echo ""

# Generate build.ninja
echo "Generating build.ninja..."
python3 scripts/generate-ninja.py
echo ""

# Get number of cores
NPROC=$(nproc 2>/dev/null || echo 4)

# Run Ninja
echo "Building with Ninja ($NPROC parallel jobs)..."
echo ""
$NINJA -j $NPROC "$@"

echo ""
echo "========================================="
echo "✓ Ninja Build Complete!"
echo "========================================="
