// gpio.c - APB GPIO driver implementation
#include "gpio.h"
#include "soc_addr.h"

// register offsets (base = GPIO_BASE = 0x50000000)
#define OFF_OUT     0x00
#define OFF_IN      0x04
#define OFF_DIR     0x08
#define OFF_INT_EN  0x0C
#define OFF_IPR     0x10
#define OFF_IC      0x14

void gpio_set_out(uint32_t base, uint16_t val)
{
    REG32(base + OFF_OUT) = val;
}

uint16_t gpio_get_out(uint32_t base)
{
    return (uint16_t)REG32(base + OFF_OUT);
}

uint16_t gpio_get_in(uint32_t base)
{
    return (uint16_t)REG32(base + OFF_IN);
}

void gpio_set_dir(uint32_t base, uint16_t dir)
{
    REG32(base + OFF_DIR) = dir;
}

void gpio_set_int_en(uint32_t base, uint16_t en)
{
    REG32(base + OFF_INT_EN) = en;
}

uint16_t gpio_get_ipr(uint32_t base)
{
    return (uint16_t)REG32(base + OFF_IPR);
}

void gpio_clear_ipr(uint32_t base, uint16_t mask)
{
    REG32(base + OFF_IC) = mask;
}
