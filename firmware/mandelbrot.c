//==============================================================================
// Mandelbrot Set Explorer with Interactive Zoom
//==============================================================================
// Controls:
//   Arrow keys: Move cursor
//   S: Start selection mode, move cursor, Enter to confirm
//   Enter: Zoom to selection
//   R: Reset to default view
//   +/-: Adjust max iterations
//   Q: Quit
//==============================================================================

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <curses.h>
#include "timer_ms.h"

//==============================================================================
// Hardware UART (required by incurses)
//==============================================================================
#define UART_TX_DATA   (*(volatile uint32_t *)0x80000000)
#define UART_TX_STATUS (*(volatile uint32_t *)0x80000004)
#define UART_RX_DATA   (*(volatile uint32_t *)0x80000008)
#define UART_RX_STATUS (*(volatile uint32_t *)0x8000000C)

void uart_putc(char c) {
    while (UART_TX_STATUS & 1);
    UART_TX_DATA = c;
}

int uart_getc_available(void) {
    return UART_RX_STATUS & 1;
}

char uart_getc(void) {
    while (!uart_getc_available());
    return UART_RX_DATA & 0xFF;
}

//==============================================================================
// VT100 Terminal Size Detection
//==============================================================================
static int g_term_rows = 24;  // Default fallback
static int g_term_cols = 80;

// Query terminal size using VT100 escape sequences
static bool query_terminal_size(void) {
    // Move cursor to far bottom-right (row 999, col 999)
    printf("\033[999;999H");

    // Query cursor position - terminal will respond with: ESC [ row ; col R
    printf("\033[6n");
    fflush(stdout);

    // Read response with timeout
    char buf[32];
    int i = 0;
    uint32_t start_time = get_millis();

    while (i < (int)sizeof(buf) - 1) {
        // Timeout after 500ms
        if (get_millis() - start_time > 500) {
            printf("\033[H");  // Move cursor to home
            return false;
        }

        if (uart_getc_available()) {
            buf[i] = uart_getc();
            if (buf[i] == 'R') {
                buf[i] = '\0';
                break;
            }
            i++;
        }
    }

    // Parse response: ESC [ rows ; cols R
    if (i > 0 && buf[0] == '\033' && buf[1] == '[') {
        int rows = 0, cols = 0;
        // Simple parser (avoid sscanf for embedded)
        char *p = buf + 2;

        // Parse rows
        while (*p >= '0' && *p <= '9') {
            rows = rows * 10 + (*p - '0');
            p++;
        }

        if (*p == ';') {
            p++;
            // Parse cols
            while (*p >= '0' && *p <= '9') {
                cols = cols * 10 + (*p - '0');
                p++;
            }
        }

        if (rows > 0 && cols > 0 && rows <= 200 && cols <= 300) {
            g_term_rows = rows;
            g_term_cols = cols;
            printf("\033[H");  // Move cursor to home
            return true;
        }
    }

    printf("\033[H");  // Move cursor to home
    return false;
}

//==============================================================================
// IRQ Handler - Timer Interrupts
//==============================================================================
void irq_handler(uint32_t irqs) {
    if (irqs & (1 << 0)) {
        timer_ms_irq_handler();
    }
}

//==============================================================================
// Mandelbrot Configuration
//==============================================================================
#define MAX_ITER_DEFAULT 256
#define MAX_ITER_MAX 1024

// Screen dimensions (use detected terminal size, minus room for info bars)
#define SCREEN_WIDTH  (g_term_cols)
#define SCREEN_HEIGHT (g_term_rows - 2)  // Reserve 2 lines for info/controls

// Palette using various shading characters for iteration depth
static const char* PALETTE[] = {
    " ",   // 0: inside set
    ".",   // 1-2 iterations
    ":",   // 3-4
    "-",   // 5-8
    "=",   // 9-16
    "+",   // 17-32
    "*",   // 33-64
    "#",   // 65-128
    "%",   // 129-256
    "@",   // 257-512
    "\xE2\x96\x93"  // 513+: dark shade █
};

