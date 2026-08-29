// i2c.c - I2C master driver implementation (alexforencich i2c_master_axil)
#include "i2c.h"
#include "soc_addr.h"

static int poll_status(const i2c_t *i, uint32_t mask, uint32_t want)
{
    uint32_t n = 0;
    uint32_t st;
    do {
        st = REG32(i->base + I2C_STATUS);
        if (i->timeout && (++n > i->timeout))
            return I2C_TIMEOUT;
    } while ((st & mask) != want);
    return I2C_OK;
}

void i2c_init(i2c_t *i)
{
    REG32(i->base + I2C_PRESCALE) = i->prescale;
    // clear stale status/error bits (write-1-to-clear)
    REG32(i->base + I2C_STATUS) = I2C_STATUS_MISS_ACK |
                                  I2C_STATUS_CMD_OVF |
                                  I2C_STATUS_WR_OVF;
}

int i2c_busy(const i2c_t *i)
{
    return (REG32(i->base + I2C_STATUS) & I2C_STATUS_BUSY) ? 1 : 0;
}

// wait until the module drains its command + write FIFOs and goes idle
static int wait_idle(const i2c_t *i)
{
    int r = poll_status(i, I2C_STATUS_BUSY, 0);
    if (r != I2C_OK) return r;
    r = poll_status(i, I2C_STATUS_CMD_EMPTY | I2C_STATUS_WR_EMPTY,
                    I2C_STATUS_CMD_EMPTY | I2C_STATUS_WR_EMPTY);
    if (r != I2C_OK) return r;
    // flush the read FIFO if anything leaked in
    while (!(REG32(i->base + I2C_STATUS) & I2C_STATUS_RD_EMPTY))
        (void)REG32(i->base + I2C_DATA);
    return I2C_OK;
}

int i2c_write(i2c_t *i, uint8_t addr, const uint8_t *data, uint32_t len)
{
    uint32_t k;
    int r;

    if ((r = wait_idle(i)) != I2C_OK) return r;

    // command: start + write_multiple (block write of len bytes)
    REG32(i->base + I2C_COMMAND) = (addr & 0x7F) | I2C_COMMAND_START | I2C_COMMAND_WR_MULTI;

    for (k = 0; k < len; k++) {
        r = poll_status(i, I2C_STATUS_WR_FULL, 0);
        if (r != I2C_OK) return r;
        // atomic 16-bit write: data | (last << 9) on the final byte
        REG32(i->base + I2C_DATA) = data[k] | ((k == len - 1) ? I2C_DATA_LAST : 0);
    }

    r = wait_idle(i);
    if (r != I2C_OK) return r;

    if (REG32(i->base + I2C_STATUS) & I2C_STATUS_MISS_ACK) {
        // clear the sticky nack flag
        REG32(i->base + I2C_STATUS) = I2C_STATUS_MISS_ACK;
        return I2C_NACK;
    }
    return I2C_OK;
}

int i2c_read(i2c_t *i, uint8_t addr, uint8_t *data, uint32_t len)
{
    uint32_t k;
    int r;
    uint32_t w;

    if ((r = wait_idle(i)) != I2C_OK) return r;

    // command: read (one command per byte; start on first, stop on last)
    for (k = 0; k < len; k++) {
        uint32_t cmd = (addr & 0x7F) | I2C_COMMAND_READ;
        if (k == 0)
            cmd |= I2C_COMMAND_START;  // (repeated) start before first byte
        if (k == len - 1)
            cmd |= I2C_COMMAND_STOP;   // stop after final byte
        REG32(i->base + I2C_COMMAND) = cmd;

        r = poll_status(i, I2C_STATUS_RD_EMPTY, 0);
        if (r != I2C_OK) return r;

        w = REG32(i->base + I2C_DATA);
        data[k] = (uint8_t)w;
    }

    r = wait_idle(i);
    if (r != I2C_OK) return r;

    if (REG32(i->base + I2C_STATUS) & I2C_STATUS_MISS_ACK) {
        REG32(i->base + I2C_STATUS) = I2C_STATUS_MISS_ACK;
        return I2C_NACK;
    }
    return I2C_OK;
}

int i2c_write_read(i2c_t *i, uint8_t addr,
                   const uint8_t *wdata, uint32_t wlen,
                   uint8_t *rdata, uint32_t rlen)
{
    int r;

    if ((r = i2c_write(i, addr, wdata, wlen)) != I2C_OK) return r;

    // repeated start is automatic: master is idle+active, next read with
    // START re-issues a start condition to the same address
    return i2c_read(i, addr, rdata, rlen);
}
