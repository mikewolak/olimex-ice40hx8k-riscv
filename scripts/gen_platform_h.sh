#!/bin/bash
# Generate platform.h from .config

set -e

if [ ! -f .config ]; then
    echo "ERROR: .config not found. Run 'make menuconfig' or 'make defconfig' first."
    exit 1
fi

source .config

mkdir -p build/generated

cat > build/generated/platform.h << EOF
/* Auto-generated from .config - DO NOT EDIT */
/* Generated: $(date) */

#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>

/* Memory Map */
#define APP_SRAM_BASE    ${CONFIG_APP_SRAM_BASE:-0x00000000}
#define APP_SRAM_SIZE    ${CONFIG_APP_SRAM_SIZE:-0x00040000}
#define ROM_BASE         ${CONFIG_ROM_BASE:-0x00040000}
#define ROM_SIZE         ${CONFIG_ROM_SIZE:-0x00002000}
#define STACK_SRAM_BASE  ${CONFIG_STACK_SRAM_BASE:-0x00042000}
#define STACK_TOP        ${CONFIG_STACKADDR:-0x00080000}

/* MMIO Peripherals */
#define MMIO_BASE        ${CONFIG_MMIO_BASE:-0x80000000}

/* UART */
#define UART_BASE        ${CONFIG_UART_BASE:-0x80000000}
#define UART_TX_DATA     (UART_BASE + 0x00)
#define UART_TX_STATUS   (UART_BASE + 0x04)
#define UART_RX_DATA     (UART_BASE + 0x08)
#define UART_RX_STATUS   (UART_BASE + 0x0C)
#define UART_BAUDRATE    ${CONFIG_UART_BAUDRATE:-115200}

/* LED Control */
#define LED_CONTROL      (MMIO_BASE + 0x10)

/* Button Input */
#define BUTTON_INPUT     (MMIO_BASE + 0x18)

/* Timer */
#define TIMER_BASE       ${CONFIG_TIMER_BASE:-0x80000020}

/* Helper functions */
static inline void uart_putc(char c) {
    volatile uint32_t *tx_data = (volatile uint32_t *)UART_TX_DATA;
    volatile uint32_t *tx_status = (volatile uint32_t *)UART_TX_STATUS;
    while (*tx_status & 1);  // Wait for not busy
    *tx_data = c;
}

static inline char uart_getc(void) {
    volatile uint32_t *rx_data = (volatile uint32_t *)UART_RX_DATA;
    volatile uint32_t *rx_status = (volatile uint32_t *)UART_RX_STATUS;
    while (!(*rx_status & 1));  // Wait for data available
    return (char)(*rx_data & 0xFF);
}

#endif /* PLATFORM_H */
EOF

chmod +x build/generated/platform.h 2>/dev/null || true
echo "✓ Generated build/generated/platform.h"
