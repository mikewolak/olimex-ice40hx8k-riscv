# Olimex iCE40HX8K PicoRV32 Build System
# Main Makefile - User interface

.PHONY: all help clean distclean mrproper menuconfig defconfig generate
.PHONY: bootloader firmware upload-tool test-generators
.PHONY: toolchain-riscv toolchain-fpga toolchain-download toolchain-check
.PHONY: fetch-picorv32 build-newlib check-newlib
.PHONY: fw-led-blink fw-timer-clock fw-hexedit fw-heap-test fw-algo-test
.PHONY: fw-mandelbrot-fixed fw-mandelbrot-float firmware-all
.PHONY: bitstream synth pnr pnr-sa pack timing

# Detect number of cores
NPROC := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
export NPROC

# Toolchain detection
ifneq (,$(wildcard build/toolchain/bin/riscv64-unknown-elf-gcc))
    PREFIX := build/toolchain/bin/riscv64-unknown-elf-
else ifneq (,$(wildcard build/toolchain/bin/riscv32-unknown-elf-gcc))
    PREFIX := build/toolchain/bin/riscv32-unknown-elf-
else
    PREFIX := riscv64-unknown-elf-
endif

all: help

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

toolchain-check:
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

# Build all firmware targets
firmware-all: fw-led-blink fw-timer-clock fw-hexedit fw-heap-test fw-algo-test fw-mandelbrot-fixed fw-mandelbrot-float
	@echo ""
	@echo "========================================="
	@echo "✓ All firmware targets built"
	@echo "========================================="
	@echo ""
	@echo "Built firmware:"
	@ls -lh firmware/*.hex 2>/dev/null || echo "No firmware built yet"

upload-tool:
	@echo "TODO: Implement upload tool build"
	@echo "Will build tools/upload/fw_upload.c"

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
synth: bootloader
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
	yosys -p "synth_ice40 -top ice40_picorv32_top -json build/ice40_picorv32.json $$SYNTH_OPTS" hdl/*.v
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
	nextpnr-ice40 --hx8k --package ct256 \
		--json build/ice40_picorv32.json \
		--pcf "$$PCF_FILE" \
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
		--asc build/ice40_picorv32.asc \
		--placer sa --ignore-loops
	@echo ""
	@echo "✓ Place and route complete: build/ice40_picorv32.asc"

# Pack Bitstream: ASC -> BIN
pack: pnr
	@echo "========================================="
	@echo "Pack Bitstream: ASC -> BIN"
	@echo "========================================="
	icepack build/ice40_picorv32.asc build/ice40_picorv32.bin
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
# Clean targets
# ============================================================================

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build/ deploy/
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
