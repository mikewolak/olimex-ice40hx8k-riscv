#!/bin/bash
#==============================================================================
# Timer Peripheral Integration Test - ModelSim Simulation
#==============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "========================================"
echo "TIMER PERIPHERAL INTEGRATION TEST"
echo "Testing: Timer peripheral IRQ generation"
echo "Target: 10 timer interrupts, counter = 10"
echo "========================================"
echo ""

# Set ModelSim path
export PATH=/usr/bin:/bin:/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin

# Clean previous build
echo -e "${YELLOW}Cleaning previous simulation...${NC}"
rm -rf work
rm -f transcript
rm -f vsim.wlf
rm -f timer_integration_test.vcd
rm -f timer_integration_test.log

# Create work library
echo -e "${YELLOW}Creating work library...${NC}"
vlib work
vmap work work

# Compile HDL sources
echo ""
echo -e "${YELLOW}Compiling HDL sources...${NC}"

echo "  - picorv32.v"
vlog -sv +define+SIMULATION -work work ../hdl/picorv32.v

echo "  - bootloader_rom.v"
vlog -sv +define+SIMULATION -work work ../hdl/bootloader_rom.v

echo "  - mem_controller.v"
vlog -sv +define+SIMULATION -work work ../hdl/mem_controller.v

echo "  - sram_driver_new.v"
vlog -sv +define+SIMULATION -work work ../hdl/sram_driver_new.v
echo "  - sram_proc_new.v"
vlog -sv +define+SIMULATION -work work ../hdl/sram_proc_new.v

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

echo "  - ice40_picorv32_top.v"
vlog -sv +define+SIMULATION -work work ../hdl/ice40_picorv32_top.v

echo "  - tb_timer_integration.sv"
vlog -sv +define+SIMULATION -work work tb_timer_integration.sv

# Run simulation
echo ""
echo -e "${YELLOW}Running simulation...${NC}"
echo ""

vsim -c -do "run -all; quit -f" work.tb_timer_integration | tee timer_integration_test.log

# Check results
echo ""
echo -e "${YELLOW}Checking results...${NC}"

if grep -q "PASS:" timer_integration_test.log; then
    echo -e "${GREEN}✓ TEST PASSED${NC}"
    echo -e "${GREEN}  Timer peripheral generating interrupts correctly!${NC}"
    exit 0
elif grep -q "FAIL:" timer_integration_test.log; then
    echo -e "${RED}✗ TEST FAILED${NC}"
    echo -e "${RED}  Counter mismatch - check log for details${NC}"
    exit 1
else
    echo -e "${RED}✗ TEST ERROR${NC}"
    echo -e "${RED}  Simulation did not complete properly${NC}"
    exit 1
fi
