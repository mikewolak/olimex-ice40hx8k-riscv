#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Makefile - Master Build System
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

# Detect host OS and set appropriate toolchain prefix
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    # macOS - use homebrew RISC-V toolchain
    RISCV_PREFIX = riscv-none-elf-
    $(info Building on macOS - using $(RISCV_PREFIX) toolchain)
else
    # Linux/Windows - use standard toolchain
    RISCV_PREFIX = riscv64-unknown-elf-
    $(info Building on $(UNAME_S) - using $(RISCV_PREFIX) toolchain)
endif

HDL_DIR = hdl
HDL_SOURCES = $(HDL_DIR)/picorv32.v \
              $(HDL_DIR)/uart.v \
              $(HDL_DIR)/circular_buffer.v \
              $(HDL_DIR)/crc32_gen.v \
              $(HDL_DIR)/sram_driver_new.v \
              $(HDL_DIR)/sram_proc_new.v \
              $(HDL_DIR)/firmware_loader.v \
              $(HDL_DIR)/bootloader_rom.v \
              $(HDL_DIR)/mem_controller.v \
              $(HDL_DIR)/mmio_peripherals.v \
              $(HDL_DIR)/timer_peripheral.v \
              $(HDL_DIR)/ice40_picorv32_top.v

PCF_FILE = $(HDL_DIR)/ice40_picorv32.pcf
TOP_MODULE = ice40_picorv32_top

# Build Outputs
BUILD_DIR = build
JSON_FILE = $(BUILD_DIR)/ice40_picorv32.json
ASC_FILE = $(BUILD_DIR)/ice40_picorv32.asc
BIN_FILE = $(BUILD_DIR)/ice40_picorv32.bin
TIME_FILE = $(BUILD_DIR)/timing_report.txt

# Synthesis and PnR Tools
YOSYS = yosys
NEXTPNR = nextpnr-ice40
ICEPACK = icepack
ICETIME = icetime

# Synthesis Options
SYNTH_OPTS = -abc9

# PnR Options (use heap placer for high utilization designs)
PNR_DEVICE = hx8k
PNR_PACKAGE = ct256
PNR_OPTS = --placer heap --seed 1

# FPGA Programmer (Windows-specific - WinIceprog via FTDI)
# NOTE: FPGA programming only works on Windows due to FTDI enumeration issues
#       on Linux/macOS. The board does not enumerate as a COM/serial device
#       on Unix systems, requiring Windows and WinIceprog.exe for bitstream upload.
ICEPROG = WinIceprog.exe -I COM5

# Bootloader Build
BOOTLOADER_DIR = bootloader
BOOTLOADER_HEX = $(BOOTLOADER_DIR)/bootloader.hex

# Firmware Build
FIRMWARE_DIR = firmware
UPLOADER_DIR = tools/uploader

# System Libraries (newlib, etc.)
SYSTEM_DIR = system
NEWLIB_SRC_DIR = lib/newlib
NEWLIB_BUILD_DIR = lib/newlib-build
NEWLIB_INSTALL_DIR = $(SYSTEM_DIR)/riscv-newlib

# Target architecture for newlib (must match firmware/Makefile)
RISCV_ARCH = rv32im
RISCV_ABI = ilp32
RISCV_TARGET = $(RISCV_PREFIX:%-=%)  # Remove trailing dash from prefix

# Simulation
SIM_DIR = sim
MODELSIM = vsim

# ============================================================================
# Build Targets
# ============================================================================

.PHONY: all synth pnr pnr-sa pnr-sa-seeds pnr-seeds bitstream time clean help
.PHONY: bootloader bootloader-clean
.PHONY: firmware firmware-interactive firmware-button-demo firmware-led-blink firmware-clean
.PHONY: uploader uploader-linux uploader-clean
.PHONY: sim sim-interactive sim-crc sim-cpu sim-r
.PHONY: prog
.PHONY: newlib-fetch newlib-configure newlib-build newlib-install newlib-clean newlib-distclean

