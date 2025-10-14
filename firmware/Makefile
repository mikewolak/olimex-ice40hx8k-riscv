#===============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Makefile - Firmware Build System with Newlib Support
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#===============================================================================

# Detect host OS and set appropriate toolchain prefix
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    PREFIX = riscv-none-elf-
    $(info Building on macOS - using $(PREFIX) toolchain)
else
    PREFIX = riscv64-unknown-elf-
    $(info Building on $(UNAME_S) - using $(PREFIX) toolchain)
endif

CC = $(PREFIX)gcc
AS = $(PREFIX)as
LD = $(PREFIX)ld
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump
SIZE = $(PREFIX)size

# Newlib paths (installed in system directory)
NEWLIB_INSTALL = ../system/riscv-newlib
SYSCALLS_SRC = ../lib/syscalls.c
SYSCALLS_OBJ = syscalls.o

# Target firmware (override with TARGET=name)
TARGET ?= led_blink
SOURCES = $(TARGET).c
ASM_SOURCES = start.S

# Use newlib flag (set USE_NEWLIB=1 to link with newlib)
USE_NEWLIB ?= 0

# All firmware targets
FIRMWARE_TARGETS = led_blink interactive button_demo timer_clock
NEWLIB_TARGETS = printf_test uart_echo_test heap_test math_test algo_test

# Compiler flags for RV32IM
ARCH = rv32im
ABI = ilp32
CFLAGS = -march=$(ARCH) -mabi=$(ABI) -O2 -g
CFLAGS += -Wall -Wextra
CFLAGS += -ffreestanding -fno-builtin

# Conditional flags based on newlib usage
ifeq ($(USE_NEWLIB),1)
    # With newlib - STATICALLY LINKED for embedded system
    # Use our own start.S instead of crt0.o
    CFLAGS += -nostartfiles
    CFLAGS += -isystem $(NEWLIB_INSTALL)/riscv64-unknown-elf/include
    LDFLAGS = -T linker.ld -static -nostartfiles
    LDFLAGS += -L$(NEWLIB_INSTALL)/riscv64-unknown-elf/lib
    LDFLAGS += -Wl,--gc-sections
    LDFLAGS += -Wl,-Map=$(TARGET).map
    LIBS = $(SYSCALLS_OBJ) -lc -lm -lgcc
    $(info Building WITH newlib support (STATIC))
else
    # Without newlib - bare metal
    CFLAGS += -nostartfiles -nostdlib -nodefaultlibs
    LDFLAGS = -T linker.ld -nostdlib -nostartfiles
    LDFLAGS += -Wl,--gc-sections
    LDFLAGS += -Wl,-Map=$(TARGET).map
    LIBS = -lgcc
    $(info Building WITHOUT newlib (bare metal))
endif

# Output files
ELF = $(TARGET).elf
BIN = $(TARGET).bin
HEX = $(TARGET).hex
LST = $(TARGET).lst
MAP = $(TARGET).map

.PHONY: all clean size disasm all-targets all-newlib-targets newlib-targets help build-newlib install-newlib

# Default: build all firmware (bare-metal + newlib if available)
all: all-targets all-newlib-targets

# Build all firmware targets
all-targets:
	@echo "========================================="
	@echo "Building all firmware targets..."
	@echo "========================================="
	@for target in $(FIRMWARE_TARGETS); do \
		echo ""; \
		echo "Building $$target (bare metal)..."; \
		$(MAKE) TARGET=$$target USE_NEWLIB=0 single-target || exit 1; \
	done
	@echo ""
	@echo "========================================="
	@echo "All bare-metal firmware built successfully!"
	@echo "========================================="
	@ls -lh *.bin

# Build newlib targets if newlib is installed
all-newlib-targets:
	@echo ""
	@if [ -d "$(NEWLIB_INSTALL)" ]; then \
		echo "=========================================" ; \
		echo "Building newlib-based targets..." ; \
		echo "=========================================" ; \
		for target in $(NEWLIB_TARGETS); do \
			echo "" ; \
			echo "Building $$target (with newlib)..." ; \
			$(MAKE) TARGET=$$target USE_NEWLIB=1 single-target || exit 1; \
		done ; \
		echo "" ; \
		echo "=========================================" ; \
		echo "All newlib targets built successfully!" ; \
		echo "=========================================" ; \
		ls -lh printf_test.bin 2>/dev/null || true ; \
	else \
		echo "=========================================" ; \
		echo "Newlib not installed - skipping newlib targets" ; \
		echo "Run 'make newlib-install' from top-level to enable" ; \
		echo "=========================================" ; \
	fi

# Build all newlib-based targets
newlib-targets: check-newlib
	@echo "========================================="
	@echo "Building newlib-based targets..."
	@echo "========================================="
	@for target in $(NEWLIB_TARGETS); do \
		echo ""; \
		echo "Building $$target (with newlib)..."; \
		$(MAKE) TARGET=$$target USE_NEWLIB=1 single-target || exit 1; \
	done
	@echo ""
	@echo "========================================="
	@echo "All newlib targets built successfully!"
	@echo "========================================="
	@ls -lh printf_test.bin

