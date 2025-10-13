//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// timer_regs.h - Timer Peripheral Register Definitions
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

#ifndef TIMER_REGS_H
#define TIMER_REGS_H

#include <stdint.h>

//==============================================================================
// Timer Peripheral Memory Map (STM32-style)
//
// Base Address: 0x80000020
// Size: 16 bytes (5 registers)
//==============================================================================

#define TIMER_BASE      0x80000020

// Register offsets from TIMER_BASE
#define TIMER_CR_OFFSET   0x00  // Control Register
#define TIMER_SR_OFFSET   0x04  // Status Register
#define TIMER_PSC_OFFSET  0x08  // Prescaler
#define TIMER_ARR_OFFSET  0x0C  // Auto-Reload Register
#define TIMER_CNT_OFFSET  0x10  // Counter (read-only)

// Register pointers
#define TIMER_CR   (*((volatile uint32_t *)(TIMER_BASE + TIMER_CR_OFFSET)))
#define TIMER_SR   (*((volatile uint32_t *)(TIMER_BASE + TIMER_SR_OFFSET)))
#define TIMER_PSC  (*((volatile uint32_t *)(TIMER_BASE + TIMER_PSC_OFFSET)))
#define TIMER_ARR  (*((volatile uint32_t *)(TIMER_BASE + TIMER_ARR_OFFSET)))
#define TIMER_CNT  (*((volatile uint32_t *)(TIMER_BASE + TIMER_CNT_OFFSET)))

//==============================================================================
// Control Register (CR) Bit Definitions
//==============================================================================

#define TIMER_CR_ENABLE     (1 << 0)  // Timer enable (1=running, 0=stopped)
#define TIMER_CR_ONE_SHOT   (1 << 1)  // One-shot mode (1=one-shot, 0=continuous)

//==============================================================================
// Status Register (SR) Bit Definitions
//==============================================================================

#define TIMER_SR_UIF        (1 << 0)  // Update Interrupt Flag (write 1 to clear)

//==============================================================================
// Timer Helper Functions
//==============================================================================

// Initialize timer (stopped, continuous mode)
static inline void timer_init(void) {
    TIMER_CR = 0;  // Disable timer
    TIMER_SR = TIMER_SR_UIF;  // Clear any pending interrupt
}

// Configure timer prescaler and period
// PSC: Prescaler value (0-65535), divides clock by (PSC+1)
// ARR: Auto-reload value (0-0xFFFFFFFF), counter reload value
//
// Interrupt rate = SYSCLK / (PSC+1) / (ARR+1)
// Example: 50MHz / (49+1) / (16666+1) = 60 Hz (every 16.67ms)
static inline void timer_config(uint16_t psc, uint32_t arr) {
    TIMER_PSC = psc;
    TIMER_ARR = arr;
}

// Start timer (continuous mode)
static inline void timer_start(void) {
    TIMER_CR = TIMER_CR_ENABLE;  // Enable, continuous mode
}

// Start timer (one-shot mode)
static inline void timer_start_oneshot(void) {
    TIMER_CR = TIMER_CR_ENABLE | TIMER_CR_ONE_SHOT;
}

// Stop timer
static inline void timer_stop(void) {
    TIMER_CR = 0;
}

// Clear interrupt flag (write 1 to clear)
static inline void timer_clear_irq(void) {
    TIMER_SR = TIMER_SR_UIF;
}

// Check if interrupt is pending
static inline uint32_t timer_irq_pending(void) {
    return TIMER_SR & TIMER_SR_UIF;
}

// Read current counter value
static inline uint32_t timer_read_counter(void) {
    return TIMER_CNT;
}

#endif // TIMER_REGS_H