# Default target
all: bootloader bitstream firmware uploader
	@echo ""
	@echo "========================================="
	@echo "Build Complete!"
	@echo "========================================="
	@echo "Bootloader:  $(BOOTLOADER_HEX)"
	@echo "Bitstream:   $(BIN_FILE)"
	@echo "Firmware:    $(FIRMWARE_DIR)/led_blink.hex"
	@echo "             $(FIRMWARE_DIR)/interactive.hex"
	@echo "             $(FIRMWARE_DIR)/button_demo.hex"
	@echo "Uploader:    $(UPLOADER_DIR)/fw_upload"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Program FPGA: make prog (Windows only)"
	@echo "  2. Upload firmware: cd $(UPLOADER_DIR) && ./fw_upload -p COM8 ../../$(FIRMWARE_DIR)/interactive.hex"
	@echo ""

# ============================================================================
# Bootloader Build Targets
# ============================================================================

bootloader: $(BOOTLOADER_HEX)

$(BOOTLOADER_HEX):
	@echo "========================================="
	@echo "Building Bootloader"
	@echo "========================================="
	@$(MAKE) -C $(BOOTLOADER_DIR)
	@echo "✓ Bootloader built: $(BOOTLOADER_HEX)"

bootloader-clean:
	@$(MAKE) -C $(BOOTLOADER_DIR) clean

# ============================================================================
# HDL Synthesis and Place & Route
# ============================================================================

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Synthesis: Verilog -> JSON (depends on bootloader.hex for ROM initialization)
synth: $(BUILD_DIR) $(JSON_FILE)

$(JSON_FILE): $(HDL_SOURCES) $(BOOTLOADER_HEX)
	@echo "========================================="
	@echo "Synthesis: Verilog -> JSON"
	@echo "========================================="
	@echo "Tool:     Yosys"
	@echo "Target:   iCE40HX8K"
	@echo "Optimize: ABC9"
	$(YOSYS) -p "synth_ice40 -top $(TOP_MODULE) -json $(JSON_FILE) $(SYNTH_OPTS)" $(HDL_SOURCES)
	@echo "✓ Synthesis complete: $(JSON_FILE)"

# Place and Route: JSON -> ASC
pnr: $(BUILD_DIR) $(ASC_FILE)

$(ASC_FILE): $(JSON_FILE)
	@echo "========================================="
	@echo "Place and Route: JSON -> ASC"
	@echo "========================================="
	@echo "Tool:     NextPNR-iCE40"
	@echo "Device:   $(PNR_DEVICE)"
	@echo "Package:  $(PNR_PACKAGE)"
	@echo "Placer:   Heap (optimized for 98% utilization)"
	$(NEXTPNR) --$(PNR_DEVICE) --package $(PNR_PACKAGE) \
	           --json $(JSON_FILE) --pcf $(PCF_FILE) \
	           --asc $(ASC_FILE) $(PNR_OPTS)
	@echo "✓ Place and route complete: $(ASC_FILE)"

# Place and Route: JSON -> ASC (SA Placer)
# Use Simulated Annealing placer instead of heap (better for tight designs)
pnr-sa: $(BUILD_DIR) $(JSON_FILE)
	@echo "========================================="
	@echo "Place and Route: JSON -> ASC (SA Placer)"
	@echo "========================================="
	@echo "Tool:     NextPNR-iCE40"
	@echo "Device:   $(PNR_DEVICE)"
	@echo "Package:  $(PNR_PACKAGE)"
	@echo "Placer:   Simulated Annealing (better for tight designs)"
	$(NEXTPNR) --$(PNR_DEVICE) --package $(PNR_PACKAGE) \
	           --json $(JSON_FILE) --pcf $(PCF_FILE) \
	           --asc $(ASC_FILE) --placer sa --ignore-loops
	@echo "✓ Place and route complete: $(ASC_FILE)"

