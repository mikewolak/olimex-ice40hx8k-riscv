# Olimex iCE40HX8K PicoRV32 Build System
# Main Makefile - User interface

.PHONY: all help clean distclean mrproper menuconfig defconfig

# TODO: Implement full build system
all:
	@echo "========================================="
	@echo "Olimex iCE40HX8K PicoRV32 Build System"
	@echo "========================================="
	@echo "Build system under development"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Implement Kconfig"
	@echo "  2. Implement generator scripts"
	@echo "  3. Implement Ninja build generator"
	@echo ""

help:
	@echo "Olimex iCE40HX8K PicoRV32 Build System"
	@echo ""
	@echo "Configuration:"
	@echo "  make menuconfig      - Configure system"
	@echo "  make defconfig       - Load default config"
	@echo ""
	@echo "Building:"
	@echo "  make                 - Build everything"
	@echo ""
	@echo "Clean:"
	@echo "  make clean           - Remove build artifacts"
	@echo "  make distclean       - Remove config + artifacts"
	@echo "  make mrproper        - Complete clean (pristine)"

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

menuconfig:
	@echo "Kconfig not yet implemented"

defconfig:
	@echo "defconfig not yet implemented"
