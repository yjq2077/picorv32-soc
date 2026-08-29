// ctrl.c - APB general-purpose control register driver implementation
#include "ctrl.h"
#include "soc_addr.h"

void ctrl_set(uint32_t idx, uint32_t val)
{
    switch (idx) {
    case 0: REG32(CTRL_REG0) = val; break;
    case 1: REG32(CTRL_REG1) = val; break;
    case 2: REG32(CTRL_REG2) = val; break;
    default: break;
    }
}

uint32_t ctrl_get(uint32_t idx)
{
    switch (idx) {
    case 0: return REG32(CTRL_REG0);
    case 1: return REG32(CTRL_REG1);
    case 2: return REG32(CTRL_REG2);
    default: return 0;
    }
}

uint32_t ctrl_version(void)
{
    return REG32(CTRL_VERSION);
}
