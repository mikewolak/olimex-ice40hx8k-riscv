#!/bin/bash
# Download FPGA tools only (for parallel downloads)

set -e

OS=$(uname -s)
ARCH=$(uname -m)

mkdir -p downloads

echo "Downloading OSS CAD Suite..."

# Get latest release from GitHub API
LATEST_RELEASE=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE" ]; then
    echo "ERROR: Could not fetch latest oss-cad-suite release"
    exit 1
fi

echo "Latest OSS CAD Suite release: $LATEST_RELEASE"

case "$OS" in
    Linux)
        if [ "$ARCH" = "x86_64" ]; then
            FPGA_URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${LATEST_RELEASE}/oss-cad-suite-linux-x64-${LATEST_RELEASE//-/}.tgz"
        else
            echo "ERROR: No pre-built OSS CAD Suite for $OS $ARCH"
            exit 1
        fi
        ;;
    Darwin)
        if [ "$ARCH" = "arm64" ]; then
            FPGA_URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${LATEST_RELEASE}/oss-cad-suite-darwin-arm64-${LATEST_RELEASE//-/}.tgz"
        else
            FPGA_URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${LATEST_RELEASE}/oss-cad-suite-darwin-x64-${LATEST_RELEASE//-/}.tgz"
        fi
        ;;
    *)
        echo "ERROR: Unsupported OS: $OS"
        exit 1
        ;;
esac

if [ ! -f downloads/oss-cad-suite.tgz ]; then
    wget -O downloads/oss-cad-suite.tgz "$FPGA_URL"
fi

echo "Extracting OSS CAD Suite..."
mkdir -p downloads/oss-cad-suite
tar -xzf downloads/oss-cad-suite.tgz -C downloads/oss-cad-suite --strip-components=1

echo "✓ FPGA tools ready"
