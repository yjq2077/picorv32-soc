// irq_ctrl.h - SoC interrupt controller driver (public interface)
#ifndef LIB_IRQ_CTRL_H
#define LIB_IRQ_CTRL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Enable/disable individual sources in the 16-bit IER mask.
void irq_set_enable(uint16_t en);
void irq_enable_src(uint32_t bit);
void irq_disable_src(uint32_t bit);

// Pending sources: (irq_src & IER) as a 16-bit mask.
uint16_t irq_get_pending(void);

// Master enable: 0 blocks the combined interrupt output.
void irq_set_master(int en);

#ifdef __cplusplus
}
#endif

#endif // LIB_IRQ_CTRL_H
