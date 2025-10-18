# Olimex iCE40HX8K PicoRV32 Build System
# Main Makefile - User interface

.PHONY: all help clean distclean mrproper menuconfig defconfig generate
.PHONY: bootloader firmware upload-tool test-generators
.PHONY: toolchain-riscv toolchain-fpga toolchain-download toolchain-check verify-platform
.PHONY: fetch-picorv32 build-newlib check-newlib
.PHONY: fw-led-blink fw-timer-clock fw-hexedit fw-heap-test fw-algo-test
.PHONY: fw-mandelbrot-fixed fw-mandelbrot-float firmware-all firmware-bare firmware-newlib newlib-if-needed
.PHONY: bitstream synth pnr pnr-sa pack timing artifacts
.PHONY: ninja ninja-clean

# Detect number of cores
NPROC := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
export NPROC

# Toolchain detection and PATH setup
ifneq (,$(wildcard build/toolchain/bin/riscv64-unknown-elf-gcc))
    PREFIX := build/toolchain/bin/riscv64-unknown-elf-
else ifneq (,$(wildcard build/toolchain/bin/riscv32-unknown-elf-gcc))
    PREFIX := build/toolchain/bin/riscv32-unknown-elf-
else
    PREFIX := riscv64-unknown-elf-
endif

# Toolchain paths will be set explicitly in each target that needs them

# Auto-select Ninja for multi-core systems (>2 CPUs)
all:
	@if [ $(NPROC) -gt 2 ] && command -v ninja >/dev/null 2>&1; then \
		echo "=========================================" ; \
		echo "Detected $(NPROC) CPU cores - using Ninja for parallel build" ; \
		echo "=========================================" ; \
		echo "" ; \
		$(MAKE) ninja ; \
	else \
		$(MAKE) all-sequential ; \
	fi

all-sequential: toolchain-check bootloader firmware-bare newlib-if-needed firmware-newlib bitstream upload-tool artifacts
	@echo ""
	@echo "========================================="
	@echo "✓ Build Complete!"
	@echo "========================================="
	@echo ""
	@echo "Build artifacts collected in artifacts/ directory"
	@echo "See artifacts/build-report.txt for detailed build information"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Program FPGA:    iceprog artifacts/gateware/ice40_picorv32.bin"
	@echo "  2. Upload firmware: artifacts/host/fw_upload -p /dev/ttyUSB0 artifacts/firmware/<name>.bin"
	@echo ""

help:
	@echo "========================================="
	@echo "Olimex iCE40HX8K PicoRV32 Build System"
	@echo "========================================="
	@echo ""
	@echo "Configuration:"
	@echo "  make menuconfig      - Configure system (requires kconfig-mconf)"
	@echo "  make defconfig       - Load default config"
	@echo "  make savedefconfig   - Save current config as defconfig"
	@echo ""
	@echo "Toolchain Management:"
	@echo "  make toolchain-check    - Check for required tools"
	@echo "  make toolchain-download - Download pre-built toolchains (~5-10 min)"
	@echo "  make toolchain-riscv    - Build RISC-V GCC from source (~1-2 hours)"
	@echo "  make toolchain-fpga     - Build Yosys/NextPNR/IceStorm (~30-45 min)"
	@echo "  make fetch-picorv32     - Download PicoRV32 core"
	@echo "  make build-newlib       - Build newlib C library (~30-45 min)"
	@echo "  make check-newlib       - Check if newlib is installed"
	@echo ""
	@echo "Code Generation:"
	@echo "  make generate        - Generate platform files from .config"
	@echo "  make test-generators - Test generator scripts"
	@echo ""
	@echo "Building:"
	@echo "  make bootloader           - Build bootloader"
	@echo "  make firmware-all         - Build all firmware targets"
	@echo "  make bitstream            - Build FPGA bitstream (synth + pnr + pack)"
	@echo "  make synth                - Synthesis only (Verilog -> JSON)"
	@echo "  make pnr                  - Place and route (JSON -> ASC)"
	@echo "  make pnr-sa               - Place and route with SA placer"
	@echo "  make pack                 - Pack bitstream (ASC -> BIN)"
	@echo "  make timing               - Timing analysis"
	@echo "  make upload-tool          - Build firmware uploader"
	@echo ""
	@echo "Firmware Targets (bare metal):"
	@echo "  make fw-led-blink         - LED blink demo"
	@echo "  make fw-timer-clock       - Timer clock demo"
	@echo ""
	@echo "Firmware Targets (newlib):"
	@echo "  make fw-hexedit           - Hex editor with file upload"
	@echo "  make fw-heap-test         - Heap allocation test"
	@echo "  make fw-algo-test         - Algorithm test suite"
	@echo "  make fw-mandelbrot-fixed  - Mandelbrot (fixed point)"
	@echo "  make fw-mandelbrot-float  - Mandelbrot (floating point)"
	@echo ""
	@echo "Parallel Build (Ninja):"
	@echo "  make ninja           - Build with Ninja (auto-installs if needed)"
	@echo "  make ninja-clean     - Clean Ninja build files"
	@echo ""
	@echo "Clean:"
	@echo "  make clean           - Remove build artifacts"
	@echo "  make distclean       - Remove config + artifacts"
	@echo "  make mrproper        - Complete clean (pristine)"
	@echo ""
	@echo "Quick Start (Fresh Machine):"
	@echo "  1. make defconfig"
	@echo "  2. make toolchain-download  (or toolchain-riscv + toolchain-fpga)"
	@echo "  3. make generate"
	@echo "  4. make  (when build system is complete)"
	@echo ""

