#!/bin/bash
#
# ModelSim Build and Run Script - Direct SRAM Load Test
# Tests: Direct Firmware Load -> CPU Release -> LED Verification
#

set -e

# ModelSim paths
VLIB=/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin/vlib
VLOG=/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin/vlog
VSIM=/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin/vsim

echo "========================================"
echo "PicoRV32 Direct SRAM Load Test"
echo "========================================"
echo ""

# Check firmware exists
if [ ! -f firmware/led_blink.bin ]; then
    echo "ERROR: Firmware not found!"
    echo "Building firmware..."
    make firmware
fi

echo "Firmware: $(ls -lh firmware/led_blink.bin)"
echo ""

# Clean previous work library
echo "Cleaning work library..."
rm -rf work
$VLIB work
echo ""

# Compile all RTL sources
echo "========================================"
echo "Compiling RTL sources..."
echo "========================================"

$VLOG -work work -sv \
    sram_driver_new.v \
    sram_proc_new.v \
    uart.v \
    circular_buffer.v \
    crc32_gen.v \
    firmware_loader.v \
    shell.v \
    picorv32.v \
    mem_controller.v \
    mmio_peripherals.v \
    mode_controller.v \
    ice40_picorv32_top.v

echo ""
echo "Compiling testbench..."
$VLOG -work work -sv tb_picorv32_direct.sv

echo ""
echo "========================================"
echo "Running simulation..."
echo "========================================"
echo ""

# Run simulation
$VSIM -c -do "run -all; quit" work.tb_picorv32_direct | tee simulation_direct.log

echo ""
echo "========================================"
echo "Simulation complete!"
echo "========================================"
echo ""
echo "Log file: simulation_direct.log"
echo "Waveform: tb_picorv32_direct.vcd"
echo ""

# Check for pass/fail
if grep -q "TEST PASSED" simulation_direct.log; then
    echo "*** TEST PASSED ***"
    exit 0
else
    echo "*** TEST FAILED ***"
    echo "Check simulation_direct.log for details"
    exit 1
fi
