//===============================================================================
// Exhaustive Math Library Test
// Tests all newlib math functions with known results
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//===============================================================================

#include <stdio.h>
#include <math.h>
#include <float.h>

// UART direct access for menu (no echo, no buffering)
#define UART_RX_DATA   (*(volatile unsigned int*)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int*)0x8000000C)

#define TOLERANCE 0.0001

static int getch(void) {
    while (!(UART_RX_STATUS & 0x01));
    return UART_RX_DATA & 0xFF;
}

static int check_float(const char *name, double result, double expected) {
    double diff = fabs(result - expected);
    int pass = (diff < TOLERANCE) || (fabs(diff / expected) < TOLERANCE);

    printf("  %s: ", name);
    if (pass) {
        printf("PASS (%.6f)\r\n", result);
    } else {
        printf("FAIL (got %.6f, expected %.6f, diff %.6f)\r\n",
               result, expected, diff);
    }
    return pass;
}

//==============================================================================
// Test Functions
//==============================================================================

static void test_basic_operations(void) {
    printf("\r\n=== Basic Operations ===\r\n");
    int pass = 0, total = 0;

    total++; pass += check_float("sqrt(4)", sqrt(4.0), 2.0);
    total++; pass += check_float("sqrt(9)", sqrt(9.0), 3.0);
    total++; pass += check_float("sqrt(2)", sqrt(2.0), 1.414213562);
    total++; pass += check_float("pow(2,3)", pow(2.0, 3.0), 8.0);
    total++; pass += check_float("pow(3,4)", pow(3.0, 4.0), 81.0);
    total++; pass += check_float("fabs(-5)", fabs(-5.0), 5.0);
    total++; pass += check_float("ceil(3.2)", ceil(3.2), 4.0);
    total++; pass += check_float("floor(3.7)", floor(3.7), 3.0);
    total++; pass += check_float("fmod(5.3,2)", fmod(5.3, 2.0), 1.3);

    printf("Result: %d/%d passed\r\n", pass, total);
}

static void test_trigonometry(void) {
    printf("\r\n=== Trigonometry ===\r\n");
    int pass = 0, total = 0;

    total++; pass += check_float("sin(0)", sin(0.0), 0.0);
    total++; pass += check_float("sin(PI/2)", sin(M_PI/2), 1.0);
    total++; pass += check_float("sin(PI)", sin(M_PI), 0.0);
    total++; pass += check_float("cos(0)", cos(0.0), 1.0);
    total++; pass += check_float("cos(PI/2)", cos(M_PI/2), 0.0);
    total++; pass += check_float("cos(PI)", cos(M_PI), -1.0);
    total++; pass += check_float("tan(0)", tan(0.0), 0.0);
    total++; pass += check_float("tan(PI/4)", tan(M_PI/4), 1.0);
    total++; pass += check_float("asin(0.5)", asin(0.5), M_PI/6);
    total++; pass += check_float("acos(0.5)", acos(0.5), M_PI/3);
    total++; pass += check_float("atan(1)", atan(1.0), M_PI/4);
    total++; pass += check_float("atan2(1,1)", atan2(1.0, 1.0), M_PI/4);

    printf("Result: %d/%d passed\r\n", pass, total);
}

static void test_hyperbolic(void) {
    printf("\r\n=== Hyperbolic Functions ===\r\n");
    int pass = 0, total = 0;

    total++; pass += check_float("sinh(0)", sinh(0.0), 0.0);
    total++; pass += check_float("sinh(1)", sinh(1.0), 1.175201194);
    total++; pass += check_float("cosh(0)", cosh(0.0), 1.0);
    total++; pass += check_float("cosh(1)", cosh(1.0), 1.543080635);
    total++; pass += check_float("tanh(0)", tanh(0.0), 0.0);
    total++; pass += check_float("tanh(1)", tanh(1.0), 0.761594156);
    total++; pass += check_float("asinh(1)", asinh(1.0), 0.881373587);
    total++; pass += check_float("acosh(2)", acosh(2.0), 1.316957897);
    total++; pass += check_float("atanh(0.5)", atanh(0.5), 0.549306144);

    printf("Result: %d/%d passed\r\n", pass, total);
}

static void test_exponential_log(void) {
    printf("\r\n=== Exponential & Logarithmic ===\r\n");
    int pass = 0, total = 0;

    total++; pass += check_float("exp(0)", exp(0.0), 1.0);
    total++; pass += check_float("exp(1)", exp(1.0), M_E);
    total++; pass += check_float("exp(2)", exp(2.0), 7.389056099);
    total++; pass += check_float("log(1)", log(1.0), 0.0);
    total++; pass += check_float("log(e)", log(M_E), 1.0);
    total++; pass += check_float("log(10)", log(10.0), 2.302585093);
    total++; pass += check_float("log10(1)", log10(1.0), 0.0);
    total++; pass += check_float("log10(10)", log10(10.0), 1.0);
    total++; pass += check_float("log10(100)", log10(100.0), 2.0);
    total++; pass += check_float("exp2(3)", exp2(3.0), 8.0);
    total++; pass += check_float("log2(8)", log2(8.0), 3.0);

    printf("Result: %d/%d passed\r\n", pass, total);
}

