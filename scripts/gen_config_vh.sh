#!/bin/bash
# Generate config.vh (Verilog header) from .config

set -e

if [ ! -f .config ]; then
    echo "ERROR: .config not found. Run 'make menuconfig' or 'make defconfig' first."
    exit 1
fi

source .config

mkdir -p build/generated

cat > build/generated/config.vh << EOF
// Auto-generated from .config - DO NOT EDIT
// Generated: $(date)

\`ifndef CONFIG_VH
\`define CONFIG_VH

// PicoRV32 Parameters
EOF

# Add defines based on config
if [ "${CONFIG_COMPRESSED_ISA}" = "y" ]; then
    echo "\`define COMPRESSED_ISA" >> build/generated/config.vh
fi

if [ "${CONFIG_ENABLE_MUL}" = "y" ]; then
    echo "\`define ENABLE_MUL" >> build/generated/config.vh
fi

if [ "${CONFIG_ENABLE_DIV}" = "y" ]; then
    echo "\`define ENABLE_DIV" >> build/generated/config.vh
fi

if [ "${CONFIG_BARREL_SHIFTER}" = "y" ]; then
    echo "\`define BARREL_SHIFTER" >> build/generated/config.vh
fi

cat >> build/generated/config.vh << EOF

// Memory Map
\`define ROM_BASE 32'h${CONFIG_ROM_BASE:-00040000}
\`define ROM_SIZE 32'h${CONFIG_ROM_SIZE:-00002000}
\`define APP_SRAM_BASE 32'h${CONFIG_APP_SRAM_BASE:-00000000}
\`define MMIO_BASE 32'h${CONFIG_MMIO_BASE:-80000000}

// UART Configuration
EOF

if [ "${CONFIG_PERIPHERAL_UART}" = "y" ]; then
    echo "\`define ENABLE_UART" >> build/generated/config.vh
fi

cat >> build/generated/config.vh << EOF
\`define UART_BASE 32'h${CONFIG_UART_BASE:-80000000}
\`define UART_BAUDRATE ${CONFIG_UART_BAUDRATE:-115200}

// Timer Configuration
EOF

if [ "${CONFIG_PERIPHERAL_TIMER}" = "y" ]; then
    echo "\`define ENABLE_TIMER" >> build/generated/config.vh
fi

cat >> build/generated/config.vh << EOF
\`define TIMER_BASE 32'h${CONFIG_TIMER_BASE:-80000020}

\`endif // CONFIG_VH
EOF

echo "✓ Generated build/generated/config.vh"
