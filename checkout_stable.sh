#!/bin/bash
#===============================================================================
# Checkout Stable Baseline (Pre-Optimization)
# Creates a separate checkout at commit 300cc5f - last known-good state
# before sram_proc_optimized was added
#===============================================================================

STABLE_COMMIT="300cc5f"
STABLE_DIR="../olimex-ice40hx8k-riscv"
SOURCE_DIR="$(pwd)"

echo "========================================="
echo "Checkout Stable Baseline"
echo "========================================="
echo ""
echo "This script creates a separate working directory with the"
echo "last known-good state before SRAM optimization changes."
echo ""
echo "Commit: $STABLE_COMMIT (Rename and simplify Mandelbrot benchmarks)"
echo "Target: $STABLE_DIR"
echo ""

# Check if directory exists
if [ -d "$STABLE_DIR" ]; then
    echo "WARNING: Directory $STABLE_DIR already exists!"
    echo ""
    read -p "Delete and recreate? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo "Removing existing directory..."
            rm -rf "$STABLE_DIR"
            ;;
        *)
            echo "Aborted. Directory not modified."
            exit 1
            ;;
    esac
fi

# Clone the repository
echo ""
echo "Cloning repository to $STABLE_DIR..."
git clone "$SOURCE_DIR" "$STABLE_DIR"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone repository!"
    exit 1
fi

# Change to new directory and checkout commit
echo ""
echo "Checking out commit $STABLE_COMMIT..."
cd "$STABLE_DIR"
git checkout "$STABLE_COMMIT"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to checkout commit $STABLE_COMMIT!"
    exit 1
fi

# Show status
echo ""
echo "========================================="
echo "Checkout Complete!"
echo "========================================="
echo ""
echo "Directory: $STABLE_DIR"
echo "Commit:    $(git log --oneline -1)"
echo ""

# Check SRAM controller version
sram_version=$(grep "sram_proc_.*sram_proc_cpu" hdl/ice40_picorv32_top.v | sed -n 's/.*\(sram_proc_[a-z_]*\) sram_proc_cpu.*/\1/p')
echo "SRAM Controller: $sram_version"
echo ""

# List available SRAM controller files
echo "Available SRAM files:"
ls -1 hdl/sram_proc*.v 2>/dev/null | sed 's/^/  - /'
echo ""

# Check for Mandelbrot firmware
if [ -f "firmware/mandelbrot_float.c" ] && [ -f "firmware/mandelbrot_fixed.c" ]; then
    echo "✓ Mandelbrot firmware files present:"
    echo "  - mandelbrot_float.c"
    echo "  - mandelbrot_fixed.c"
else
    echo "⚠ Warning: Mandelbrot firmware files not found!"
fi

echo ""
echo "========================================="
echo "To build firmware in this directory:"
echo "  cd $STABLE_DIR"
echo "  make TARGET=mandelbrot_float USE_NEWLIB=1"
echo "  make TARGET=mandelbrot_fixed USE_NEWLIB=1"
echo ""
echo "To build bitstream:"
echo "  make synth"
echo "  make pnr"
echo "  make bitstream"
echo "========================================="
echo ""

# Optional: Create a branch to get out of detached HEAD
read -p "Create a branch 'stable-baseline' to track changes? (y/N): " response
case "$response" in
    [yY][eE][sS]|[yY])
        git switch -c stable-baseline
        echo "✓ Created branch 'stable-baseline'"
        ;;
    *)
        echo "Staying in detached HEAD state (read-only mode)"
        ;;
esac

echo ""
echo "Done!"