static void test_special_values(void) {
    printf("\r\n=== Special Values ===\r\n");
    int pass = 0, total = 0;

    // Test infinity
    double inf = INFINITY;
    double ninf = -INFINITY;

    printf("  INFINITY: %s\r\n", isinf(inf) ? "PASS" : "FAIL");
    total++; pass += isinf(inf);

    printf("  -INFINITY: %s\r\n", isinf(ninf) ? "PASS" : "FAIL");
    total++; pass += isinf(ninf);

    // Test NaN
    double nan_val = NAN;
    printf("  NAN: %s\r\n", isnan(nan_val) ? "PASS" : "FAIL");
    total++; pass += isnan(nan_val);

    printf("  sqrt(-1) -> NAN: %s\r\n", isnan(sqrt(-1.0)) ? "PASS" : "FAIL");
    total++; pass += isnan(sqrt(-1.0));

    // Test zero
    total++; pass += check_float("copysign(1,-1)", copysign(1.0, -1.0), -1.0);
    total++; pass += check_float("fmax(3,5)", fmax(3.0, 5.0), 5.0);
    total++; pass += check_float("fmin(3,5)", fmin(3.0, 5.0), 3.0);

    printf("Result: %d/%d passed\r\n", pass, total);
}

static void test_rounding(void) {
    printf("\r\n=== Rounding Functions ===\r\n");
    int pass = 0, total = 0;

    total++; pass += check_float("ceil(3.1)", ceil(3.1), 4.0);
    total++; pass += check_float("ceil(-3.1)", ceil(-3.1), -3.0);
    total++; pass += check_float("floor(3.9)", floor(3.9), 3.0);
    total++; pass += check_float("floor(-3.9)", floor(-3.9), -4.0);
    total++; pass += check_float("trunc(3.9)", trunc(3.9), 3.0);
    total++; pass += check_float("trunc(-3.9)", trunc(-3.9), -3.0);
    total++; pass += check_float("round(3.5)", round(3.5), 4.0);
    total++; pass += check_float("round(3.4)", round(3.4), 3.0);

    printf("Result: %d/%d passed\r\n", pass, total);
}

static void test_stress_computation(void) {
    printf("\r\n=== Stress Test (30 seconds) ===\r\n");
    printf("Computing 100,000 mixed math operations...\r\n");
    fflush(stdout);

    unsigned int iterations = 100000;
    double sum = 0.0;

    for (unsigned int i = 1; i <= iterations; i++) {
        double x = (double)i / 1000.0;

        // Mix of operations
        double result = sin(x) * cos(x) + sqrt(x) + log(x + 1.0) + exp(x / 1000.0);
        sum += result;

        if (i % 10000 == 0) {
            printf("  %u iterations complete...\r\n", i);
            fflush(stdout);
        }
    }

    printf("\r\nCompleted %u iterations\r\n", iterations);
    printf("Final sum: %.10f\r\n", sum);
    printf("PASS (no crashes)\r\n");
}

//==============================================================================
// Main Menu
//==============================================================================

static void show_menu(void) {
    printf("\r\n");
    printf("========================================\r\n");
    printf("  Exhaustive Math Test Suite\r\n");
    printf("========================================\r\n");
    printf("1. Basic operations (sqrt, pow, abs)\r\n");
    printf("2. Trigonometry (sin, cos, tan, etc.)\r\n");
    printf("3. Hyperbolic functions\r\n");
    printf("4. Exponential & logarithmic\r\n");
    printf("5. Special values (inf, nan)\r\n");
    printf("6. Rounding functions\r\n");
    printf("7. Stress test (30 seconds)\r\n");
    printf("8. Run all tests\r\n");
    printf("h. Show this menu\r\n");
    printf("q. Quit\r\n");
    printf("========================================\r\n");
    printf("Select option: ");
    fflush(stdout);
}

int main(void) {
    printf("\r\n\r\n");
    printf("========================================\r\n");
    printf("  Exhaustive Math Test Suite\r\n");
    printf("  Testing newlib math library\r\n");
    printf("========================================\r\n");
    printf("\r\n");
    printf("Press any key to start...\r\n");

    getch();

    printf("\r\n");
    printf("Terminal connected!\r\n");
    printf("Math constants:\r\n");
    printf("  M_PI = %.10f\r\n", M_PI);
    printf("  M_E  = %.10f\r\n", M_E);

    show_menu();

    while (1) {
        int choice = getch();

        printf("\r\n");

        switch (choice) {
            case '1':
                test_basic_operations();
                show_menu();
                break;

            case '2':
                test_trigonometry();
                show_menu();
                break;

            case '3':
                test_hyperbolic();
                show_menu();
                break;

            case '4':
                test_exponential_log();
                show_menu();
                break;

            case '5':
                test_special_values();
                show_menu();
                break;

            case '6':
                test_rounding();
                show_menu();
                break;

            case '7':
                test_stress_computation();
                show_menu();
                break;

            case '8':
                test_basic_operations();
                test_trigonometry();
                test_hyperbolic();
                test_exponential_log();
                test_special_values();
                test_rounding();
                test_stress_computation();
                printf("\r\n");
                printf("========================================\r\n");
                printf("All math tests complete!\r\n");
                printf("========================================\r\n");
                show_menu();
                break;

            case 'h':
            case 'H':
                show_menu();
                break;

            case 'q':
            case 'Q':
                printf("Quitting...\r\n");
                printf("Entering infinite loop (WFI).\r\n");
                while (1) {
                    __asm__ volatile ("wfi");
                }
                break;

            default:
                printf("Invalid option: '%c'. Press 'h' for menu.\r\n", choice);
                break;
        }
    }

    return 0;
}
