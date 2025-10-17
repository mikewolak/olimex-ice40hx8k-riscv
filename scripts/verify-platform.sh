#!/bin/bash
#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Platform Verification Script
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# ⚠️  NOT FOR COMMERCIAL USE ⚠️
# Educational and research purposes only
#===============================================================================

set -e

echo "========================================="
echo "Platform Verification"
echo "========================================="
echo ""

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "✗ ERROR: This build system requires x86-64 Linux"
    echo "  Current architecture: $ARCH"
    exit 1
fi
echo "✓ Architecture: $ARCH"

# Check OS
OS=$(uname -s)
if [ "$OS" != "Linux" ]; then
    echo "✗ ERROR: This build system requires Linux"
    echo "  Current OS: $OS"
    exit 1
fi
echo "✓ Operating System: Linux"

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    DISTRO_NAME=$PRETTY_NAME
    echo "✓ Distribution: $DISTRO_NAME"
else
    DISTRO="unknown"
    echo "⚠ Warning: Cannot detect Linux distribution"
fi

echo ""
echo "Checking required build tools..."
echo ""

MISSING_TOOLS=()

# Check for essential build tools
if ! command -v gcc >/dev/null 2>&1; then
    MISSING_TOOLS+=("gcc")
fi

if ! command -v g++ >/dev/null 2>&1; then
    MISSING_TOOLS+=("g++")
fi

if ! command -v make >/dev/null 2>&1; then
    MISSING_TOOLS+=("make")
fi

if ! command -v git >/dev/null 2>&1; then
    MISSING_TOOLS+=("git")
fi

if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    MISSING_TOOLS+=("wget or curl")
fi

if ! command -v tar >/dev/null 2>&1; then
    MISSING_TOOLS+=("tar")
fi

if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
    echo "✓ All required build tools are installed"
    echo ""
    exit 0
fi

echo "✗ Missing required build tools: ${MISSING_TOOLS[@]}"
echo ""
echo "========================================="
echo "Installation Instructions"
echo "========================================="
echo ""

case "$DISTRO" in
    ubuntu|debian)
        echo "For Ubuntu/Debian, run:"
        echo ""
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y build-essential git wget curl tar"
        echo ""
        ;;
    fedora)
        echo "For Fedora, run:"
        echo ""
        echo "  sudo dnf groupinstall 'Development Tools'"
        echo "  sudo dnf install git wget curl tar"
        echo ""
        ;;
    rhel|centos|rocky|almalinux)
        echo "For RHEL/CentOS/Rocky/AlmaLinux, run:"
        echo ""
        echo "  sudo yum groupinstall 'Development Tools'"
        echo "  sudo yum install git wget curl tar"
        echo ""
        ;;
    arch|manjaro)
        echo "For Arch/Manjaro, run:"
        echo ""
        echo "  sudo pacman -S base-devel git wget curl tar"
        echo ""
        ;;
    opensuse*)
        echo "For openSUSE, run:"
        echo ""
        echo "  sudo zypper install -t pattern devel_basis"
        echo "  sudo zypper install git wget curl tar"
        echo ""
        ;;
    *)
        echo "For your distribution, install the following packages:"
        echo "  - GCC compiler"
        echo "  - G++ compiler"
        echo "  - make"
        echo "  - git"
        echo "  - wget or curl"
        echo "  - tar"
        echo ""
        echo "Consult your distribution's documentation for package names."
        echo ""
        ;;
esac

exit 1
