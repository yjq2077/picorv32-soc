/*
 * board.c - PicoRV32 SoC board support for RT-Thread Nano
 *
 * Console UART0 and the secondary UART1 run in interrupt-driven mode
 * (uart_it_init).  TIMER0 drives the 1 kHz OS tick; it is started with the
 * irq master gate by board_tick_start() right before the scheduler runs.
 */
#include <rtthread.h>
#include <rthw.h>
#include "board.h"
#include "soc_addr.h"
#include "irq_ctrl.h"
#include "timer.h"
#include "print.h"

#define UART_PRESCALE_VAL   2u
#define TICK_RELOAD         99999u   /* 100MHz / 1000Hz - 1 */

uart_t uart0_inst = { .base = UART0_BASE, .prescale = UART_PRESCALE_VAL };
uart_t uart1_inst = { .base = UART1_BASE, .prescale = UART_PRESCALE_VAL };

static uint8_t console_tx_ring[64];
static uint8_t console_rx_ring[16];
static uint8_t uart1_tx_ring[64];
static uint8_t uart1_rx_ring[16];

/* console uses blocking output until the OS tick / IRQ path is live */
static volatile int console_it_ready;

void board_tick_start(void)
{
    timer_init(TIMER0_BASE, TICK_RELOAD, 1);   /* autoreload */
    irq_enable_src(IRQ_SRC_TIMER0);
    irq_set_master(1);
    timer_enable(TIMER0_BASE, 1);
    console_it_ready = 1;
}

void rt_hw_board_init(void)
{
    uart_it_init(&uart0_inst, UART_PRESCALE_VAL,
                 console_tx_ring, sizeof(console_tx_ring),
                 console_rx_ring, sizeof(console_rx_ring),
                 IRQ_SRC_UART0_RX, IRQ_SRC_UART0_TX);
    uart_it_init(&uart1_inst, UART_PRESCALE_VAL,
                 uart1_tx_ring, sizeof(uart1_tx_ring),
                 uart1_rx_ring, sizeof(uart1_rx_ring),
                 IRQ_SRC_UART1_RX, IRQ_SRC_UART1_TX);

    /* keep the IER bits set by uart_it_init (UART RX sources); the master
     * gate stays off until the scheduler starts (board_tick_start) */
    irq_set_master(0);
}

void rt_hw_console_output(const char *str)
{
    while (*str) {
        if (console_it_ready)
            putchar_(*str);              /* interrupt-driven path */
        else
            uart_putc(&uart0_inst, *str); /* boot banner: IRQs not yet on */
        str++;
    }
}

void rt_hw_us_delay(rt_uint32_t us)
{
    volatile rt_uint32_t n = us * 100;   /* ~100 cycles/us @ 100 MHz */
    while (n--)
        ;
}
