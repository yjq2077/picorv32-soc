// uart.c - AXI-Lite UART driver implementation
// Blocking (polling) + interrupt-driven (STM32-HAL style) modes.
#include "uart.h"
#include "soc_addr.h"
#include "irq_ctrl.h"
#include "riscv_cpu.h"

// ---------------------------------------------------------------------
// Blocking (polling) API
// ---------------------------------------------------------------------

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

// ---------------------------------------------------------------------
// Interrupt-driven API (STM32-HAL style)
// ---------------------------------------------------------------------

// The TX interrupt is edge-triggered: it fires on the "core ready" edge
// (s_axis_tready rising) and only while a transmission is in flight.  If the
// core is idle there is no edge to wake it, so submit the first queued byte
// directly to start the flow (one byte per call, matching the ISR model).
static void uart_it_tx_kick(uart_t *u)
{
    if (!(REG32(u->base + UART_STATUS) & UART_STATUS_TX_PENDING) &&
        u->tx_head != u->tx_tail) {
        REG32(u->base + UART_TXDATA) = u->tx_ring[u->tx_tail];
        u->tx_tail = (uint16_t)((u->tx_tail + 1) % u->tx_ring_size);
    }
}

int uart_it_init(uart_t *u, uint16_t prescale,
                 uint8_t *tx_ring, uint16_t tx_ring_size,
                 uint8_t *rx_ring, uint16_t rx_ring_size,
                 uint8_t irq_src_rx, uint8_t irq_src_tx)
{
    if (u->tx_ring != 0 || u->rx_ring != 0)
        return -1;

    u->prescale     = prescale;
    u->tx_ring      = tx_ring;
    u->tx_head      = 0;
    u->tx_tail      = 0;
    u->tx_ring_size = tx_ring_size;
    u->tx_active    = 0;
    u->rx_ring      = rx_ring;
    u->rx_head      = 0;
    u->rx_tail      = 0;
    u->rx_ring_size = rx_ring_size;
    u->rx_active    = 0;
    u->irq_src_rx   = irq_src_rx;
    u->irq_src_tx   = irq_src_tx;

    REG32(u->base + UART_PRESCALE) = prescale;

    // start collecting bytes into the RX background ring
    irq_enable_src(u->irq_src_rx);
    return 0;
}

int uart_transmit_it(uart_t *u, const uint8_t *data, uint16_t size)
{
    uint32_t key;

    if (u->tx_ring == 0)
        return -1;

    key = irq_global_save();
    if (u->tx_active) {
        irq_global_restore(key);
        return -1;
    }
    // make sure the whole message fits before touching the ring
    uint16_t free = (u->tx_ring_size - 1u) -
                    (uint16_t)((u->tx_head - u->tx_tail) % u->tx_ring_size);
    if (free < size) {
        irq_global_restore(key);
        return -1;
    }
    for (uint16_t i = 0; i < size; i++) {
        u->tx_ring[u->tx_head] = data[i];
        u->tx_head = (uint16_t)((u->tx_head + 1) % u->tx_ring_size);
    }
    u->tx_active = 1;
    irq_global_restore(key);

    // arm the TX-empty interrupt, then start the flow if the core is idle
    irq_enable_src(u->irq_src_tx);
    uart_it_tx_kick(u);
    return 0;
}

int uart_receive_it(uart_t *u, uint8_t *buf, uint16_t size)
{
    uint32_t key;

    if (u->rx_ring == 0)
        return -1;

    key = irq_global_save();
    if (u->rx_active) {
        irq_global_restore(key);
        return -1;
    }
    u->rx_active_buf  = buf;
    u->rx_active_len  = size;
    u->rx_active_idx  = 0;
    u->rx_active      = 1;
    irq_global_restore(key);

    // ensure the RX interrupt is live (it may have been disabled after a
    // previous receive completed)
    irq_enable_src(u->irq_src_rx);
    return 0;
}

void uart_it_putc(uart_t *u, char c)
{
    uint32_t key;

    if (u->tx_ring == 0) {          // fall back to polling
        uart_putc(u, c);
        return;
    }

    for (;;) {
        uint16_t free = (u->tx_ring_size - 1u) -
                        (uint16_t)((u->tx_head - u->tx_tail) % u->tx_ring_size);
        if (free > 0)
            break;
    }
    key = irq_global_save();
    u->tx_ring[u->tx_head] = (uint8_t)c;
    u->tx_head = (uint16_t)((u->tx_head + 1) % u->tx_ring_size);
    if (!u->tx_active) {
        u->tx_active = 1;
        irq_global_restore(key);
        irq_enable_src(u->irq_src_tx);
        uart_it_tx_kick(u);
        return;
    }
    irq_global_restore(key);
}

uint16_t uart_tx_pending(const uart_t *u)
{
    return (uint16_t)((u->tx_head - u->tx_tail) % u->tx_ring_size);
}

uint16_t uart_rx_ready(const uart_t *u)
{
    return (uint16_t)((u->rx_head - u->rx_tail) % u->rx_ring_size);
}

int uart_rx_read(uart_t *u)
{
    int c = -1;

    if (u->rx_head != u->rx_tail) {
        c = u->rx_ring[u->rx_tail];
        u->rx_tail = (uint16_t)((u->rx_tail + 1) % u->rx_ring_size);
    }
    return c;
}

// ---------------------------------------------------------------------
// ISR entry points
// ---------------------------------------------------------------------

void uart_it_irq_rx(uart_t *u)
{
    // drain every byte currently available
    while (REG32(u->base + UART_STATUS) & UART_STATUS_RX_AVAIL) {
        uint8_t c = (uint8_t)REG32(u->base + UART_RXDATA);

        if (u->rx_active) {
            u->rx_active_buf[u->rx_active_idx++] = c;
            if (u->rx_active_idx >= u->rx_active_len) {
                u->rx_active = 0;
                irq_disable_src(u->irq_src_rx);
                uart_rx_cplt(u);
            }
        } else {
            uint16_t next = (uint16_t)((u->rx_head + 1) % u->rx_ring_size);
            if (next != u->rx_tail) {           // ring not full
                u->rx_ring[u->rx_head] = c;
                u->rx_head = next;
            }
        }
    }
}

void uart_it_irq_tx(uart_t *u)
{
    // TX-empty interrupt: feed the next byte (one per interrupt)
    if (!(REG32(u->base + UART_STATUS) & UART_STATUS_TX_PENDING)) {
        if (u->tx_head != u->tx_tail) {
            REG32(u->base + UART_TXDATA) = u->tx_ring[u->tx_tail];
            u->tx_tail = (uint16_t)((u->tx_tail + 1) % u->tx_ring_size);
        } else if (u->tx_active) {
            u->tx_active = 0;
            irq_disable_src(u->irq_src_tx);
            uart_tx_cplt(u);
        }
    }
}

// ---------------------------------------------------------------------
// Weak callbacks
// ---------------------------------------------------------------------

__attribute__((weak)) void uart_tx_cplt(uart_t *u) { (void)u; }
__attribute__((weak)) void uart_rx_cplt(uart_t *u) { (void)u; }
