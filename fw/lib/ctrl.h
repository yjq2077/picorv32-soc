// ctrl.h - APB general-purpose control register driver (public interface)
#ifndef LIB_CTRL_H
#define LIB_CTRL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// idx 0..2 maps to REG0..REG2; values are exported on soc_top ctrl0..ctrl2
// so the host / testbench can observe them.
void ctrl_set(uint32_t idx, uint32_t val);
uint32_t ctrl_get(uint32_t idx);
uint32_t ctrl_version(void);   // reads VERSION register

#ifdef __cplusplus
}
#endif

#endif // LIB_CTRL_H