# Configuration targets
menuconfig:
	@if ! command -v kconfig-mconf >/dev/null 2>&1; then \
		echo "ERROR: kconfig-mconf not found"; \
		echo "Install with: sudo apt install kconfig-frontends"; \
		exit 1; \
	fi
	@kconfig-mconf Kconfig

defconfig:
	@echo "Loading default configuration..."
	@cp configs/defconfig .config
	@echo "✓ Loaded configs/defconfig"
	@echo ""
	@echo "Next steps:"
	@echo "  1. make toolchain-check     # Check if tools are installed"
	@echo "  2. make toolchain-download  # Or build from source"
	@echo "  3. make generate            # Create platform files"

savedefconfig:
	@if [ ! -f .config ]; then \
		echo "ERROR: No .config found. Run 'make menuconfig' or 'make defconfig' first."; \
		exit 1; \
	fi
	@echo "Saving current config as defconfig..."
	@cp .config configs/defconfig
	@echo "✓ Saved to configs/defconfig"

# ============================================================================
# Toolchain Management
# ============================================================================

verify-platform:
	@if [ -f scripts/verify-platform.sh ]; then \
		chmod +x scripts/verify-platform.sh; \
		bash scripts/verify-platform.sh; \
	else \
		echo "⚠ Warning: scripts/verify-platform.sh not found, skipping platform verification"; \
	fi

toolchain-check: verify-platform
	@bash scripts/check-tool-versions.sh || $(MAKE) toolchain-download
	@echo "========================================="
	@echo "Checking for required tools"
	@echo "========================================="
	@echo ""
	@echo "RISC-V Toolchain:"
	@if command -v $(PREFIX)gcc >/dev/null 2>&1; then \
		$(PREFIX)gcc --version | head -1; \
		echo "✓ Found: $(PREFIX)gcc"; \
	else \
		echo "✗ Not found: $(PREFIX)gcc"; \
		echo "  Run: make toolchain-download (fast)"; \
		echo "   or: make toolchain-riscv (build from source)"; \
	fi
	@echo ""
	@echo "FPGA Tools:"
	@if command -v yosys >/dev/null 2>&1; then \
		yosys -V | head -1; \
		echo "✓ Found: yosys"; \
	else \
		echo "✗ Not found: yosys"; \
		echo "  Run: make toolchain-download (fast)"; \
		echo "   or: make toolchain-fpga (build from source)"; \
	fi
	@if command -v nextpnr-ice40 >/dev/null 2>&1; then \
		nextpnr-ice40 --version 2>&1 | head -1; \
		echo "✓ Found: nextpnr-ice40"; \
	else \
		echo "✗ Not found: nextpnr-ice40"; \
	fi
	@if command -v icepack >/dev/null 2>&1; then \
		echo "✓ Found: icepack"; \
	else \
		echo "✗ Not found: icepack"; \
	fi

toolchain-download:
	@echo "Downloading pre-built toolchains..."
	@./scripts/download_prebuilt_tools.sh

toolchain-riscv: .config
	@echo "Building RISC-V toolchain from source..."
	@./scripts/build_riscv_toolchain.sh

