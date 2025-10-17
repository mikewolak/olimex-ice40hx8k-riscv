# Olimex iCE40HX8K PicoRV32 Build System
# Main Makefile - User interface

.PHONY: all help clean distclean mrproper menuconfig defconfig generate
.PHONY: bootloader firmware upload-tool test-generators
.PHONY: toolchain-riscv toolchain-fpga toolchain-download toolchain-check
.PHONY: fetch-picorv32

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
	@echo ""
	@echo "Code Generation:"
	@echo "  make generate        - Generate platform files from .config"
	@echo "  make test-generators - Test generator scripts"
	@echo ""
	@echo "Building (TODO - Not yet implemented):"
	@echo "  make bootloader      - Build bootloader"
	@echo "  make firmware        - Build firmware"
	@echo "  make bitstream       - Build FPGA bitstream"
	@echo "  make upload-tool     - Build firmware uploader"
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
# Build targets (stubs for now)
# ============================================================================

bootloader: generate
	@echo "TODO: Implement bootloader build"
	@echo "Will build from bootloader/*.c using generated files"

firmware: generate
	@echo "TODO: Implement firmware build"
	@echo "Will build firmware/*.c using generated files"

upload-tool:
	@echo "TODO: Implement upload tool build"
	@echo "Will build tools/upload/fw_upload.c"

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