//==============================================================================
// Mandelbrot State
//==============================================================================
typedef struct {
    double min_real, max_real;
    double min_imag, max_imag;
    int max_iter;
    int cursor_x, cursor_y;
    int sel_x1, sel_y1, sel_x2, sel_y2;
    bool selecting;
    uint32_t last_calc_time_ms;
} mandelbrot_state;

static mandelbrot_state state;

//==============================================================================
// Fixed-point Mandelbrot (faster than floating point)
//==============================================================================
#define FIXED_SHIFT 16
#define FIXED_ONE (1 << FIXED_SHIFT)

static inline int32_t double_to_fixed(double d) {
    return (int32_t)(d * FIXED_ONE);
}

static inline int32_t fixed_mul(int32_t a, int32_t b) {
    return (int32_t)(((int64_t)a * (int64_t)b) >> FIXED_SHIFT);
}

// Calculate Mandelbrot iterations for a point
static int mandelbrot_iterations(double cx, double cy, int max_iter) {
    int32_t cr = double_to_fixed(cx);
    int32_t ci = double_to_fixed(cy);
    int32_t zr = 0;
    int32_t zi = 0;
    int32_t zr2 = 0;
    int32_t zi2 = 0;

    int iter = 0;
    while (iter < max_iter && (zr2 + zi2) < (4 << FIXED_SHIFT)) {
        zi = fixed_mul(zr, zi);
        zi += zi;  // 2 * zr * zi
        zi += ci;

        zr = zr2 - zi2 + cr;

        zr2 = fixed_mul(zr, zr);
        zi2 = fixed_mul(zi, zi);

        iter++;
    }

    return iter;
}

//==============================================================================
// Map iteration count to character
//==============================================================================
static const char* iter_to_char(int iter, int max_iter) {
    if (iter >= max_iter) {
        return PALETTE[0];  // Inside set
    }

    // Map to palette index logarithmically
    int idx = 1;
    int threshold = 2;

    while (idx < 10 && iter > threshold) {
        threshold *= 2;
        idx++;
    }

    return PALETTE[idx];
}

//==============================================================================
// Draw the Mandelbrot Set
//==============================================================================
static void draw_mandelbrot(WINDOW *win) {
    uint32_t start_time = get_millis();

    double real_step = (state.max_real - state.min_real) / SCREEN_WIDTH;
    double imag_step = (state.max_imag - state.min_imag) / SCREEN_HEIGHT;

    for (int row = 0; row < SCREEN_HEIGHT; row++) {
        wmove(win, row, 0);

        for (int col = 0; col < SCREEN_WIDTH; col++) {
            double real = state.min_real + col * real_step;
            double imag = state.min_imag + row * imag_step;

            int iter = mandelbrot_iterations(real, imag, state.max_iter);
            const char* ch = iter_to_char(iter, state.max_iter);

            wprintw(win, "%s", ch);
        }
    }

    state.last_calc_time_ms = get_millis() - start_time;
    wrefresh(win);
}

//==============================================================================
// Draw cursor and selection box
//==============================================================================
static void draw_cursor(WINDOW *win) {
    // Draw cursor
    wmove(win, state.cursor_y, state.cursor_x);
    waddch(win, '+' | A_REVERSE);

    // Draw selection box if selecting
    if (state.selecting) {
        int x1 = state.sel_x1 < state.sel_x2 ? state.sel_x1 : state.sel_x2;
        int x2 = state.sel_x1 < state.sel_x2 ? state.sel_x2 : state.sel_x1;
        int y1 = state.sel_y1 < state.sel_y2 ? state.sel_y1 : state.sel_y2;
        int y2 = state.sel_y1 < state.sel_y2 ? state.sel_y2 : state.sel_y1;

        // Draw horizontal lines
        for (int x = x1; x <= x2; x++) {
            wmove(win, y1, x);
            waddch(win, '-' | A_REVERSE);
            wmove(win, y2, x);
            waddch(win, '-' | A_REVERSE);
        }

        // Draw vertical lines
        for (int y = y1; y <= y2; y++) {
            wmove(win, y, x1);
            waddch(win, '|' | A_REVERSE);
            wmove(win, y, x2);
            waddch(win, '|' | A_REVERSE);
        }

        // Draw corners
        wmove(win, y1, x1); waddch(win, '+' | A_REVERSE);
        wmove(win, y1, x2); waddch(win, '+' | A_REVERSE);
        wmove(win, y2, x1); waddch(win, '+' | A_REVERSE);
        wmove(win, y2, x2); waddch(win, '+' | A_REVERSE);
    }

    wrefresh(win);
}

