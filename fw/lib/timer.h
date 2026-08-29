// timer.h - APB down-counter timer driver (public interface)
#ifndef LIB_TIMER_H
#define LIB_TIMER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Set reload value and configure mode. autoreload!=0 -> periodic.
void timer_init(uint32_t base, uint32_t reload, int autoreload);

// Enable counting; if irq_en, assert the timer irq line on zero.
void timer_enable(uint32_t base, int irq_en);

// Disable counting (one-shot runs will stop at zero).
void timer_disable(uint32_t base);

uint32_t timer_get_count(uint32_t base);
uint32_t timer_get_reload(uint32_t base);

// Clear the pending interrupt flag.
void timer_irq_ack(uint32_t base);

#ifdef __cplusplus
}
#endif

#endif // LIB_TIMER_H
