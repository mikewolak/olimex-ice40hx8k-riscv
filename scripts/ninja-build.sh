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

# Check for FPGA tools and auto-download if missing
check_fpga_tools() {
    # Check if yosys exists
    if command -v yosys >/dev/null 2>&1 || [ -f "downloads/oss-cad-suite/bin/yosys" ]; then
        return 0
    fi

    echo "FPGA tools not found. Downloading..."
    echo ""
    make ensure-fpga-tools

    if [ ! -f "downloads/oss-cad-suite/bin/yosys" ]; then
        echo "ERROR: Failed to download FPGA tools"
        exit 1
    fi
}

# Main
echo "========================================="
echo "Ninja Parallel Build System"
echo "========================================="
echo ""

# Check if we need to download toolchains in parallel
NEED_RISCV=0
NEED_FPGA=0

# Check for RISC-V toolchain
for prefix in "build/toolchain/bin/riscv64-unknown-elf-" "build/toolchain/bin/riscv32-unknown-elf-" "riscv64-unknown-elf-" "riscv32-unknown-elf-"; do
    if command -v ${prefix}gcc >/dev/null 2>&1 || [ -f "${prefix}gcc" ]; then
        NEED_RISCV=0
        break
    fi
    NEED_RISCV=1
done

# Check for FPGA tools
if ! command -v yosys >/dev/null 2>&1 && [ ! -f "downloads/oss-cad-suite/bin/yosys" ]; then
    NEED_FPGA=1
fi

# Download toolchains in parallel if needed
if [ $NEED_RISCV -eq 1 ] || [ $NEED_FPGA -eq 1 ]; then
    echo "Downloading toolchains in parallel..."
    echo ""

    if [ $NEED_RISCV -eq 1 ]; then
        echo "Starting RISC-V toolchain download in background..."
        bash scripts/download_riscv_only.sh > /tmp/ninja_riscv_download.log 2>&1 &
        RISCV_PID=$!
    fi

    if [ $NEED_FPGA -eq 1 ]; then
        echo "Starting FPGA tools download in background..."
        bash scripts/download_fpga_only.sh > /tmp/ninja_fpga_download.log 2>&1 &
        FPGA_PID=$!
    fi

    # Wait for both downloads to complete
    if [ $NEED_RISCV -eq 1 ]; then
        echo "Waiting for RISC-V toolchain download..."
        wait $RISCV_PID
        if [ $? -eq 0 ]; then
            echo "✓ RISC-V toolchain downloaded"
        else
            echo "ERROR: RISC-V toolchain download failed"
            cat /tmp/ninja_riscv_download.log
            exit 1
        fi
    fi

    if [ $NEED_FPGA -eq 1 ]; then
        echo "Waiting for FPGA tools download..."
        wait $FPGA_PID
        if [ $? -eq 0 ]; then
            echo "✓ FPGA tools downloaded"
        else
            echo "ERROR: FPGA tools download failed"
            cat /tmp/ninja_fpga_download.log
            exit 1
        fi
    fi

    echo ""
fi

# Final verification
check_toolchain
check_fpga_tools

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
