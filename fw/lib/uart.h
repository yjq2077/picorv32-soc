// uart.h - AXI-Lite UART driver (public interface)
// Implements the register protocol of uart_axil.v (rtl/uart_axil.v).
#ifndef LIB_UART_H
#define LIB_UART_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t base;         // one of UART0_BASE / UART1_BASE
    uint16_t prescale;     // clk_hz / (8 * baud)
} uart_t;

// Init UART: configure baud prescale.
void uart_init(uart_t *u, uint16_t prescale);

// Transmit one byte (blocking until the TX buffer accepts it).
void uart_putc(uart_t *u, char c);

// Transmit a NUL-terminated string.
void uart_puts(uart_t *u, const char *s);

// Non-blocking RX check.
int uart_rx_avail(const uart_t *u);

// Receive one byte (blocking until a byte arrives).
char uart_getc(uart_t *u);

// 1 while the TX shift register / buffer still holds a byte.
int uart_tx_busy(const uart_t *u);

// Raw status word.
uint32_t uart_status(const uart_t *u);

#ifdef __cplusplus
}
#endif

#endif // LIB_UART_H
