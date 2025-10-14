//===============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform - Peripheral Library
// peripherals.h - Hardware abstraction layer for all peripherals
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#ifndef PERIPHERALS_H
#define PERIPHERALS_H

#include <stdint.h>

//==============================================================================
// MMIO Register Base Addresses
//==============================================================================

#define UART_BASE     0x80000000
#define LED_BASE      0x80000010
#define BUTTON_BASE   0x80000014
#define TIMER_BASE    0x80000020

//==============================================================================
// UART Registers
//==============================================================================

#define UART_TX_DATA   (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_TX_STATUS (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_RX_DATA   (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_RX_STATUS (*(volatile uint32_t*)(UART_BASE + 0x0C))

//==============================================================================
// LED Registers
//==============================================================================

#define LED_CONTROL (*(volatile uint32_t*)LED_BASE)

//==============================================================================
// Button Registers
//==============================================================================

#define BUTTON_STATUS (*(volatile uint32_t*)BUTTON_BASE)

//==============================================================================
// Timer Registers
//==============================================================================

#define TIMER_CR  (*(volatile uint32_t*)(TIMER_BASE + 0x00))  // Control register
#define TIMER_SR  (*(volatile uint32_t*)(TIMER_BASE + 0x04))  // Status register
#define TIMER_PSC (*(volatile uint32_t*)(TIMER_BASE + 0x08))  // Prescaler
#define TIMER_ARR (*(volatile uint32_t*)(TIMER_BASE + 0x0C))  // Auto-reload
#define TIMER_CNT (*(volatile uint32_t*)(TIMER_BASE + 0x10))  // Counter

//==============================================================================
// PicoRV32 Custom IRQ Instructions
//
// CRITICAL: These are the ONLY correct encodings for PicoRV32 IRQ control!
//
// PicoRV32 IRQ Mask:
//   - 1 = masked (interrupt DISABLED)
//   - 0 = unmasked (interrupt ENABLED)
//
// Instruction: .insn r 0x0B, 6, 3, rd, rs1, x0
//   - Opcode: 0x0B (custom-0)
//   - funct3: 6 (setq instruction)
//   - funct7: 3 (set IRQ mask)
//   - rs1: mask value (0=enable all, 0xFFFFFFFF=disable all)
//
// DO NOT modify these without understanding PicoRV32 ISA!
//==============================================================================

static inline void irq_enable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0" : "=r"(dummy) : "r"(0));
}

static inline void irq_disable(void) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0" : "=r"(dummy) : "r"(0xFFFFFFFF));
}

static inline void irq_setmask(uint32_t mask) {
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0" : "=r"(dummy) : "r"(mask));
}

//==============================================================================
// UART Functions
//==============================================================================

void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);
char uart_getc(void);              // Blocking read
int uart_available(void);          // Check if data available
char uart_getc_nonblocking(void);  // Returns 0 if no data

//==============================================================================
// LED Functions
//==============================================================================

void led_set(int led1, int led2);
void led_on(int led_num);
void led_off(int led_num);
void led_toggle(int led_num);

//==============================================================================
// Button Functions
//==============================================================================

int button_read(int button_num);  // Returns 1 if pressed, 0 if not
int button_wait(int button_num);  // Waits for button press

//==============================================================================
// Timer Functions
//==============================================================================

void timer_init(uint32_t prescaler, uint32_t reload);
void timer_start(void);
void timer_stop(void);
uint32_t timer_get_count(void);
void timer_clear_interrupt(void);

//==============================================================================
// Utility Functions
//==============================================================================

void delay_ms(uint32_t ms);        // Approximate delay
void delay_cycles(uint32_t cycles); // Precise cycle delay

#endif // PERIPHERALS_H
