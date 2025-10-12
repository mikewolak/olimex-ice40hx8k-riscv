#!/bin/bash
#
# ModelSim simulation script for PicoRV32 firmware test
#

set -e

echo "========================================="
echo "ModelSim PicoRV32 Firmware Test"
echo "========================================="

# Clean previous build
rm -rf work
rm -f transcript
rm -f picorv32_firmware.vcd

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

# Compile testbench
echo "Compiling testbench..."
vlog -work work -sv tb_picorv32_modelsim.sv

# Run simulation
echo "Running simulation..."
vsim -c -do "run -all; quit" work.tb_picorv32_modelsim

echo ""
echo "========================================="
echo "Simulation complete"
echo "========================================="
