#!/bin/bash
# Script to apply standardized copyright headers

# Verilog/SystemVerilog header
apply_verilog_header() {
    local file=$1
    local desc=$2
    local tmpfile=$(mktemp)
    
    cat > "$tmpfile" << EOF
//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// $(basename "$file") - $desc
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

EOF
    
    # Skip existing comments and blank lines at start
    awk '/^[^\/\s]/ { p=1 } p' "$file" >> "$tmpfile"
    mv "$tmpfile" "$file"
    echo "✓ Updated: $file"
}

# C source header
apply_c_header() {
    local file=$1
    local desc=$2
    local tmpfile=$(mktemp)
    
    cat > "$tmpfile" << EOF
//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// $(basename "$file") - $desc
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

EOF
    
    # Skip existing comments and includes/defines
    awk '/^[^\/\s*]/ { p=1 } p' "$file" >> "$tmpfile"
    mv "$tmpfile" "$file"
    echo "✓ Updated: $file"
}

# Makefile/Script header
apply_make_header() {
    local file=$1
    local desc=$2
    local tmpfile=$(mktemp)
    
    cat > "$tmpfile" << EOF
#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# $(basename "$file") - $desc
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

EOF
    
    # Preserve shebang if exists, skip other comments
    if head -1 "$file" | grep -q "^#!"; then
        head -1 "$file" > "${tmpfile}.tmp"
        echo "" >> "${tmpfile}.tmp"
        cat "$tmpfile" >> "${tmpfile}.tmp"
        awk 'NR>1 && /^[^#\s]/ { p=1 } p' "$file" >> "${tmpfile}.tmp"
        mv "${tmpfile}.tmp" "$file"
        rm -f "$tmpfile"
    else
        awk '/^[^#\s]/ { p=1 } p' "$file" >> "$tmpfile"
        mv "$tmpfile" "$file"
    fi
    echo "✓ Updated: $file"
}

echo "Applying copyright headers..."
echo "================================"

# HDL Files (Verilog/SystemVerilog)
echo ""
echo "Processing HDL files..."
apply_verilog_header "hdl/picorv32.v" "PicoRV32 RISC-V CPU Core"
apply_verilog_header "hdl/uart.v" "UART Controller with TX/RX FIFO"
apply_verilog_header "hdl/circular_buffer.v" "Circular Buffer for UART FIFOs"
apply_verilog_header "hdl/crc32_gen.v" "CRC32 Generator (IEEE 802.3)"
apply_verilog_header "hdl/sram_driver_new.v" "SRAM Physical Interface Driver"
apply_verilog_header "hdl/sram_proc_new.v" "SRAM Memory Controller"
apply_verilog_header "hdl/firmware_loader.v" "Firmware Upload Protocol Handler"
apply_verilog_header "hdl/shell.v" "Interactive Shell Command Processor"
apply_verilog_header "hdl/mem_controller.v" "Memory Controller with SRAM Interface"
apply_verilog_header "hdl/mmio_peripherals.v" "Memory-Mapped I/O Peripherals"
apply_verilog_header "hdl/mode_controller.v" "Mode Controller (SHELL/APP)"
apply_verilog_header "hdl/ice40_picorv32_top.v" "Top-Level FPGA Design"

# Firmware Files
echo ""
echo "Processing firmware files..."
apply_c_header "firmware/interactive.c" "Interactive Firmware with Bidirectional Mode Control"
apply_c_header "firmware/button_demo.c" "Button Input Demonstration Firmware"
apply_c_header "firmware/start.s" "RISC-V Startup Code"
apply_c_header "firmware/sections.lds" "Linker Script for RISC-V Firmware"

# Uploader Files
echo ""
echo "Processing uploader files..."
apply_c_header "tools/uploader/fw_upload.c" "Cross-Platform Firmware Uploader"

# Makefiles
echo ""
echo "Processing Makefiles..."
apply_make_header "Makefile" "Master Build System"
apply_make_header "firmware/Makefile" "Firmware Build System"
apply_make_header "tools/uploader/Makefile" "Uploader Build System"

# Simulation Scripts
echo ""
echo "Processing simulation scripts..."
apply_make_header "sim/run_interactive_test.sh" "Interactive Firmware Simulation"
apply_make_header "sim/run_crc_test.sh" "CRC32 Test Simulation"
apply_make_header "sim/run_cpu_test.sh" "CPU Execution Test Simulation"
apply_make_header "sim/run_r_test.sh" "Shell 'r' Command Test Simulation"

# Testbenches
echo ""
echo "Processing testbenches..."
apply_verilog_header "sim/ice40_picorv32_tb.v" "Top-Level Testbench"

# PCF (Pin Constraint File) - treat as make-style comments
echo ""
echo "Processing constraint files..."
apply_make_header "hdl/ice40_picorv32.pcf" "Pin Constraint File for iCE40HX8K-CT256"

echo ""
echo "================================"
echo "✓ All copyright headers applied!"
echo "================================"