//===============================================================================
// Verify math_test.c expected values
// Compile: gcc verify_math.c -o verify_math -lm
//===============================================================================

#include <stdio.h>
#include <math.h>

int main() {
    printf("Math Test Value Verification\n");
    printf("=============================\n\n");

    printf("=== Basic Operations ===\n");
    printf("sqrt(2) = %.9f (expected: 1.414213562)\n", sqrt(2.0));

    printf("\n=== Trigonometry ===\n");
    printf("sin(M_PI/2) = %.9f (expected: 1.0)\n", sin(M_PI/2));
    printf("sin(M_PI) = %.9f (expected: 0.0)\n", sin(M_PI));
    printf("cos(M_PI/2) = %.9f (expected: 0.0)\n", cos(M_PI/2));
    printf("cos(M_PI) = %.9f (expected: -1.0)\n", cos(M_PI));
    printf("tan(M_PI/4) = %.9f (expected: 1.0)\n", tan(M_PI/4));
    printf("asin(0.5) = %.9f (expected: M_PI/6 = %.9f)\n", asin(0.5), M_PI/6);
    printf("acos(0.5) = %.9f (expected: M_PI/3 = %.9f)\n", acos(0.5), M_PI/3);
    printf("atan(1) = %.9f (expected: M_PI/4 = %.9f)\n", atan(1.0), M_PI/4);
    printf("atan2(1,1) = %.9f (expected: M_PI/4 = %.9f)\n", atan2(1.0, 1.0), M_PI/4);

    printf("\n=== Hyperbolic Functions ===\n");
    printf("sinh(1) = %.9f (expected: 1.175201194)\n", sinh(1.0));
    printf("cosh(1) = %.9f (expected: 1.543080635)\n", cosh(1.0));
    printf("tanh(1) = %.9f (expected: 0.761594156)\n", tanh(1.0));
    printf("asinh(1) = %.9f (expected: 0.881373587)\n", asinh(1.0));
    printf("acosh(2) = %.9f (expected: 1.316957897)\n", acosh(2.0));
    printf("atanh(0.5) = %.9f (expected: 0.549306144)\n", atanh(0.5));

    printf("\n=== Exponential & Logarithmic ===\n");
    printf("exp(1) = %.9f (expected: M_E = %.9f)\n", exp(1.0), M_E);
    printf("exp(2) = %.9f (expected: 7.389056099)\n", exp(2.0));
    printf("log(M_E) = %.9f (expected: 1.0)\n", log(M_E));
    printf("log(10) = %.9f (expected: 2.302585093)\n", log(10.0));
    printf("log10(10) = %.9f (expected: 1.0)\n", log10(10.0));
    printf("log10(100) = %.9f (expected: 2.0)\n", log10(100.0));
    printf("exp2(3) = %.9f (expected: 8.0)\n", exp2(3.0));
    printf("log2(8) = %.9f (expected: 3.0)\n", log2(8.0));

    printf("\n=== Rounding ===\n");
    printf("fmod(5.3, 2.0) = %.9f (expected: 1.3)\n", fmod(5.3, 2.0));
    printf("round(3.5) = %.9f (expected: 4.0)\n", round(3.5));
    printf("round(3.4) = %.9f (expected: 3.0)\n", round(3.4));

    printf("\nAll values checked!\n");
    return 0;
}
