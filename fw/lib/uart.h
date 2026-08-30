// uart.h - AXI-Lite UART driver (public interface)
// Implements the register protocol of uart_axil.v (rtl/uart_axil.v).
//
// Two usage models:
//   - Blocking (polling): uart_init / uart_putc / uart_getc ...
//   - Interrupt-driven (STM32-HAL style): uart_it_init /
//     uart_transmit_it / uart_receive_it with uart_tx_cplt /
//     uart_rx_cplt callbacks.  The ISR entry points uart_it_irq_rx()
//     and uart_it_irq_tx() must be called from the SoC irq handler.
#ifndef LIB_UART_H
#define LIB_UART_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t base;         // one of UART0_BASE / UART1_BASE
    uint16_t prescale;     // clk_hz / (8 * baud)

    // --- interrupt-driven TX (ring buffer) ---
    volatile uint8_t  *tx_ring;
    volatile uint16_t  tx_head;      // producer index (thread)
    volatile uint16_t  tx_tail;      // consumer index (ISR)
    uint16_t           tx_ring_size;
    volatile int       tx_active;    // a transmit is in flight

    // --- interrupt-driven RX (background ring + active receive) ---
    volatile uint8_t  *rx_ring;
    volatile uint16_t  rx_head;      // producer index (ISR)
    volatile uint16_t  rx_tail;      // consumer index (thread)
    uint16_t           rx_ring_size;
    volatile uint8_t  *rx_active_buf;  // target of uart_receive_it
    volatile uint16_t  rx_active_len;
    volatile uint16_t  rx_active_idx;
    volatile int       rx_active;

    // irq_ctrl source indices assigned to this UART
    uint8_t            irq_src_rx;   // e.g. IRQ_SRC_UART0_RX
    uint8_t            irq_src_tx;   // e.g. IRQ_SRC_UART0_TX
} uart_t;

// ---- blocking (polling) API ----

// Init UART: configure baud prescale.
void uart_init(uart_t *u, uint16_t prescale);

// Transmit one byte (blocking until the TX buffer accepts it).
void uart_putc(uart_t *u, char c);

// Transmit a NUL-terminated string (blocking).
void uart_puts(uart_t *u, const char *s);

// Non-blocking RX check.
int uart_rx_avail(const uart_t *u);

// Receive one byte (blocking until a byte arrives).
char uart_getc(uart_t *u);

// 1 while the TX shift register / buffer still holds a byte.
int uart_tx_busy(const uart_t *u);

// Raw status word.
uint32_t uart_status(const uart_t *u);

// ---- interrupt-driven API (STM32-HAL style) ----

// Attach ring buffers and irq_ctrl source indices, then enable the
// background RX ring (RX IRQ source).  Call once per UART.
// Returns 0 on success, -1 if the UART is already in IT mode.
int uart_it_init(uart_t *u, uint16_t prescale,
                 uint8_t *tx_ring, uint16_t tx_ring_size,
                 uint8_t *rx_ring, uint16_t rx_ring_size,
                 uint8_t irq_src_rx, uint8_t irq_src_tx);

// Start an asynchronous transmit of `size` bytes (copy into TX ring and
// enable the TX-empty interrupt).  Returns 0 on success, -1 if busy or
// the ring is too small.  Completion reported via uart_tx_cplt().
int uart_transmit_it(uart_t *u, const uint8_t *data, uint16_t size);

// Start an asynchronous receive of exactly `size` bytes into `buf`.
// Returns 0 on success, -1 if a receive is already active.
// Completion reported via uart_rx_cplt().
int uart_receive_it(uart_t *u, uint8_t *buf, uint16_t size);

// Low-level single-byte TX for the console: pushes one byte into the TX
// ring (enabling the TX IRQ if needed) and blocks while the ring is
// full.  Fully interrupt-driven on the output path.
void uart_it_putc(uart_t *u, char c);

// Number of bytes currently queued in the TX ring.
uint16_t uart_tx_pending(const uart_t *u);

// Number of bytes available in the RX background ring.
uint16_t uart_rx_ready(const uart_t *u);

// Pop one byte from the RX background ring (or -1 if empty).
int uart_rx_read(uart_t *u);

// ISR entry points: call from the SoC interrupt handler on the
// corresponding irq_ctrl source.
void uart_it_irq_rx(uart_t *u);
void uart_it_irq_tx(uart_t *u);

// Completion callbacks (weak, override in the application).
void uart_tx_cplt(uart_t *u);
void uart_rx_cplt(uart_t *u);

#ifdef __cplusplus
}
#endif

#endif // LIB_UART_H
