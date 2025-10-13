#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Makefile - Firmware Build System
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#===============================================================================

PREFIX = riscv64-unknown-elf-
CC = $(PREFIX)gcc
AS = $(PREFIX)as
LD = $(PREFIX)ld
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump
SIZE = $(PREFIX)size

# Target firmware (override with TARGET=interactive to build single target)
TARGET ?= led_blink
SOURCES = $(TARGET).c
ASM_SOURCES = start.S

# All firmware targets
FIRMWARE_TARGETS = led_blink interactive button_demo timer_clock

# Compiler flags for RV32I (32 registers with MUL/DIV/barrel shifter)
ARCH = rv32im
ABI = ilp32
CFLAGS = -march=$(ARCH) -mabi=$(ABI) -O2 -g
CFLAGS += -nostartfiles -nostdlib -nodefaultlibs
CFLAGS += -Wall -Wextra
CFLAGS += -ffreestanding -fno-builtin

# Linker flags
LDFLAGS = -T linker.ld -nostdlib -nostartfiles
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -Wl,-Map=$(TARGET).map

# Output files
ELF = $(TARGET).elf
BIN = $(TARGET).bin
HEX = $(TARGET).hex
LST = $(TARGET).lst
MAP = $(TARGET).map

.PHONY: all clean size disasm all-targets

# Build all firmware targets by default
all: all-targets

# Build all three firmware variants
all-targets:
	@echo "========================================="
	@echo "Building all firmware targets..."
	@echo "========================================="
	@for target in $(FIRMWARE_TARGETS); do \
		echo ""; \
		echo "Building $$target..."; \
		$(MAKE) TARGET=$$target single-target || exit 1; \
	done
	@echo ""
	@echo "========================================="
	@echo "All firmware built successfully!"
	@echo "========================================="
	@ls -lh *.hex

# Build single target (used internally by all-targets)
single-target: $(BIN) $(HEX) size

# Link ELF
$(ELF): $(SOURCES) $(ASM_SOURCES) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(ASM_SOURCES) $(SOURCES) -o $@

# Create binary
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@
	@echo "Binary size:"
	@ls -lh $@

# Create hex dump
$(HEX): $(ELF)
	$(OBJCOPY) -O verilog $< $@

# Disassembly listing
$(LST): $(ELF)
	$(OBJDUMP) -D -S $< > $@

# Show memory usage
size: $(ELF)
	@echo "==================================="
	@echo "Memory usage:"
	@echo "==================================="
	$(SIZE) $<
	@echo ""
	@echo "Memory layout (from linker script):"
	@echo "  Code/Data/BSS: 0x00000000 - 0x00065FFF (417,792 bytes, 80%)"
	@echo "  Heap:          0x00066000 - 0x00078FFF ( 77,824 bytes, 15%)"
	@echo "  Stack:         0x00079000 - 0x0007FFFF ( 28,672 bytes,  5%)"
	@echo "  Total:         512 KB"

# Disassemble
disasm: $(LST)
	@cat $(LST)

# Clean build artifacts
clean:
	@echo "Cleaning all firmware build artifacts..."
	@rm -f *.elf *.bin *.hex *.lst *.map
	@echo "✓ Clean complete"

# Help
help:
	@echo "PicoRV32 Firmware Build Targets:"
	@echo "  make all                - Build all firmware targets (led_blink, interactive, button_demo)"
	@echo "  make TARGET=<name>      - Build specific target (e.g., make TARGET=interactive single-target)"
	@echo "  make size               - Show memory usage for current TARGET"
	@echo "  make disasm             - Generate and show disassembly for current TARGET"
	@echo "  make clean              - Remove all build artifacts"
	@echo ""
	@echo "Available firmware targets:"
	@echo "  led_blink               - Simple LED blink demo"
	@echo "  interactive             - Interactive shell firmware"
	@echo "  button_demo             - Button and LED demo"