toolchain-fpga:
	@echo "Building FPGA tools from source..."
	@./scripts/build_fpga_tools.sh

# Auto-install FPGA tools if not present
ensure-fpga-tools:
	@if [ ! -f downloads/oss-cad-suite/bin/yosys ] || \
	    [ ! -f downloads/oss-cad-suite/bin/nextpnr-ice40 ] || \
	    [ ! -f downloads/oss-cad-suite/bin/icepack ]; then \
		echo "========================================="; \
		echo "FPGA tools not found - downloading..."; \
		echo "========================================="; \
		$(MAKE) toolchain-download; \
	fi

fetch-picorv32: .config
	@./scripts/fetch_picorv32.sh

build-newlib: .config
	@if [ ! -f .config ]; then \
		echo "ERROR: No .config found. Run 'make defconfig' first."; \
		exit 1; \
	fi
	@. ./.config && \
	if [ "$$CONFIG_BUILD_NEWLIB" != "y" ]; then \
		echo "ERROR: Newlib build not enabled in configuration"; \
		echo "Run 'make menuconfig' and enable 'Build newlib C library'"; \
		exit 1; \
	fi
	@echo "Building newlib C library..."
	@./scripts/build_newlib.sh

check-newlib:
	@if [ -d build/sysroot ]; then \
		echo "✓ Newlib installed at build/sysroot"; \
		echo ""; \
		echo "Libraries:"; \
		find build/sysroot -name "*.a" | head -5; \
	else \
		echo "✗ Newlib not found"; \
		echo "Run: make build-newlib"; \
	fi

# ============================================================================
# Code Generation
# ============================================================================

generate: .config
	@./scripts/generate_all.sh

test-generators: defconfig
	@echo "========================================="
	@echo "Testing generator scripts"
	@echo "========================================="
	@./scripts/generate_all.sh
	@echo ""
	@echo "Generated files:"
	@ls -lh build/generated/
	@echo ""
	@echo "Preview of generated files:"
	@echo ""
	@echo "--- start.S (first 20 lines) ---"
	@head -20 build/generated/start.S
	@echo ""
	@echo "--- linker.ld (memory sections) ---"
	@grep -A 5 "MEMORY" build/generated/linker.ld
	@echo ""
	@echo "--- platform.h (defines) ---"
	@grep "#define" build/generated/platform.h | head -15
	@echo ""
	@echo "✓ Generator scripts working correctly"

# ============================================================================
# Build Targets
# ============================================================================

# Bootloader (required before bitstream - embedded in BRAM)
bootloader: generate
	@echo "========================================="
	@echo "Building Bootloader"
	@echo "========================================="
	@$(MAKE) -C bootloader
	@echo ""
	@echo "✓ Bootloader built: bootloader/bootloader.hex"
	@echo "  (Embedded in BRAM during bitstream synthesis)"

# Bare metal firmware targets (no newlib)
firmware-bare: fw-led-blink fw-timer-clock

fw-led-blink: generate
	@$(MAKE) -C firmware TARGET=led_blink USE_NEWLIB=0 single-target

fw-timer-clock: generate
	@$(MAKE) -C firmware TARGET=timer_clock USE_NEWLIB=0 single-target

# Newlib firmware targets (require newlib)
fw-hexedit: generate check-newlib
	@$(MAKE) -C firmware TARGET=hexedit USE_NEWLIB=1 single-target

fw-heap-test: generate check-newlib
	@$(MAKE) -C firmware TARGET=heap_test USE_NEWLIB=1 single-target

fw-algo-test: generate check-newlib
	@$(MAKE) -C firmware TARGET=algo_test USE_NEWLIB=1 single-target

fw-mandelbrot-fixed: generate check-newlib
	@$(MAKE) -C firmware TARGET=mandelbrot_fixed USE_NEWLIB=1 single-target

fw-mandelbrot-float: generate check-newlib
	@$(MAKE) -C firmware TARGET=mandelbrot_float USE_NEWLIB=1 single-target

# Build newlib firmware (conditional on newlib being installed)
firmware-newlib: fw-hexedit fw-heap-test fw-algo-test fw-mandelbrot-fixed fw-mandelbrot-float

