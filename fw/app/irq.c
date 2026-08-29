// irq.c - PicoRV32 C interrupt handler (called from start.S irq_vec)
#include "soc_addr.h"
#include "timer.h"
#include "gpio.h"
#include "irq_ctrl.h"

volatile uint32_t irq_timer0_fired;
volatile uint32_t irq_gpio_fired;

uint32_t *irq(uint32_t *regs, uint32_t irq_num)
{
    uint16_t pend;

    (void)irq_num;
    pend = irq_get_pending();

    if (pend & (1u << IRQ_SRC_TIMER0)) {
        timer_irq_ack(TIMER0_BASE);
        irq_timer0_fired = 1;
    }
    if (pend & (1u << IRQ_SRC_GPIO)) {
        gpio_clear_ipr(GPIO_BASE, 0xFFFF);
        irq_gpio_fired = 1;
    }
    if (pend & (1u << IRQ_SRC_UART0_RX)) {
        (void)REG32(UART0_BASE + 0x04);   // drain RX byte
    }

    return regs;
}
