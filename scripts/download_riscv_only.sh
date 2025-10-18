#!/bin/bash
# Download RISC-V toolchain only (for parallel downloads)

set -e

INSTALL_DIR="build/toolchain"
OS=$(uname -s)
ARCH=$(uname -m)

mkdir -p "$INSTALL_DIR"
mkdir -p downloads

echo "Downloading RISC-V toolchain..."

case "$OS" in
    Linux)
        if [ "$ARCH" = "x86_64" ]; then
            RISCV_URL="https://github.com/stnolting/riscv-gcc-prebuilt/releases/download/rv32i-4.0.0/riscv32-unknown-elf.gcc-12.1.0.tar.gz"
        else
            echo "ERROR: No pre-built RISC-V toolchain for $OS $ARCH"
            exit 1
        fi
        ;;
    Darwin)
        echo "ERROR: macOS users should use Homebrew:"
        echo "  brew install riscv-gnu-toolchain"
        exit 1
        ;;
    *)
        echo "ERROR: Unsupported OS: $OS"
        exit 1
        ;;
esac

if [ ! -f downloads/riscv-toolchain.tar.gz ]; then
    wget -O downloads/riscv-toolchain.tar.gz "$RISCV_URL"
fi

echo "Extracting RISC-V toolchain..."
tar -xzf downloads/riscv-toolchain.tar.gz -C "$INSTALL_DIR" --strip-components=1

echo "✓ RISC-V toolchain ready"