//==============================================================================
// Zoom to selection
//==============================================================================
static void zoom_to_selection(void) {
    if (!state.selecting) return;

    int x1 = state.sel_x1 < state.sel_x2 ? state.sel_x1 : state.sel_x2;
    int x2 = state.sel_x1 < state.sel_x2 ? state.sel_x2 : state.sel_x1;
    int y1 = state.sel_y1 < state.sel_y2 ? state.sel_y1 : state.sel_y2;
    int y2 = state.sel_y1 < state.sel_y2 ? state.sel_y2 : state.sel_y1;

    // Ensure minimum selection size
    if ((x2 - x1) < 2 || (y2 - y1) < 2) return;

    // Map screen coordinates to complex plane
    double real_step = (state.max_real - state.min_real) / SCREEN_WIDTH;
    double imag_step = (state.max_imag - state.min_imag) / SCREEN_HEIGHT;

    double new_min_real = state.min_real + x1 * real_step;
    double new_max_real = state.min_real + x2 * real_step;
    double new_min_imag = state.min_imag + y1 * imag_step;
    double new_max_imag = state.min_imag + y2 * imag_step;

    state.min_real = new_min_real;
    state.max_real = new_max_real;
    state.min_imag = new_min_imag;
    state.max_imag = new_max_imag;

    state.selecting = false;
}

//==============================================================================
// Reset to default view
//==============================================================================
static void reset_view(void) {
    state.min_real = -2.5;
    state.max_real = 1.0;
    state.min_imag = -1.0;
    state.max_imag = 1.0;
    state.cursor_x = SCREEN_WIDTH / 2;
    state.cursor_y = SCREEN_HEIGHT / 2;
    state.selecting = false;
}

//==============================================================================
// Display info bar
//==============================================================================
static void draw_info_bar(void) {
    move(SCREEN_HEIGHT, 0);
    clrtoeol();

    double center_real = (state.min_real + state.max_real) / 2.0;
    double center_imag = (state.min_imag + state.max_imag) / 2.0;
    double zoom = 3.5 / (state.max_real - state.min_real);

    printw("Center: %.10f%+.10fi | Zoom: %.2fx | Iter: %d | Calc: %lums",
           center_real, center_imag, zoom, state.max_iter,
           (unsigned long)state.last_calc_time_ms);

    move(SCREEN_HEIGHT + 1, 0);
    clrtoeol();
    printw("Arrows:Move S:Select Enter:Zoom R:Reset +/-:Iter ESC:Cancel Q:Quit");

    refresh();
}

