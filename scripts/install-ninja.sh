#!/bin/bash
#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Ninja Build System Installer
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

set -e

NINJA_VERSION="1.11.1"
NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"
INSTALL_DIR="downloads/ninja"
NINJA_BIN="$INSTALL_DIR/ninja"

echo "========================================="
echo "Ninja Build System Check"
echo "========================================="
echo ""

# Check if ninja is already in PATH
if command -v ninja >/dev/null 2>&1; then
    NINJA_PATH=$(which ninja)
    NINJA_VER=$(ninja --version 2>/dev/null || echo "unknown")
    echo "✓ Ninja found in PATH: $NINJA_PATH"
    echo "  Version: $NINJA_VER"
    exit 0
fi

# Check if we have a local installation
if [ -f "$NINJA_BIN" ]; then
    NINJA_VER=$($NINJA_BIN --version 2>/dev/null || echo "unknown")
    echo "✓ Ninja found locally: $NINJA_BIN"
    echo "  Version: $NINJA_VER"
    exit 0
fi

echo "Ninja not found. Installing locally..."
echo ""

# Create download directory
mkdir -p "$INSTALL_DIR"
mkdir -p downloads

# Download Ninja
echo "Downloading Ninja $NINJA_VERSION..."
if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress "$NINJA_URL" -O downloads/ninja.zip
elif command -v curl >/dev/null 2>&1; then
    curl -L --progress-bar "$NINJA_URL" -o downloads/ninja.zip
else
    echo "ERROR: Neither wget nor curl found. Please install one of them."
    exit 1
fi

# Extract Ninja
echo "Extracting Ninja..."
if command -v unzip >/dev/null 2>&1; then
    unzip -q downloads/ninja.zip -d "$INSTALL_DIR"
else
    echo "ERROR: unzip not found. Please install unzip."
    exit 1
fi

# Make executable
chmod +x "$NINJA_BIN"

# Clean up
rm -f downloads/ninja.zip

# Verify installation
if [ -f "$NINJA_BIN" ]; then
    NINJA_VER=$($NINJA_BIN --version)
    echo ""
    echo "========================================="
    echo "✓ Ninja installed successfully!"
    echo "========================================="
    echo ""
    echo "  Location: $NINJA_BIN"
    echo "  Version: $NINJA_VER"
    echo ""
    echo "Add to PATH with:"
    echo "  export PATH=\$PWD/$INSTALL_DIR:\$PATH"
    echo ""
else
    echo "ERROR: Ninja installation failed"
    exit 1
fi
