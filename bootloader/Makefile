#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform - Bootloader Build System
# Makefile - Bootloader at 0x10000
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

# Source files
SOURCES = bootloader.c
ASM_SOURCES = start.S

# Compiler flags for RV32E (16 registers, no MUL/DIV)
ARCH = rv32e
ABI = ilp32e
CFLAGS = -march=$(ARCH) -mabi=$(ABI) -O2 -g
CFLAGS += -nostartfiles -nostdlib -nodefaultlibs
CFLAGS += -Wall -Wextra
CFLAGS += -ffreestanding -fno-builtin

# Linker flags
LDFLAGS = -T linker.ld -nostdlib -nostartfiles
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -Wl,-Map=bootloader.map

# Output files
ELF = bootloader.elf
BIN = bootloader.bin
HEX = bootloader.hex
LST = bootloader.lst
MAP = bootloader.map

.PHONY: all clean size disasm

# Always generate .lst file
all: $(BIN) $(HEX) $(LST) size

# Link ELF
$(ELF): $(SOURCES) $(ASM_SOURCES) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(ASM_SOURCES) $(SOURCES) -o $@

# Create binary
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@
	@echo "Bootloader binary size:"
	@ls -lh $@

# Create hex dump (for SPRAM initialization)
$(HEX): $(ELF)
	$(OBJCOPY) -O verilog $< $@
	@echo "Bootloader hex file created: $@"

# Disassembly listing (ALWAYS GENERATED)
$(LST): $(ELF)
	$(OBJDUMP) -D -S $< > $@
	@echo "========================================="
	@echo "Disassembly listing: $@"
	@echo "========================================="

# Show memory usage
size: $(ELF)
	@echo "========================================="
	@echo "Bootloader memory usage:"
	@echo "========================================="
	$(SIZE) $<
	@echo ""
	@echo "Memory layout:"
	@echo "  Bootloader ROM: 0x00010000 - 0x00011FFF (8KB)"
	@echo "  Stack:          0x00011F00 - 0x00011FFF (256B)"
	@echo ""

# Disassemble (view listing)
disasm: $(LST)
	@cat $(LST) | less

# Clean build artifacts
clean:
	@echo "Cleaning bootloader build artifacts..."
	@rm -f $(ELF) $(BIN) $(HEX) $(LST) $(MAP)
	@echo "✓ Clean complete"

# Help
help:
	@echo "Bootloader Build Targets:"
	@echo "  make all     - Build bootloader (binary, hex, and listing)"
	@echo "  make size    - Show memory usage"
	@echo "  make disasm  - View disassembly listing"
	@echo "  make clean   - Remove build artifacts"
	@echo ""
	@echo "Output files:"
	@echo "  bootloader.elf - ELF executable"
	@echo "  bootloader.bin - Raw binary"
	@echo "  bootloader.hex - Verilog hex format (for SPRAM init)"
	@echo "  bootloader.lst - Disassembly listing (ALWAYS GENERATED)"
	@echo "  bootloader.map - Linker map"
