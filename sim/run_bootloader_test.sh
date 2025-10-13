#!/bin/bash
#==============================================================================
# Bootloader Complete Test - ModelSim Simulation
# run_bootloader_test.sh
#
# Tests complete bootloader upload and firmware execution flow
# Timeout: 1 hour (as specified in testbench)
#==============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "========================================"
echo "BOOTLOADER COMPLETE TEST"
echo "Testing: Upload + Execution"
echo "Timeout: 1 hour"
echo "========================================"
echo ""

# Set ModelSim path with proper Unix utilities
export PATH=/usr/bin:/bin:/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin

# Clean previous build
echo -e "${YELLOW}Cleaning previous simulation...${NC}"
rm -rf work
rm -f transcript
rm -f vsim.wlf
rm -f tb_bootloader_complete.vcd
rm -f *.log

# Create work library
echo -e "${YELLOW}Creating work library...${NC}"
vlib work
vmap work work

# Compile HDL sources
echo ""
echo -e "${YELLOW}Compiling HDL sources...${NC}"

# Core CPU
echo "  - picorv32.v"
vlog -sv +define+SIMULATION -work work ../hdl/picorv32.v

# Memory components
echo "  - bootloader_rom.v"
vlog -sv +define+SIMULATION -work work ../hdl/bootloader_rom.v

echo "  - boot_loader_init.v"
vlog -sv +define+SIMULATION -work work ../hdl/boot_loader_init.v

echo "  - mem_controller.v"
vlog -sv +define+SIMULATION -work work ../hdl/mem_controller.v

# SRAM interface
echo "  - sram_driver_new.v"
vlog -sv +define+SIMULATION -work work ../hdl/sram_driver_new.v

echo "  - sram_proc_new.v"
vlog -sv +define+SIMULATION -work work ../hdl/sram_proc_new.v

# Peripherals
echo "  - uart.v"
vlog -sv +define+SIMULATION -work work ../hdl/uart.v

echo "  - circular_buffer.v"
vlog -sv +define+SIMULATION -work work ../hdl/circular_buffer.v

echo "  - crc32_gen.v"
vlog -sv +define+SIMULATION -work work ../hdl/crc32_gen.v

echo "  - mmio_peripherals.v"
vlog -sv +define+SIMULATION -work work ../hdl/mmio_peripherals.v

# Top-level
echo "  - ice40_picorv32_top.v"
vlog -sv +define+SIMULATION -work work ../hdl/ice40_picorv32_top.v

# Testbench
echo "  - tb_bootloader_complete.sv"
vlog -sv +define+SIMULATION -work work tb_bootloader_complete.sv

# Check compilation success
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Compilation successful${NC}"

# Run simulation
echo ""
echo -e "${YELLOW}Starting simulation...${NC}"
echo "Note: This test can take up to 1 hour to complete"
echo ""

# Run with extended timeout (1 hour = 3600 seconds)
# Add -do "run -all; quit -f" to auto-run and quit
timeout 3700 vsim -c -do "run -all; quit -f" work.tb_bootloader_complete | tee simulation.log

# Check simulation result
if grep -q "TEST COMPLETE" simulation.log; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ BOOTLOADER TEST PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Summary:"
    grep "✓" simulation.log | tail -10
    echo ""
    exit 0
elif grep -q "ERROR" simulation.log; then
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ BOOTLOADER TEST FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Errors:"
    grep "ERROR" simulation.log | tail -20
    echo ""
    exit 1
else
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}? SIMULATION INCOMPLETE${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Simulation may have timed out or terminated unexpectedly"
    echo "Check simulation.log for details"
    echo ""
    exit 1
fi
