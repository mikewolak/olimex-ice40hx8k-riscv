#!/bin/bash
#===============================================================================
# SRAM Controller Switcher
# Switches between sram_proc_new (11-cycle) and sram_proc_optimized (7-cycle)
#===============================================================================

TOP_LEVEL="hdl/ice40_picorv32_top.v"

# Check if top level file exists
if [ ! -f "$TOP_LEVEL" ]; then
    echo "ERROR: $TOP_LEVEL not found!"
    exit 1
fi

# Function to show current SRAM controller
show_current() {
    current=$(grep "sram_proc_.*sram_proc_cpu" "$TOP_LEVEL" | sed -n 's/.*\(sram_proc_[a-z_]*\) sram_proc_cpu.*/\1/p')
    echo "Current SRAM controller: $current"
}

# Function to switch to a specific controller
switch_to() {
    local target=$1
    local other=$2

    if grep -q "${target} sram_proc_cpu" "$TOP_LEVEL"; then
        echo "Already using ${target}"
        return 0
    fi

    echo "Switching from ${other} to ${target}..."
    sed -i "s/${other} sram_proc_cpu/${target} sram_proc_cpu/g" "$TOP_LEVEL"

    if grep -q "${target} sram_proc_cpu" "$TOP_LEVEL"; then
        echo "✓ Successfully switched to ${target}"
        return 0
    else
        echo "ERROR: Failed to switch!"
        return 1
    fi
}

# Parse command line arguments
case "$1" in
    new|original|11)
        show_current
        switch_to "sram_proc_new" "sram_proc_optimized"
        ;;
    optimized|opt|7)
        show_current
        switch_to "sram_proc_optimized" "sram_proc_new"
        ;;
    show|status)
        show_current
        ;;
    toggle|"")
        # Toggle between the two
        show_current
        if grep -q "sram_proc_new sram_proc_cpu" "$TOP_LEVEL"; then
            switch_to "sram_proc_optimized" "sram_proc_new"
        else
            switch_to "sram_proc_new" "sram_proc_optimized"
        fi
        ;;
    *)
        echo "SRAM Controller Switcher"
        echo ""
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  new, original, 11    - Switch to sram_proc_new (11-cycle, stable)"
        echo "  optimized, opt, 7    - Switch to sram_proc_optimized (7-cycle, 36% faster)"
        echo "  toggle               - Toggle between the two (default)"
        echo "  show, status         - Show current controller"
        echo ""
        echo "Examples:"
        echo "  $0                   # Toggle between controllers"
        echo "  $0 optimized         # Switch to optimized version"
        echo "  $0 new               # Switch to original version"
        echo "  $0 show              # Show current controller"
        exit 1
        ;;
esac

echo ""
echo "Current configuration:"
show_current
echo ""
echo "To rebuild with new controller:"
echo "  make clean"
echo "  make synth"
echo "  make pnr    (or make pnr-seeds if placement fails)"
