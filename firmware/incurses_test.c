//==============================================================================
// Incurses Test - Tests if incurses library works with timer
//==============================================================================

#include <stdio.h>
#include <stdint.h>
#include <curses.h>
#include "timer_ms.h"

// UART direct access (required by incurses)
#define UART_TX_DATA   (*(volatile unsigned int*)0x80000000)
#define UART_TX_STATUS (*(volatile unsigned int*)0x80000004)
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

// uart_putc and uart_getc required by incurses
void uart_putc(char c) {
    while (UART_TX_STATUS & 1);
    UART_TX_DATA = c;
}

char uart_getc(void) {
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

// IRQ Handler - routes timer interrupts
void irq_handler(uint32_t irqs) {
    if (irqs & (1 << 0)) {
        timer_ms_irq_handler();
    }
}

int main(int argc, char **argv) {
    // Wait for keypress before starting
    uart_getc();

    printf("Incurses test starting...\r\n");
    printf("argc=%d, argv=%p\r\n", argc, (void*)argv);

    printf("Initializing timer...\r\n");
    timer_ms_init();
    printf("Timer OK\r\n");

    printf("Initializing ncurses...\r\n");
    initscr();
    printf("initscr() OK\r\n");

    cbreak();
    printf("cbreak() OK\r\n");

    noecho();
    printf("noecho() OK\r\n");

    keypad(stdscr, TRUE);
    printf("keypad() OK\r\n");

    timeout(0);
    printf("timeout() OK\r\n");

    curs_set(0);
    printf("curs_set() OK\r\n");

    // Create a window
    printf("Creating window...\r\n");
    WINDOW *win = newwin(10, 20, 0, 0);
    printf("newwin() OK\r\n");

    // Draw to window
    box(win, 0, 0);
    wmove(win, 1, 1);
    wprintw(win, "Incurses Test");
    wmove(win, 2, 1);
    wprintw(win, "Clock:");
    wrefresh(win);

    printf("\r\nIncurses initialized successfully!\r\n");
    printf("Running clock display. Press 'q' to quit.\r\n\r\n");

    // Main loop with clock
    while(1) {
        uint32_t ms = get_millis();
        uint32_t total_seconds = ms / 1000;
        uint32_t hours = total_seconds / 3600;
        uint32_t minutes = (total_seconds % 3600) / 60;
        uint32_t seconds = total_seconds % 60;

        wmove(win, 3, 1);
        wprintw(win, "%02u:%02u:%02u", hours, minutes, seconds);
        wrefresh(win);

        sleep_milli(100);  // Update every 100ms

        int ch = getch();
        if (ch == 'q') {
            break;
        }
    }

    wclear(stdscr);
    endwin();

    printf("\r\n\r\nIncurses test complete!\r\n");
    while(1);  // Loop forever

    return 0;
}