# Place and Route: JSON -> ASC (SA Placer with multiple seeds)
pnr-sa-seeds: $(BUILD_DIR) $(JSON_FILE)
	@echo "========================================="
	@echo "Place and Route: SA Placer with Seeds"
	@echo "========================================="
	@echo "Trying SA placer with seeds 1-20"
	@echo ""
	@for seed in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
		echo "Trying SA placer with seed $$seed..."; \
		if $(NEXTPNR) --$(PNR_DEVICE) --package $(PNR_PACKAGE) \
		   --json $(JSON_FILE) --pcf $(PCF_FILE) \
		   --asc $(ASC_FILE) --placer sa --seed $$seed --ignore-loops > $(BUILD_DIR)/pnr_sa_seed$$seed.log 2>&1 && \
		   test -f $(ASC_FILE); then \
			echo ""; \
			echo "========================================"; \
			echo "SUCCESS with SA seed $$seed!"; \
			echo "========================================"; \
			echo "✓ Place and route complete: $(ASC_FILE)"; \
			exit 0; \
		fi; \
		echo "SA seed $$seed failed, trying next..."; \
		echo ""; \
	done; \
	echo "ERROR: All SA seeds failed. Using pre-built bitstream may be required."; \
	exit 1

# Place and Route: Try multiple seeds (for nextpnr-0.9+)
# Tries seeds 1-20 until one succeeds
pnr-seeds: $(BUILD_DIR) $(JSON_FILE)
	@echo "========================================="
	@echo "Place and Route: Trying Multiple Seeds"
	@echo "========================================="
	@echo "This will try seeds 1-20 with heap placer"
	@echo "Useful for nextpnr-0.9+ with 98% utilization"
	@echo ""
	@for seed in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
		echo "Trying seed $$seed..."; \
		if $(NEXTPNR) --$(PNR_DEVICE) --package $(PNR_PACKAGE) \
		   --json $(JSON_FILE) --pcf $(PCF_FILE) \
		   --asc $(ASC_FILE) --placer heap --seed $$seed > $(BUILD_DIR)/pnr_seed$$seed.log 2>&1 && \
		   test -f $(ASC_FILE); then \
			echo ""; \
			echo "========================================"; \
			echo "SUCCESS with seed $$seed!"; \
			echo "========================================"; \
			echo "✓ Place and route complete: $(ASC_FILE)"; \
			exit 0; \
		fi; \
		echo "Seed $$seed failed, trying next..."; \
		echo ""; \
	done; \
	echo "ERROR: All seeds failed. Try 'make pnr-sa' or reduce design size."; \
	exit 1

# Pack Bitstream: ASC -> BIN
bitstream: $(BUILD_DIR) $(BIN_FILE)

$(BIN_FILE): $(ASC_FILE)
	@echo "========================================="
	@echo "Pack Bitstream: ASC -> BIN"
	@echo "========================================="
	$(ICEPACK) $(ASC_FILE) $(BIN_FILE)
	@echo "✓ Bitstream complete: $(BIN_FILE)"
	@ls -lh $(BIN_FILE)

# Timing Analysis
time: $(ASC_FILE)
	@echo "========================================="
	@echo "Timing Analysis"
	@echo "========================================="
	$(ICETIME) -d $(PNR_DEVICE) -mtr $(TIME_FILE) $(ASC_FILE)
	@echo ""
	@echo "Timing report saved to: $(TIME_FILE)"
	@grep -A5 "Max frequency" $(TIME_FILE) || cat $(TIME_FILE)

# ============================================================================
# Firmware Build Targets
# ============================================================================

firmware:
	@echo "========================================="
	@echo "Building Firmware"
	@echo "========================================="
	@$(MAKE) -C $(FIRMWARE_DIR)

firmware-interactive:
	@echo "Building interactive.hex..."
	@$(MAKE) -C $(FIRMWARE_DIR) TARGET=interactive single-target

firmware-button-demo:
	@echo "Building button_demo.hex..."
	@$(MAKE) -C $(FIRMWARE_DIR) TARGET=button_demo single-target

firmware-led-blink:
	@echo "Building led_blink.hex..."
	@$(MAKE) -C $(FIRMWARE_DIR) TARGET=led_blink single-target

