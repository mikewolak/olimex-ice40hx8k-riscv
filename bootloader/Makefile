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

# Create hex dump (32-bit words, little-endian for Verilog $readmemh)
$(HEX): $(BIN)
	@echo "@00000000" > $@
	@hexdump -v -e '1/4 "%08x\n"' $(BIN) >> $@
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
	@echo "  Code space:     0x00000000 - 0x0003FFFF (256KB)"
	@echo "  Bootloader ROM: 0x00040000 - 0x00041FFF (8KB)"
	@echo "  Stack:          0x00041F00 - 0x00041FFF (256B)"
	@echo "  Heap/Stack:     0x00042000 - 0x0007FFFF (~248KB)"
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
