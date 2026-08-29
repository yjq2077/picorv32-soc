// print.h - minimal console output (public interface)
// All output goes to UART0. Must call print_init() first.
#ifndef LIB_PRINT_H
#define LIB_PRINT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Configure the console UART prescale (clk_hz / (8 * baud)).
void print_init(uint16_t prescale);

void putchar_(char c);
void puts_(const char *s);

// Minimal printf: %d %u %x %X %c %s %p %%. No floating point.
int printf_(const char *fmt, ...);

#ifdef __cplusplus
}
#endif

#endif // LIB_PRINT_H