firmware-clean:
	@$(MAKE) -C $(FIRMWARE_DIR) clean

# ============================================================================
# System Libraries - Newlib (C Standard Library for RISC-V)
# ============================================================================

# Fetch newlib source from git if not present
newlib-fetch:
	@echo "========================================="
	@echo "Checking Newlib Source"
	@echo "========================================="
	@mkdir -p lib
	@mkdir -p $(SYSTEM_DIR)
	@if [ ! -d "$(NEWLIB_SRC_DIR)" ]; then \
		echo "Newlib source not found. Cloning from git..."; \
		echo "Repository: https://sourceware.org/git/newlib-cygwin.git"; \
		echo "This may take a few minutes..."; \
		echo ""; \
		git clone --depth 1 https://sourceware.org/git/newlib-cygwin.git $(NEWLIB_SRC_DIR) || \
		(echo "ERROR: Failed to clone newlib. Check your internet connection." && exit 1); \
		echo ""; \
		echo "✓ Newlib source cloned to $(NEWLIB_SRC_DIR)"; \
	else \
		echo "✓ Newlib source found at $(NEWLIB_SRC_DIR)"; \
	fi

# Configure newlib for rv32im/ilp32 only
newlib-configure: newlib-fetch
	@echo "========================================="
	@echo "Configuring Newlib for $(RISCV_ARCH)/$(RISCV_ABI)"
	@echo "========================================="
	@echo "Target:  $(RISCV_TARGET)"
	@echo "Arch:    $(RISCV_ARCH)"
	@echo "ABI:     $(RISCV_ABI)"
	@echo "Install: $(NEWLIB_INSTALL_DIR)"
	@echo ""
	@mkdir -p $(NEWLIB_BUILD_DIR)
	@mkdir -p $(SYSTEM_DIR)
	@cd $(NEWLIB_BUILD_DIR) && \
	../newlib/configure \
		--target=$(RISCV_TARGET) \
		--prefix=$(PWD)/$(NEWLIB_INSTALL_DIR) \
		--with-arch=$(RISCV_ARCH) \
		--with-abi=$(RISCV_ABI) \
		--enable-newlib-nano-malloc \
		--enable-newlib-nano-formatted-io \
		--enable-newlib-reent-small \
		--disable-newlib-fvwrite-in-streamio \
		--disable-newlib-fseek-optimization \
		--disable-newlib-wide-orient \
		--disable-newlib-unbuf-stream-opt \
		--disable-newlib-supplied-syscalls \
		--disable-nls \
		--disable-multilib \
		CFLAGS_FOR_TARGET="-march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -O2 -g" \
		> build_configure.log 2>&1
	@echo "✓ Newlib configured for $(RISCV_ARCH)/$(RISCV_ABI) only"
	@echo "  See $(NEWLIB_BUILD_DIR)/build_configure.log for details"

# Build newlib (single target only - much faster!)
newlib-build: newlib-configure
	@echo "========================================="
	@echo "Building Newlib for $(RISCV_ARCH)/$(RISCV_ABI)"
	@echo "========================================="
	@echo "This will build ONLY for $(RISCV_ARCH)/$(RISCV_ABI)"
	@echo "(not all RISC-V variants - should take ~30 min instead of 12 hours)"
	@echo ""
	@cd $(NEWLIB_BUILD_DIR) && \
		$(MAKE) -j$$(nproc) > build.log 2>&1 || \
		(tail -50 build.log && exit 1)
	@echo "✓ Newlib built successfully"
	@echo "  Build log: $(NEWLIB_BUILD_DIR)/build.log"

