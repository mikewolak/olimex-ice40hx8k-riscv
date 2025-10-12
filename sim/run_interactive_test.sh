#!/bin/bash

#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# run_interactive_test.sh - Interactive Firmware Simulation
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

export PATH=/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin:$PATH

echo "========================================="
echo "ModelSim Interactive Firmware Test"
echo "========================================="

# Clean previous build
rm -rf work
rm -f transcript

# Create work library
echo "Creating work library..."
vlib work

# Compile RTL files
echo "Compiling RTL modules..."
vlog -work work ice40_picorv32_top.v
vlog -work work sram_driver_new.v
vlog -work work sram_proc_new.v
vlog -work work shell.v
vlog -work work uart.v
vlog -work work circular_buffer.v
vlog -work work crc32_gen.v
vlog -work work firmware_loader.v
vlog -work work picorv32.v
vlog -work work mem_controller.v
vlog -work work mmio_peripherals.v
vlog -work work mode_controller.v

# Compile testbench
echo "Compiling testbench..."
vlog -work work -sv tb_interactive.sv

# Run simulation
echo "Running interactive test simulation..."
vsim -c -do "run -all; quit" work.tb_interactive

echo ""
echo "========================================="
echo "Simulation complete"
echo "========================================="
