// i2c.h - I2C master driver over AXI-Lite (public interface)
// Implements the register protocol of alexforencich's i2c_master_axil.
#ifndef LIB_I2C_H
#define LIB_I2C_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Wait forever while the module reports busy / FIFOs are full.
#define I2C_POLL_INFINITE  0u

// Result codes
#define I2C_OK      0
#define I2C_NACK   -1
#define I2C_TIMEOUT -2

typedef struct {
    uint32_t base;         // one of I2C0_BASE..I2C3_BASE
    uint16_t prescale;     // clk_hz / (i2c_clk_hz * 4)
    uint32_t timeout;      // poll iterations, 0 = infinite
} i2c_t;

// Init I2C master: set prescale, clear stale error flags.
void i2c_init(i2c_t *i);

// Write len bytes to 7-bit slave address. Returns I2C_OK / I2C_NACK / I2C_TIMEOUT.
int i2c_write(i2c_t *i, uint8_t addr, const uint8_t *data, uint32_t len);

// Read len bytes from 7-bit slave address. Returns I2C_OK / I2C_NACK / I2C_TIMEOUT.
int i2c_read(i2c_t *i, uint8_t addr, uint8_t *data, uint32_t len);

// Combined: write then (repeated) start then read.
int i2c_write_read(i2c_t *i, uint8_t addr,
                   const uint8_t *wdata, uint32_t wlen,
                   uint8_t *rdata, uint32_t rlen);

// Check if the module is idle (no transaction in progress).
int i2c_busy(const i2c_t *i);

#ifdef __cplusplus
}
#endif

#endif // LIB_I2C_H
