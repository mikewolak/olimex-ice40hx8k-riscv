//===============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform - Peripheral Library
// peripherals.c - Implementation of peripheral functions
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include "peripherals.h"

//==============================================================================
// UART Functions
//==============================================================================

void uart_init(void) {
    // UART is always initialized by hardware - nothing to do
}

void uart_putc(char c) {
    // Wait while TX is busy
    while (UART_TX_STATUS & 0x01);
    UART_TX_DATA = c;
}

void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

char uart_getc(void) {
    // Wait for RX data available (bit is 1 when data ready)
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

int uart_available(void) {
    // Returns 1 if data available, 0 if not
    return (UART_RX_STATUS & 0x01) ? 1 : 0;
}

char uart_getc_nonblocking(void) {
    if (uart_available()) {
        return UART_RX_DATA & 0xFF;
    }
    return 0;
}

//==============================================================================
// LED Functions
//==============================================================================

void led_set(int led1, int led2) {
    LED_CONTROL = (led2 << 1) | led1;
}

void led_on(int led_num) {
    uint32_t current = LED_CONTROL;
    LED_CONTROL = current | (1 << led_num);
}

void led_off(int led_num) {
    uint32_t current = LED_CONTROL;
    LED_CONTROL = current & ~(1 << led_num);
}

void led_toggle(int led_num) {
    uint32_t current = LED_CONTROL;
    LED_CONTROL = current ^ (1 << led_num);
}

//==============================================================================
// Button Functions
//==============================================================================

int button_read(int button_num) {
    return (BUTTON_STATUS >> button_num) & 0x01;
}

int button_wait(int button_num) {
    // Wait for button press
    while (!button_read(button_num));

    // Simple debounce
    for (volatile int i = 0; i < 10000; i++);

    // Wait for release
    while (button_read(button_num));

    return 1;
}

//==============================================================================
// Timer Functions
//==============================================================================

void timer_init(uint32_t prescaler, uint32_t reload) {
    TIMER_CR = 0;  // Stop timer
    TIMER_PSC = prescaler;
    TIMER_ARR = reload;
    TIMER_CNT = 0;
}

void timer_start(void) {
    TIMER_CR = 0x00000001;
}

void timer_stop(void) {
    TIMER_CR = 0x00000000;
}

uint32_t timer_get_count(void) {
    return TIMER_CNT;
}

void timer_clear_interrupt(void) {
    TIMER_SR = 0x00000001;  // Write 1 to clear
}

//==============================================================================
// Utility Functions
//==============================================================================

void delay_cycles(uint32_t cycles) {
    for (volatile uint32_t i = 0; i < cycles; i++);
}

void delay_ms(uint32_t ms) {
    // Approximate delay assuming 50 MHz clock
    // Rough estimate: 50000 cycles per ms
    delay_cycles(ms * 50000);
}
