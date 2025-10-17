# Olimex iCE40HX8K PicoRV32 Build System
# Main Makefile - User interface

.PHONY: all help clean distclean mrproper menuconfig defconfig generate
.PHONY: bootloader firmware upload-tool test-generators

# Detect number of cores
NPROC := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Toolchain
PREFIX ?= riscv64-unknown-elf-

# Check for required tools
REQUIRED_TOOLS := $(PREFIX)gcc make
OPTIONAL_TOOLS := ninja kconfig-mconf

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
	@echo "Status:"
	@echo "  - Generator scripts: ✓ Ready"
	@echo "  - Kconfig: ✓ Ready"
	@echo "  - Build system: ⚠ TODO"
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
	@echo "Run 'make generate' to create platform files"

savedefconfig:
	@if [ ! -f .config ]; then \
		echo "ERROR: No .config found. Run 'make menuconfig' or 'make defconfig' first."; \
		exit 1; \
	fi
	@echo "Saving current config as defconfig..."
	@cp .config configs/defconfig
	@echo "✓ Saved to configs/defconfig"

# Generate platform files
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

# Build targets (stubs for now)
bootloader: generate
	@echo "TODO: Implement bootloader build"
	@echo "Will build from bootloader/*.c using generated files"

firmware: generate
	@echo "TODO: Implement firmware build"
	@echo "Will build firmware/*.c using generated files"

upload-tool:
	@echo "TODO: Implement upload tool build"
	@echo "Will build tools/upload/fw_upload.c"

# Clean targets
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