# Build single target
single-target: $(BIN) $(LST) size

# Compile syscalls (needed for newlib)
$(SYSCALLS_OBJ): ../lib/syscalls.c
	$(CC) $(CFLAGS) -c $< -o $@

# Link ELF
$(ELF): $(SOURCES) $(ASM_SOURCES) linker.ld
ifeq ($(USE_NEWLIB),1)
	$(MAKE) $(SYSCALLS_OBJ)
	$(CC) $(CFLAGS) $(LDFLAGS) $(ASM_SOURCES) $(SOURCES) $(LIBS) -o $@
else
	$(CC) $(CFLAGS) $(LDFLAGS) $(ASM_SOURCES) $(SOURCES) $(LIBS) -o $@
endif

# Create binary
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@
	@echo "Binary size:"
	@ls -lh $@

# Create hex dump
$(HEX): $(ELF)
	$(OBJCOPY) -O verilog $< $@

# Disassembly listing (ALWAYS GENERATED)
$(LST): $(ELF)
	$(OBJDUMP) -D -S $< > $@
	@echo "Generated disassembly: $@"

# Show memory usage
size: $(ELF)
	@echo "===================================="
	@echo "Memory usage:"
	@echo "===================================="
	$(SIZE) $<
	@echo ""
	@echo "Memory layout (from linker script):"
	@echo "  Code/Data/BSS: 0x00000000 - 0x0003FFFF (256KB)"
	@echo "  Heap:          0x00042000 - 0x00080000 (248KB)"
	@echo "  Stack:         Grows down from 0x80000"

# Disassemble
disasm: $(LST)
	@cat $(LST)

# Check if newlib is installed
check-newlib:
	@if [ ! -d "$(NEWLIB_INSTALL)/riscv64-unknown-elf/lib/rv32im" ]; then \
		echo "ERROR: Newlib not found!"; \
		echo "Please run: make install-newlib"; \
		exit 1; \
	fi
	@echo "✓ Newlib installation found"

# Build newlib from source
build-newlib:
	@echo "========================================="
	@echo "Building newlib (this takes 30+ minutes)"
	@echo "========================================="
	@mkdir -p $(NEWLIB_BUILD)
	@cd $(NEWLIB_BUILD) && \
	if [ ! -f Makefile ]; then \
		$(NEWLIB_SRC)/configure \
			--target=riscv64-unknown-elf \
			--prefix=$(shell cd $(NEWLIB_INSTALL) && pwd) \
			--enable-newlib-nano-malloc \
			--enable-newlib-nano-formatted-io \
			--enable-newlib-io-float \
			--disable-newlib-supplied-syscalls \
			CFLAGS_FOR_TARGET="-march=$(ARCH) -mabi=$(ABI) -O2 -g"; \
	fi
	@cd $(NEWLIB_BUILD) && $(MAKE) -j4
	@echo "✓ Newlib build complete"

# Install newlib
install-newlib: build-newlib
	@echo "Installing newlib to $(NEWLIB_INSTALL)..."
	@cd $(NEWLIB_BUILD) && $(MAKE) install
	@echo "✓ Newlib installed successfully"
	@echo ""
	@echo "You can now build with: make TARGET=printf_test USE_NEWLIB=1"

# Clean build artifacts
clean:
	@echo "Cleaning all firmware build artifacts..."
	@rm -f *.elf *.bin *.hex *.lst *.map *.o
	@echo "✓ Clean complete"

# Clean newlib build
clean-newlib:
	@echo "Cleaning newlib build directory..."
	@rm -rf $(NEWLIB_BUILD)/*
	@echo "✓ Newlib build directory cleaned"

# Help
help:
	@echo "Firmware Build System with Newlib Support"
	@echo ""
	@echo "Basic Targets:"
	@echo "  make all                 - Build all bare-metal firmware"
	@echo "  make newlib-targets      - Build all newlib-based firmware"
	@echo "  make TARGET=name         - Build specific target (bare metal)"
	@echo "  make TARGET=name USE_NEWLIB=1 - Build with newlib"
	@echo ""
	@echo "Newlib Management:"
	@echo "  make build-newlib        - Build newlib from source (~30 min)"
	@echo "  make install-newlib      - Build and install newlib"
	@echo "  make check-newlib        - Check if newlib is installed"
	@echo "  make clean-newlib        - Clean newlib build directory"
	@echo ""
	@echo "Available Targets:"
	@echo "  Bare Metal:"
	@echo "    led_blink              - LED animation demo"
	@echo "    interactive            - UART echo server"
	@echo "    button_demo            - Button polling example"
	@echo "    timer_clock            - Real-time clock demo"
	@echo "  With Newlib:"
	@echo "    printf_test            - Full printf/scanf test"
	@echo ""
	@echo "Utility Targets:"
	@echo "  make size                - Show memory usage"
	@echo "  make disasm              - Show disassembly"
	@echo "  make clean               - Remove build artifacts"