//==============================================================================
// Main Program
//==============================================================================
int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    // Wait for keypress before starting
    uart_getc();

    printf("Mandelbrot Set Explorer\r\n");
    printf("Initializing...\r\n");

    // Initialize timer (needed for query_terminal_size timeout)
    timer_ms_init();

    // Detect terminal size before initializing curses
    printf("Detecting terminal size...\r\n");
    if (query_terminal_size()) {
        printf("Terminal: %d rows x %d cols\r\n", g_term_rows, g_term_cols);
        printf("Render area: %d rows x %d cols\r\n", SCREEN_HEIGHT, SCREEN_WIDTH);
    } else {
        printf("Failed to detect terminal size, using defaults: %d x %d\r\n",
               g_term_rows, g_term_cols);
    }

    // Initialize ncurses
    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);
    timeout(0);
    curs_set(0);

    // Initialize state
    reset_view();
    state.max_iter = MAX_ITER_DEFAULT;
    state.last_calc_time_ms = 0;

    // Create main window
    WINDOW *mandel_win = newwin(SCREEN_HEIGHT, SCREEN_WIDTH, 0, 0);

    printf("Drawing initial view...\r\n");

    // Draw initial mandelbrot
    draw_mandelbrot(mandel_win);
    draw_cursor(mandel_win);
    draw_info_bar();

    bool running = true;
    bool needs_redraw = false;

    // Main loop
    while (running) {
        int ch = getch();

        if (ch != ERR) {
            bool cursor_moved = false;

            switch (ch) {
                // Quit
                case 'q':
                case 'Q':
                    running = false;
                    break;

                // Reset view
                case 'r':
                case 'R':
                    reset_view();
                    needs_redraw = true;
                    break;

                // Adjust max iterations
                case '+':
                case '=':
                    if (state.max_iter < MAX_ITER_MAX) {
                        state.max_iter = (state.max_iter < 256) ?
                                        state.max_iter + 32 :
                                        state.max_iter + 128;
                        if (state.max_iter > MAX_ITER_MAX)
                            state.max_iter = MAX_ITER_MAX;
                        needs_redraw = true;
                    }
                    break;

                case '-':
                case '_':
                    if (state.max_iter > 32) {
                        state.max_iter = (state.max_iter <= 256) ?
                                        state.max_iter - 32 :
                                        state.max_iter - 128;
                        if (state.max_iter < 32)
                            state.max_iter = 32;
                        needs_redraw = true;
                    }
                    break;

                // Zoom to selection
                case '\n':
                case '\r':
                    if (state.selecting) {
                        zoom_to_selection();
                        needs_redraw = true;
                    }
                    break;

                // Arrow key navigation
                case KEY_UP:
                    if (state.cursor_y > 0) {
                        state.cursor_y--;
                        cursor_moved = true;
                    }
                    break;

                case KEY_DOWN:
                    if (state.cursor_y < SCREEN_HEIGHT - 1) {
                        state.cursor_y++;
                        cursor_moved = true;
                    }
                    break;

                case KEY_LEFT:
                    if (state.cursor_x > 0) {
                        state.cursor_x--;
                        cursor_moved = true;
                    }
                    break;

                case KEY_RIGHT:
                    if (state.cursor_x < SCREEN_WIDTH - 1) {
                        state.cursor_x++;
                        cursor_moved = true;
                    }
                    break;

                // 'S' key to start/toggle selection mode
                case 's':
                case 'S':
                    if (!state.selecting) {
                        // Start selection
                        state.selecting = true;
                        state.sel_x1 = state.cursor_x;
                        state.sel_y1 = state.cursor_y;
                        state.sel_x2 = state.cursor_x;
                        state.sel_y2 = state.cursor_y;
                    } else {
                        // Update second corner of selection
                        state.sel_x2 = state.cursor_x;
                        state.sel_y2 = state.cursor_y;
                    }
                    needs_redraw = true;
                    break;

                // Escape cancels selection
                case 27:  // ESC
                    state.selecting = false;
                    needs_redraw = true;
                    break;
            }

            // Redraw if cursor moved or selection changed
            if (cursor_moved || needs_redraw) {
                if (needs_redraw) {
                    wclear(mandel_win);
                    draw_mandelbrot(mandel_win);
                    needs_redraw = false;
                } else {
                    // Just redraw the last frame (removes old cursor)
                    wrefresh(mandel_win);
                }

                draw_cursor(mandel_win);
                draw_info_bar();
            }
        }

        // Small delay to reduce CPU usage
        for (volatile int i = 0; i < 1000; i++);
    }

    // Cleanup
    wclear(stdscr);
    endwin();

    printf("\r\n\r\nMandelbrot Explorer exited.\r\n");
    printf("Final view: [%.6f, %.6f] x [%.6f, %.6f]\r\n",
           state.min_real, state.max_real, state.min_imag, state.max_imag);
    printf("Max iterations: %d\r\n", state.max_iter);
    printf("Last calculation time: %lu ms\r\n", (unsigned long)state.last_calc_time_ms);

    while(1);  // Hang for embedded system
    return 0;
}
