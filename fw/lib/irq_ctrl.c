// irq_ctrl.c - SoC interrupt controller driver implementation
#include "irq_ctrl.h"
#include "soc_addr.h"

void irq_set_enable(uint16_t en)
{
    REG32(IRQ_IER) = en;
}

void irq_enable_src(uint32_t bit)
{
    uint32_t v = REG32(IRQ_IER);
    REG32(IRQ_IER) = v | (1u << bit);
}

void irq_disable_src(uint32_t bit)
{
    uint32_t v = REG32(IRQ_IER);
    REG32(IRQ_IER) = v & ~(1u << bit);
}

uint16_t irq_get_pending(void)
{
    return (uint16_t)REG32(IRQ_IPR);
}

void irq_set_master(int en)
{
    REG32(IRQ_MER) = en ? 1 : 0;
}