# Install newlib to system directory
newlib-install: newlib-build
	@echo "========================================="
	@echo "Installing Newlib to $(NEWLIB_INSTALL_DIR)"
	@echo "========================================="
	@cd $(NEWLIB_BUILD_DIR) && \
		$(MAKE) install > install.log 2>&1
	@echo "✓ Newlib installed to $(NEWLIB_INSTALL_DIR)"
	@echo ""
	@echo "Installed libraries:"
	@ls -lh $(NEWLIB_INSTALL_DIR)/$(RISCV_TARGET)/lib/$(RISCV_ARCH)/$(RISCV_ABI)/*.a 2>/dev/null || \
		ls -lh $(NEWLIB_INSTALL_DIR)/$(RISCV_TARGET)/lib/*.a 2>/dev/null || \
		echo "  (libraries will be in subdirectories)"
	@echo ""
	@echo "Update firmware/Makefile to use:"
	@echo "  CFLAGS += -isystem ../$(NEWLIB_INSTALL_DIR)/$(RISCV_TARGET)/include"
	@echo "  LDFLAGS += -L../$(NEWLIB_INSTALL_DIR)/$(RISCV_TARGET)/lib"
	@echo "  LIBS = -lc -lm -lgcc"

# Clean newlib build artifacts (keep configuration)
newlib-clean:
	@echo "Cleaning newlib build artifacts..."
	@cd $(NEWLIB_BUILD_DIR) && $(MAKE) clean 2>/dev/null || true
	@echo "✓ Newlib build artifacts cleaned"

# Complete clean of newlib (requires reconfigure)
newlib-distclean:
	@echo "Removing all newlib build files..."
	@rm -rf $(NEWLIB_BUILD_DIR)
	@rm -rf $(NEWLIB_INSTALL_DIR)
	@echo "✓ Newlib completely removed (requires reconfigure)"

# ============================================================================
# Firmware Uploader (Host Software)
# ============================================================================

uploader: uploader-linux

uploader-linux:
	@echo "Building firmware uploader (Linux)..."
	@$(MAKE) -C $(UPLOADER_DIR) linux

uploader-clean:
	@$(MAKE) -C $(UPLOADER_DIR) clean

# ============================================================================
# Simulation Targets (ModelSim/Questa)
# ============================================================================

sim: sim-interactive

sim-interactive:
	@echo "Running interactive firmware simulation..."
	@cd $(SIM_DIR) && ./run_interactive_test.sh

sim-crc:
	@echo "Running CRC32 test..."
	@cd $(SIM_DIR) && ./run_crc_test.sh

sim-cpu:
	@echo "Running CPU execution test..."
	@cd $(SIM_DIR) && ./run_cpu_test.sh

sim-r:
	@echo "Running shell 'r' command test..."
	@cd $(SIM_DIR) && ./run_r_test.sh

# ============================================================================
# FPGA Programming (Windows Only)
# ============================================================================

# Program FPGA with WinIceprog.exe (Windows only)
# NOTE: This board does not enumerate as a serial device on Linux/macOS.
#       FPGA programming must be done on Windows using WinIceprog.exe.
#       The FTDI FT2232H requires Windows drivers to access JTAG interface.
prog: $(BIN_FILE)
	@echo "========================================="
	@echo "Programming FPGA (Windows Only)"
	@echo "========================================="
	@echo "Tool:   WinIceprog.exe"
	@echo "Port:   COM5 (FTDI FT2232H Channel A)"
	@echo "File:   $(BIN_FILE)"
	@echo ""
	@echo "IMPORTANT: FPGA programming only works on Windows!"
	@echo "           Linux/macOS cannot access the JTAG interface."
	@echo ""
	$(ICEPROG) $(BIN_FILE)
	@echo "✓ FPGA programmed successfully"

# ============================================================================
# Cleanup
# ============================================================================

clean: bootloader-clean firmware-clean uploader-clean
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -f *.log *.vcd
	@echo "✓ Clean complete"

distclean: clean
	@echo "Cleaning all generated files..."
	@rm -rf $(SIM_DIR)/work
	@rm -f $(SIM_DIR)/*.log $(SIM_DIR)/*.wlf $(SIM_DIR)/transcript
	@echo "✓ Deep clean complete"

# ============================================================================
# Help
# ============================================================================

help:
	@echo "Olimex iCE40HX8K-EVB RISC-V Platform - Build System (Bootloader Edition)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all              - Build everything (bootloader + HDL + firmware + uploader)"
	@echo "  synth            - Synthesize HDL (Verilog -> JSON)"
	@echo "  pnr              - Place and route (JSON -> ASC) - heap placer, seed 1"
	@echo "  pnr-sa           - Place and route with SA placer + ignore-loops"
	@echo "  pnr-sa-seeds     - Try SA placer with seeds 1-20 (most aggressive)"
	@echo "  pnr-seeds        - Try heap placer with seeds 1-20"
	@echo "  bitstream        - Generate bitstream (ASC -> BIN)"
	@echo "  time             - Run timing analysis"
	@echo "  prog             - Program FPGA (Windows only)"
	@echo ""
	@echo "Bootloader Targets:"
	@echo "  bootloader       - Build software bootloader (runs from 0x40000)"
	@echo "  bootloader-clean - Clean bootloader build"
	@echo ""
	@echo "Firmware Targets:"
	@echo "  firmware                  - Build all firmware (led_blink, interactive, button_demo)"
	@echo "  firmware-led-blink        - Build led_blink.hex only"
	@echo "  firmware-interactive      - Build interactive.hex only"
	@echo "  firmware-button-demo      - Build button_demo.hex only"
	@echo "  firmware-clean            - Clean firmware build"
	@echo ""
	@echo "Newlib Targets (C Standard Library for rv32im/ilp32):"
	@echo "  newlib-install            - Auto-fetch, configure, build, install newlib (~30-45 min)"
	@echo "  newlib-fetch              - Clone newlib source from git (if not present)"
	@echo "  newlib-configure          - Configure newlib for rv32im/ilp32 ONLY"
	@echo "  newlib-build              - Build newlib (single target, not multilib)"
	@echo "  newlib-clean              - Clean build artifacts (keep config)"
	@echo "  newlib-distclean          - Remove all newlib files (requires rebuild)"
	@echo ""
	@echo "Building with Newlib:"
	@echo "  cd firmware && make TARGET=printf_test USE_NEWLIB=1 single-target"
	@echo ""
	@echo "Uploader Targets:"
	@echo "  uploader         - Build firmware uploader (Linux)"
	@echo "  uploader-clean   - Clean uploader build"
	@echo ""
	@echo "Simulation Targets:"
	@echo "  sim              - Run main simulation"
	@echo "  sim-interactive  - Test interactive firmware"
	@echo "  sim-crc          - Test CRC32 calculation"
	@echo "  sim-cpu          - Test CPU execution"
	@echo "  sim-r            - Test shell 'r' command"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean            - Remove build artifacts"
	@echo "  distclean        - Remove all generated files"
	@echo ""
	@echo "Important Notes:"
	@echo "  - FPGA programming only works on Windows (WinIceprog.exe)"
	@echo "  - Linux/macOS: Use for HDL build and firmware upload only"
	@echo "  - Firmware upload works on all platforms via UART"
	@echo "  - NextPNR version matters: 0.7 works reliably, 0.9+ may need pnr-sa or pnr-seeds"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make all              # Build everything"
	@echo "  2. make prog             # Program FPGA (Windows)"
	@echo "  3. cd tools/uploader && ./fw_upload -p COM8 ../../firmware/interactive.hex"
	@echo ""
	@echo "If Place-and-Route Fails (nextpnr-0.9+):"
	@echo "  1. Try: make pnr-sa           # SA placer with ignore-loops"
	@echo "  2. Try: make pnr-seeds        # Heap placer, seeds 1-20"
	@echo "  3. Try: make pnr-sa-seeds     # SA placer, seeds 1-20 (slowest, most thorough)"
	@echo "  4. Or use pre-built bitstream in build/ directory (MD5: ac6df943bfc014a1b66dd28e3532c09c)"
	@echo ""
	@echo "Build Statistics:"
	@echo "  - FPGA Utilization: 7595/7680 (98.9%)"
	@echo "  - Max Frequency: 41.79 MHz (target: 12 MHz)"
	@echo "  - SRAM Size: 512 KB"
	@echo "  - Firmware Size: ~2.8 KB"
