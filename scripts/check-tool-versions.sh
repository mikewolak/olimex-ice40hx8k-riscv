#!/bin/bash
#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Tool Version Checker
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

set -e

# Minimum required versions
MIN_YOSYS_MAJOR=0
MIN_YOSYS_MINOR=58
MIN_NEXTPNR_MAJOR=0
MIN_NEXTPNR_MINOR=9

NEED_DOWNLOAD=0

echo "========================================="
echo "Checking Tool Versions"
echo "========================================="
echo ""

# Check if downloaded tools exist
if [ -f downloads/oss-cad-suite/bin/yosys ] && [ -f downloads/oss-cad-suite/bin/nextpnr-ice40 ]; then
    echo "✓ Downloaded toolchain found (will be used automatically)"
    exit 0
fi

# Check Yosys version
if command -v yosys >/dev/null 2>&1; then
    YOSYS_VER=$(yosys -V 2>&1 | head -1 | grep -oP 'Yosys \K[0-9]+\.[0-9]+' | head -1)
    if [ -n "$YOSYS_VER" ]; then
        YOSYS_MAJOR=$(echo "$YOSYS_VER" | cut -d. -f1)
        YOSYS_MINOR=$(echo "$YOSYS_VER" | cut -d. -f2)

        if [ "$YOSYS_MAJOR" -lt "$MIN_YOSYS_MAJOR" ] || \
           ([ "$YOSYS_MAJOR" -eq "$MIN_YOSYS_MAJOR" ] && [ "$YOSYS_MINOR" -lt "$MIN_YOSYS_MINOR" ]); then
            echo "⚠  WARNING: Yosys $YOSYS_VER is too old (need $MIN_YOSYS_MAJOR.$MIN_YOSYS_MINOR+)"
            NEED_DOWNLOAD=1
        else
            echo "✓ Yosys $YOSYS_VER (meets minimum $MIN_YOSYS_MAJOR.$MIN_YOSYS_MINOR+)"
        fi
    fi
else
    echo "  Yosys not found in PATH"
    NEED_DOWNLOAD=1
fi

# Check NextPNR version
if command -v nextpnr-ice40 >/dev/null 2>&1; then
    NEXTPNR_VER=$(nextpnr-ice40 --version 2>&1 | grep -oP 'nextpnr-\K[0-9]+\.[0-9]+' | head -1)
    if [ -n "$NEXTPNR_VER" ]; then
        NEXTPNR_MAJOR=$(echo "$NEXTPNR_VER" | cut -d. -f1)
        NEXTPNR_MINOR=$(echo "$NEXTPNR_VER" | cut -d. -f2)

        if [ "$NEXTPNR_MAJOR" -lt "$MIN_NEXTPNR_MAJOR" ] || \
           ([ "$NEXTPNR_MAJOR" -eq "$MIN_NEXTPNR_MAJOR" ] && [ "$NEXTPNR_MINOR" -lt "$MIN_NEXTPNR_MINOR" ]); then
            echo "⚠  WARNING: NextPNR $NEXTPNR_VER is too old (need $MIN_NEXTPNR_MAJOR.$MIN_NEXTPNR_MINOR+)"
            NEED_DOWNLOAD=1
        else
            echo "✓ NextPNR $NEXTPNR_VER (meets minimum $MIN_NEXTPNR_MAJOR.$MIN_NEXTPNR_MINOR+)"
        fi
    fi
else
    echo "  NextPNR not found in PATH"
    NEED_DOWNLOAD=1
fi

echo ""

if [ $NEED_DOWNLOAD -eq 1 ]; then
    echo "========================================="
    echo "Action Required"
    echo "========================================="
    echo ""
    echo "Your system tools are missing or too old."
    echo "Compatible toolchain will be downloaded automatically."
    echo ""
    echo "Run: make toolchain-download"
    echo ""
    exit 1
fi

echo "✓ All tool versions are compatible"
exit 0
