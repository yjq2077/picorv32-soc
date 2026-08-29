// gpio.h - APB GPIO driver (public interface)
#ifndef LIB_GPIO_H
#define LIB_GPIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void gpio_set_out(uint32_t base, uint16_t val);
uint16_t gpio_get_out(uint32_t base);
uint16_t gpio_get_in(uint32_t base);
void gpio_set_dir(uint32_t base, uint16_t dir);   // 1=output
void gpio_set_int_en(uint32_t base, uint16_t en);
uint16_t gpio_get_ipr(uint32_t base);             // latched rising-edge pending
void gpio_clear_ipr(uint32_t base, uint16_t mask); // write 1 to clear

#ifdef __cplusplus
}
#endif

#endif // LIB_GPIO_H
