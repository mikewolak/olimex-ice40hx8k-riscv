#!/bin/bash
#==============================================================================
# Simple Interrupt Test - ModelSim Simulation
# run_simple_irq_test.sh
#
# Tests basic interrupt handling by manually triggering IRQ from testbench
# Verifies firmware counter matches testbench trigger count (10 interrupts)
#==============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "========================================"
echo "SIMPLE INTERRUPT TEST"
echo "Testing: Manual IRQ Triggering"
echo "Target: 10 interrupts, counter match"
echo "========================================"
echo ""

# Set ModelSim path with proper Unix utilities
export PATH=/usr/bin:/bin:/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin

# Clean previous build
echo -e "${YELLOW}Cleaning previous simulation...${NC}"
rm -rf work
rm -f transcript
rm -f vsim.wlf
rm -f simple_irq_test.vcd
rm -f simple_irq_test.log

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

# Bootloader ROM
echo "  - bootloader_rom.v"
vlog -sv +define+SIMULATION -work work ../hdl/bootloader_rom.v

# Memory controller
echo "  - mem_controller.v"
vlog -sv +define+SIMULATION -work work ../hdl/mem_controller.v

# SRAM modules
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
echo "  - timer_peripheral.v"
vlog -sv +define+SIMULATION -work work ../hdl/timer_peripheral.v
echo "  - mmio_peripherals.v"
vlog -sv +define+SIMULATION -work work ../hdl/mmio_peripherals.v

# Top level
echo "  - ice40_picorv32_top.v"
vlog -sv +define+SIMULATION -work work ../hdl/ice40_picorv32_top.v

# Testbench
echo "  - tb_simple_irq_test.sv"
vlog -sv +define+SIMULATION -work work tb_simple_irq_test.sv

# Run simulation
echo ""
echo -e "${YELLOW}Running simulation...${NC}"
echo ""

vsim -c -do "run -all; quit -f" work.tb_simple_irq_test | tee simple_irq_test.log

# Check results
echo ""
echo -e "${YELLOW}Checking results...${NC}"

if grep -q "PASS: Interrupt counts match!" simple_irq_test.log; then
    echo -e "${GREEN}✓ TEST PASSED${NC}"
    echo -e "${GREEN}  Interrupt handling working correctly!${NC}"
    exit 0
elif grep -q "FAIL: Interrupt count mismatch!" simple_irq_test.log; then
    echo -e "${RED}✗ TEST FAILED${NC}"
    echo -e "${RED}  Counter mismatch - check log for details${NC}"
    exit 1
else
    echo -e "${RED}✗ TEST ERROR${NC}"
    echo -e "${RED}  Simulation did not complete properly${NC}"
    exit 1
fi
