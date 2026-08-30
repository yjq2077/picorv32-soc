// riscv_cpu.h - PicoRV32 CPU-level helpers (global IRQ mask)
// PicoRV32 controls its interrupt gate through the custom maskirq
// instruction (bit n = 1 means irq line n is masked).  The assembly
// implementations live in riscv_cpu.S.
#ifndef LIB_RISCV_CPU_H
#define LIB_RISCV_CPU_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Set the PicoRV32 irq mask (1 = disabled for that irq line).
void picorv32_irq_mask(uint32_t mask);

// Return the current irq mask.
uint32_t picorv32_irq_get_mask(void);

// Convenience wrappers for critical sections (disable/enable all IRQs).
static inline uint32_t irq_global_save(void)
{
    uint32_t m = picorv32_irq_get_mask();
    picorv32_irq_mask(0xFFFFFFFFu);
    return m;
}

static inline void irq_global_restore(uint32_t m)
{
    picorv32_irq_mask(m);
}

// Unmask every IRQ line (normal operating state).
static inline void irq_global_enable(void)
{
    picorv32_irq_mask(0u);
}

#ifdef __cplusplus
}
#endif

#endif // LIB_RISCV_CPU_H
