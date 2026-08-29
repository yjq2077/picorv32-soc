// uart.c - AXI-Lite UART driver implementation
#include "uart.h"
#include "soc_addr.h"

void uart_init(uart_t *u, uint16_t prescale)
{
    u->prescale = prescale;
    REG32(u->base + UART_PRESCALE) = prescale;
}

void uart_putc(uart_t *u, char c)
{
    // wait until TXDATA accepted (tx_pending cleared by uart core)
    while (REG32(u->base + UART_STATUS) & UART_STATUS_TX_PENDING)
        ;
    REG32(u->base + UART_TXDATA) = (uint8_t)c;
}

void uart_puts(uart_t *u, const char *s)
{
    while (*s)
        uart_putc(u, *s++);
}

int uart_rx_avail(const uart_t *u)
{
    return (REG32(u->base + UART_STATUS) & UART_STATUS_RX_AVAIL) ? 1 : 0;
}

char uart_getc(uart_t *u)
{
    while (!(REG32(u->base + UART_STATUS) & UART_STATUS_RX_AVAIL))
        ;
    return (char)REG32(u->base + UART_RXDATA);
}

int uart_tx_busy(const uart_t *u)
{
    return (REG32(u->base + UART_STATUS) & UART_STATUS_TX_PENDING) ? 1 : 0;
}

uint32_t uart_status(const uart_t *u)
{
    return REG32(u->base + UART_STATUS);
}