# Check and build newlib if needed
newlib-if-needed:
	@. ./.config && \
	if [ "$$CONFIG_BUILD_NEWLIB" = "y" ]; then \
		if [ ! -d build/sysroot/riscv64-unknown-elf/include ]; then \
			echo "Newlib not found, building..."; \
			$(MAKE) build-newlib; \
		fi; \
	fi

# Build all firmware targets
firmware-all: firmware-bare firmware-newlib
	@echo ""
	@echo "========================================="
	@echo "✓ All firmware targets built"
	@echo "========================================="
	@echo ""
	@echo "Built firmware:"
	@ls -lh firmware/*.hex 2>/dev/null || echo "No firmware built yet"

upload-tool:
	@echo "========================================="
	@echo "Building Firmware Upload Tool"
	@echo "========================================="
	@$(MAKE) -C tools/uploader
	@echo ""
	@echo "✓ Upload tool built: tools/uploader/fw_upload"

# ============================================================================
# HDL Synthesis and Bitstream Generation
# ============================================================================

bitstream: bootloader synth pnr pack
	@echo ""
	@echo "========================================="
	@echo "✓ Bitstream generation complete"
	@echo "========================================="
	@echo "Bitstream: build/ice40_picorv32.bin"
	@ls -lh build/ice40_picorv32.bin
	@echo ""
	@echo "To program FPGA:"
	@echo "  iceprog build/ice40_picorv32.bin"

# Synthesis: Verilog -> JSON (requires bootloader.hex)
synth: ensure-fpga-tools bootloader
	@echo "========================================="
	@echo "Synthesis: Verilog -> JSON"
	@echo "========================================="
	@. ./.config && \
	SYNTH_OPTS=""; \
	if [ "$$CONFIG_SYNTH_ABC9" = "y" ]; then \
		SYNTH_OPTS="-abc9"; \
		echo "ABC9:    enabled"; \
	else \
		echo "ABC9:    disabled"; \
	fi; \
	echo "Tool:    Yosys"; \
	echo "Target:  iCE40HX8K"; \
	echo ""; \
	YOSYS_CMD="yosys"; \
	if [ -f $(CURDIR)/downloads/oss-cad-suite/bin/yosys ]; then \
		YOSYS_CMD="$(CURDIR)/downloads/oss-cad-suite/bin/yosys"; \
		echo "Using: $$YOSYS_CMD"; \
	fi; \
	$$YOSYS_CMD -p "synth_ice40 -top ice40_picorv32_top -json build/ice40_picorv32.json $$SYNTH_OPTS" \
		hdl/picorv32.v \
		hdl/uart.v \
		hdl/circular_buffer.v \
		hdl/crc32_gen.v \
		hdl/sram_driver_new.v \
		hdl/sram_proc_new.v \
		hdl/firmware_loader.v \
		hdl/bootloader_rom.v \
		hdl/mem_controller.v \
		hdl/mmio_peripherals.v \
		hdl/timer_peripheral.v \
		hdl/ice40_picorv32_top.v
	@echo ""
	@echo "✓ Synthesis complete: build/ice40_picorv32.json"

# Place and Route: JSON -> ASC
pnr: synth
	@echo "========================================="
	@echo "Place and Route: JSON -> ASC"
	@echo "========================================="
	@. ./.config && \
	PCF_FILE="$$CONFIG_PCF_FILE"; \
	if [ -z "$$PCF_FILE" ]; then \
		PCF_FILE="hdl/ice40_picorv32.pcf"; \
	fi; \
	echo "Tool:    NextPNR-iCE40"; \
	echo "Device:  hx8k"; \
	echo "Package: ct256"; \
	echo "PCF:     $$PCF_FILE"; \
	echo "Placer:  heap --seed 1"; \
	echo ""; \
	NEXTPNR_CMD="nextpnr-ice40"; \
	if [ -f $(CURDIR)/downloads/oss-cad-suite/bin/nextpnr-ice40 ]; then \
		NEXTPNR_CMD="$(CURDIR)/downloads/oss-cad-suite/bin/nextpnr-ice40"; \
		echo "Using: $$NEXTPNR_CMD"; \
	fi; \
	$$NEXTPNR_CMD --hx8k --package ct256 \
		--json build/ice40_picorv32.json \
		--pcf "$$PCF_FILE" \
		--sdc hdl/ice40_picorv32.sdc \
		--asc build/ice40_picorv32.asc \
		--placer heap --seed 1
	@echo ""
	@echo "✓ Place and route complete: build/ice40_picorv32.asc"

# Alternative: Simulated Annealing placer (better for tight designs)
pnr-sa: synth
	@echo "========================================="
	@echo "Place and Route: JSON -> ASC (SA)"
	@echo "========================================="
	@. ./.config && \
	PCF_FILE="$$CONFIG_PCF_FILE"; \
	if [ -z "$$PCF_FILE" ]; then \
		PCF_FILE="hdl/ice40_picorv32.pcf"; \
	fi; \
	echo "Tool:    NextPNR-iCE40"; \
	echo "Device:  hx8k"; \
	echo "Package: ct256"; \
	echo "PCF:     $$PCF_FILE"; \
	echo "Placer:  SA (Simulated Annealing)"; \
	echo ""; \
	nextpnr-ice40 --hx8k --package ct256 \
		--json build/ice40_picorv32.json \
		--pcf "$$PCF_FILE" \
		--sdc hdl/ice40_picorv32.sdc \
		--asc build/ice40_picorv32.asc \
		--placer sa --ignore-loops
	@echo ""
	@echo "✓ Place and route complete: build/ice40_picorv32.asc"

# Alternative: Try multiple seeds (for tight designs at ~90% utilization)
pnr-seeds: synth
	@echo "========================================="
	@echo "Place and Route: Trying Multiple Seeds"
	@echo "========================================="
	@. ./.config && \
	PCF_FILE="$$CONFIG_PCF_FILE"; \
	if [ -z "$$PCF_FILE" ]; then \
		PCF_FILE="hdl/ice40_picorv32.pcf"; \
	fi; \
	echo "Tool:    NextPNR-iCE40"; \
	echo "Device:  hx8k"; \
	echo "Package: ct256"; \
	echo "PCF:     $$PCF_FILE"; \
	echo "Useful for nextpnr-0.9+ with 90%+ utilization"; \
	echo ""; \
	NEXTPNR_CMD="nextpnr-ice40"; \
	if [ -f $(CURDIR)/downloads/oss-cad-suite/bin/nextpnr-ice40 ]; then \
		NEXTPNR_CMD="$(CURDIR)/downloads/oss-cad-suite/bin/nextpnr-ice40"; \
		echo "Using: $$NEXTPNR_CMD"; \
	fi; \
	for seed in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
		echo "Trying seed $$seed..."; \
		if $$NEXTPNR_CMD --hx8k --package ct256 \
		   --json build/ice40_picorv32.json --pcf "$$PCF_FILE" \
		   --sdc hdl/ice40_picorv32.sdc \
		   --asc build/ice40_picorv32.asc --placer heap --seed $$seed; then \
			echo "✓ Success with seed $$seed!"; \
			break; \
		else \
			echo "✗ Seed $$seed failed, trying next..."; \
		fi; \
	done
	@if [ -f build/ice40_picorv32.asc ]; then \
		echo ""; \
		echo "✓ Place and route complete: build/ice40_picorv32.asc"; \
	else \
		echo ""; \
		echo "✗ All seeds failed - design may not fit"; \
		exit 1; \
	fi

# Pack Bitstream: ASC -> BIN
pack: pnr
	@echo "========================================="
	@echo "Pack Bitstream: ASC -> BIN"
	@echo "========================================="
	@echo "Tool:    icepack"; \
	ICEPACK_CMD="icepack"; \
	if [ -f $(CURDIR)/downloads/oss-cad-suite/bin/icepack ]; then \
		ICEPACK_CMD="$(CURDIR)/downloads/oss-cad-suite/bin/icepack"; \
		echo "Using: $$ICEPACK_CMD"; \
	fi; \
	$$ICEPACK_CMD build/ice40_picorv32.asc build/ice40_picorv32.bin
	@echo "✓ Bitstream packed: build/ice40_picorv32.bin"

# Timing analysis
timing: pnr
	@echo "========================================="
	@echo "Timing Analysis"
	@echo "========================================="
	icetime -d hx8k -mtr build/timing_report.txt build/ice40_picorv32.asc
	@echo ""
	@echo "Timing report:"
	@grep -A5 "Max frequency" build/timing_report.txt || cat build/timing_report.txt

# ============================================================================
# Artifacts Collection
# ============================================================================

artifacts:
	@echo "========================================="
	@echo "Collecting Build Artifacts"
	@echo "========================================="
	@echo ""
	@# Create directory structure
	@rm -rf artifacts
	@mkdir -p artifacts/host artifacts/gateware artifacts/firmware
	@echo "✓ Created artifacts directory structure"
	@echo ""
	@# Copy host tools
	@if [ -f tools/uploader/fw_upload ]; then \
		cp tools/uploader/fw_upload artifacts/host/; \
		echo "✓ Copied fw_upload to artifacts/host/"; \
	else \
		echo "⚠ fw_upload not found"; \
	fi
	@echo ""
	@# Copy gateware
	@if [ -f build/ice40_picorv32.bin ]; then \
		cp build/ice40_picorv32.bin artifacts/gateware/; \
		echo "✓ Copied bitstream to artifacts/gateware/"; \
	else \
		echo "⚠ Bitstream not found"; \
	fi
	@echo ""
	@# Copy firmware binaries
	@if [ -n "$$(find firmware -name '*.bin' 2>/dev/null)" ]; then \
		find firmware -name "*.bin" -exec cp {} artifacts/firmware/ \;; \
		echo "✓ Copied firmware binaries to artifacts/firmware/"; \
		find artifacts/firmware/ -name "*.bin" -exec basename {} \; | sort | sed 's/^/  - /'; \
	else \
		echo "⚠ No firmware binaries found"; \
	fi
	@echo ""
	@# Generate build report
	@echo "Generating build report..."
	@echo "==========================================" > artifacts/build-report.txt
	@echo "Olimex iCE40HX8K PicoRV32 Build Report" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@echo "Build Timestamp: $$(date)" >> artifacts/build-report.txt
	@echo "Build Host: $$(hostname)" >> artifacts/build-report.txt
	@echo "Build Platform: $$(uname -s) $$(uname -r)" >> artifacts/build-report.txt
	@echo "Architecture: $$(uname -m)" >> artifacts/build-report.txt
	@echo "CPU Cores: $$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 'Unknown')" >> artifacts/build-report.txt
	@echo "Total RAM: $$(free -h 2>/dev/null | awk '/^Mem:/ {print $$2}' || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1fG", $$1/1024/1024/1024}' || echo 'Unknown')" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "⚠️  NOT FOR COMMERCIAL USE ⚠️" >> artifacts/build-report.txt
	@echo "EDUCATIONAL AND RESEARCH PURPOSES ONLY" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@echo "Copyright (c) October 2025 Michael Wolak" >> artifacts/build-report.txt
	@echo "Email: mikewolak@gmail.com, mike@epromfoundry.com" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "Tool Versions" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@# Detect which Yosys to use
	@if [ -f downloads/oss-cad-suite/bin/yosys ]; then \
		echo "Yosys: $$(downloads/oss-cad-suite/bin/yosys --version 2>&1 | head -1)" >> artifacts/build-report.txt; \
	elif command -v yosys >/dev/null 2>&1; then \
		echo "Yosys: $$(yosys --version 2>&1 | head -1)" >> artifacts/build-report.txt; \
	else \
		echo "Yosys: Not found" >> artifacts/build-report.txt; \
	fi
	@# Detect which NextPNR to use
	@if [ -f downloads/oss-cad-suite/bin/nextpnr-ice40 ]; then \
		echo "NextPNR: $$(downloads/oss-cad-suite/bin/nextpnr-ice40 --version 2>&1 | head -1)" >> artifacts/build-report.txt; \
	elif command -v nextpnr-ice40 >/dev/null 2>&1; then \
		echo "NextPNR: $$(nextpnr-ice40 --version 2>&1 | head -1)" >> artifacts/build-report.txt; \
	else \
		echo "NextPNR: Not found" >> artifacts/build-report.txt; \
	fi
	@# Detect which icetime to use (icetime doesn't have --version, just check if it exists)
	@if [ -f downloads/oss-cad-suite/bin/icetime ]; then \
		echo "IceTime: Found (from oss-cad-suite)" >> artifacts/build-report.txt; \
	elif command -v icetime >/dev/null 2>&1; then \
		echo "IceTime: Found (system)" >> artifacts/build-report.txt; \
	else \
		echo "IceTime: Not found" >> artifacts/build-report.txt; \
	fi
	@# RISC-V GCC version
	@if [ -f build/toolchain/bin/riscv64-unknown-elf-gcc ]; then \
		echo "RISC-V GCC: $$(build/toolchain/bin/riscv64-unknown-elf-gcc --version 2>&1 | head -1)" >> artifacts/build-report.txt; \
	elif [ -f build/toolchain/bin/riscv32-unknown-elf-gcc ]; then \
		echo "RISC-V GCC: $$(build/toolchain/bin/riscv32-unknown-elf-gcc --version 2>&1 | head -1)" >> artifacts/build-report.txt; \
	elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then \
		echo "RISC-V GCC: $$(riscv64-unknown-elf-gcc --version 2>&1 | head -1)" >> artifacts/build-report.txt; \
	else \
		echo "RISC-V GCC: Not found" >> artifacts/build-report.txt; \
	fi
	@echo "" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "FPGA Utilization" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@if [ -f build/ice40_picorv32.asc ]; then \
		if [ -f downloads/oss-cad-suite/bin/icebox_stat ]; then \
			downloads/oss-cad-suite/bin/icebox_stat build/ice40_picorv32.asc >> artifacts/build-report.txt 2>&1; \
		elif command -v icebox_stat >/dev/null 2>&1; then \
			icebox_stat build/ice40_picorv32.asc >> artifacts/build-report.txt 2>&1; \
		else \
			echo "Utilization data not available (icebox_stat not found)" >> artifacts/build-report.txt; \
		fi; \
	else \
		echo "Utilization data not available (build/ice40_picorv32.asc not found)" >> artifacts/build-report.txt; \
	fi
	@echo "" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "Timing Analysis" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@if [ -f build/timing_report.txt ]; then \
		cat build/timing_report.txt >> artifacts/build-report.txt; \
	else \
		echo "Timing report not available" >> artifacts/build-report.txt; \
	fi
	@echo "" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "Build Artifacts Tree" >> artifacts/build-report.txt
	@echo "==========================================" >> artifacts/build-report.txt
	@echo "" >> artifacts/build-report.txt
	@if command -v tree >/dev/null 2>&1; then \
		tree artifacts >> artifacts/build-report.txt; \
	else \
		find artifacts -type f -o -type d | sort | sed 's|^artifacts|.|' >> artifacts/build-report.txt; \
	fi
	@echo "" >> artifacts/build-report.txt
	@echo "✓ Build report generated: artifacts/build-report.txt"
	@echo ""
	@# Create tar.gz archive with version and date
	@GIT_TAG=$$(git describe --tags --always 2>/dev/null || echo "0.1-initial"); \
	BUILD_DATE=$$(date +%Y%m%d-%H%M%S); \
	ARCHIVE_NAME="olimex-ice40hx8k-picorv32-$${GIT_TAG}-$${BUILD_DATE}"; \
	echo "Creating release archive: $${ARCHIVE_NAME}.tar.gz"; \
	tar -czf artifacts/$${ARCHIVE_NAME}.tar.gz -C artifacts host gateware firmware build-report.txt 2>/dev/null || tar -czf artifacts/$${ARCHIVE_NAME}.tar.gz artifacts/host artifacts/gateware artifacts/firmware artifacts/build-report.txt; \
	echo "✓ Release archive created: artifacts/$${ARCHIVE_NAME}.tar.gz"; \
	ls -lh artifacts/$${ARCHIVE_NAME}.tar.gz
	@echo ""
	@echo "========================================="
	@echo "✓ Artifacts Collection Complete"
	@echo "========================================="

# ============================================================================
# Ninja Parallel Build System
# ============================================================================

ninja: generate
	@bash scripts/ninja-build.sh

ninja-clean:
	@echo "Cleaning Ninja build files..."
	@rm -f build.ninja .ninja_*
	@echo "✓ Ninja files cleaned"

# ============================================================================
# Clean targets
# ============================================================================

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build/ deploy/ artifacts/
	@echo "✓ Clean complete"

distclean: clean
	@echo "Cleaning configuration..."
	@rm -f .config .config.old build.ninja .ninja_*
	@echo "✓ Configuration cleaned"

mrproper: distclean
	@echo "Mr. Proper: Removing all downloaded dependencies..."
	@rm -rf downloads/
	@echo "✓ Repository pristine"

# Check for .config
.config:
	@echo "ERROR: No .config found"
	@echo "Run 'make defconfig' or 'make menuconfig' first"
	@exit 1
