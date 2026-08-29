// timer.c - APB down-counter timer driver implementation
#include "timer.h"
#include "soc_addr.h"

#define OFF_CTRL    0x00
#define OFF_RELOAD  0x04
#define OFF_COUNT   0x08
#define OFF_IACK    0x0C

void timer_init(uint32_t base, uint32_t reload, int autoreload)
{
    REG32(base + OFF_CTRL) = autoreload ? TIMER_CTRL_AUTORELOAD : 0;
    REG32(base + OFF_RELOAD) = reload;
    REG32(base + OFF_IACK) = 1;   // clear any stale pending flag
}

void timer_enable(uint32_t base, int irq_en)
{
    uint32_t c = REG32(base + OFF_CTRL);
    if (irq_en) c |= TIMER_CTRL_IRQ_EN; else c &= ~TIMER_CTRL_IRQ_EN;
    c |= TIMER_CTRL_ENABLE;
    REG32(base + OFF_CTRL) = c;
}

void timer_disable(uint32_t base)
{
    uint32_t c = REG32(base + OFF_CTRL);
    REG32(base + OFF_CTRL) = c & ~TIMER_CTRL_ENABLE;
}

uint32_t timer_get_count(uint32_t base)
{
    return REG32(base + OFF_COUNT);
}

uint32_t timer_get_reload(uint32_t base)
{
    return REG32(base + OFF_RELOAD);
}

void timer_irq_ack(uint32_t base)
{
    REG32(base + OFF_IACK) = 1;
}
