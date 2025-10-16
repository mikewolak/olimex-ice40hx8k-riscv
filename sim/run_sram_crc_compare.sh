#!/bin/bash

#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# run_sram_crc_compare.sh - SRAM CRC32 Comparison Test
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#
# DESCRIPTION:
# Runs a side-by-side comparison of CRC32 calculations between sram_proc_new
# and sram_proc_optimized to verify the optimization fix is correct.
#===============================================================================

export PATH=/home/mwolak/intelFPGA_lite/20.1/modelsim_ase/bin:$PATH

echo "========================================="
echo "SRAM Processor CRC32 Comparison Test"
echo "========================================="
echo ""
echo "This test compares CRC32 calculations between:"
echo "  - sram_proc_new (original, known good)"
echo "  - sram_proc_optimized (optimized with CRC fix)"
echo ""

# Change to sim directory
cd "$(dirname "$0")"

# Clean previous build
echo "Cleaning previous build..."
rm -rf work
rm -f transcript
rm -f sram_crc_compare.log

# Create work library
echo "Creating work library..."
vlib work

# Compile HDL files from parent directory
echo ""
echo "Compiling HDL modules..."
vlog -work work ../hdl/sram_proc_new.v || exit 1
vlog -work work ../hdl/sram_proc_optimized.v || exit 1

# Compile testbench
echo ""
echo "Compiling testbench..."
vlog -work work -sv tb_sram_proc_crc_compare.sv || exit 1

# Run simulation
echo ""
echo "========================================="
echo "Running CRC comparison simulation..."
echo "========================================="
echo ""

vsim -c -do "run -all; quit" work.tb_sram_proc_crc_compare | tee sram_crc_compare.log

# Check results
echo ""
echo "========================================="
echo "Simulation Complete"
echo "========================================="

if grep -q "ALL TESTS PASSED" sram_crc_compare.log; then
    echo ""
    echo "✓ SUCCESS: All CRC tests passed!"
    echo "✓ The optimized CRC implementation is correct."
    echo ""
    exit 0
elif grep -q "SOME TESTS FAILED" sram_crc_compare.log; then
    echo ""
    echo "✗ FAILURE: Some CRC tests failed!"
    echo "✗ Check sram_crc_compare.log for details."
    echo ""
    exit 1
elif grep -q "TIMEOUT" sram_crc_compare.log; then
    echo ""
    echo "✗ TIMEOUT: Simulation did not complete."
    echo "✗ Possible deadlock or hang detected."
    echo ""
    exit 1
else
    echo ""
    echo "? UNKNOWN: Could not determine test result."
    echo "? Check sram_crc_compare.log for details."
    echo ""
    exit 1
fi
