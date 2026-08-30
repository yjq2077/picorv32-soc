// irq.c - PicoRV32 SoC interrupt dispatcher (RT-Thread)
// Called from start.S irq_vec with regs = &irq_regs and irq_num = the CPU
// irq line (always the aggregated external line, 5).  The actual peripheral
// source is decoded from the irq_ctrl pending register (IPR).  All CPU-level
// irq lines are masked on entry (start.S), so the handler is non-nesting.
#include <rthw.h>
#include <rtthread.h>
#include "cpuport.h"
#include "soc_addr.h"
#include "irq_ctrl.h"
#include "timer.h"
#include "gpio.h"
#include "board.h"

extern struct rt_semaphore g_gpio_irq_sem;

uint32_t *irq(uint32_t *regs, uint32_t irq_num)
{
    uint16_t pend;

    (void)irq_num;
    rt_interrupt_enter();
    pend = irq_get_pending();

    // UART RX / TX (interrupt-driven ring buffers)
    if (pend & (1u << IRQ_SRC_UART0_RX))
        uart_it_irq_rx(&uart0_inst);
    if (pend & (1u << IRQ_SRC_UART0_TX))
        uart_it_irq_tx(&uart0_inst);
    if (pend & (1u << IRQ_SRC_UART1_RX))
        uart_it_irq_rx(&uart1_inst);
    if (pend & (1u << IRQ_SRC_UART1_TX))
        uart_it_irq_tx(&uart1_inst);

    // OS tick (TIMER0); rt_tick_increase may request a context switch
    if (pend & (1u << IRQ_SRC_TIMER0)) {
        timer_irq_ack(TIMER0_BASE);
        rt_tick_increase();
    }

    // GPIO rising-edge interrupt
    if (pend & (1u << IRQ_SRC_GPIO)) {
        gpio_clear_ipr(GPIO_BASE, 0xFFFF);
        rt_sem_release(&g_gpio_irq_sem);
    }

    rt_interrupt_leave();

    // perform a context switch if rt_schedule() (from the ISR) requested one;
    // skip the epilogue call entirely in the common no-switch case
    if (!rt_thread_switch_interrupt_flag)
        return regs;
    return rt_hw_irq_handle_switch(regs);
}
