// main.c - PicoRV32 SoC peripheral self-test application
// Exercises every peripheral through the lib/ driver library.
#include "soc_addr.h"
#include "print.h"
#include "uart.h"
#include "i2c.h"
#include "gpio.h"
#include "timer.h"
#include "irq_ctrl.h"
#include "ctrl.h"

#define UART_PRESCALE_VAL  2u
#define I2C_PRESCALE_VAL   1u
#define I2C_SLAVE_ADDR     0x50u

extern volatile uint32_t irq_timer0_fired;
extern volatile uint32_t irq_gpio_fired;

static int failures;

static void check(int ok, const char *name)
{
    if (ok)
        printf_("  [PASS] %s\n", name);
    else {
        printf_("  [FAIL] %s\n", name);
        failures++;
    }
}

// ---------------------------------------------------------------------
static void test_ctrl(void)
{
    printf_("ctrl.version   = 0x%08x\n", ctrl_version());

    ctrl_set(0, 0x11112222);
    ctrl_set(1, 0x33334444);
    ctrl_set(2, 0x55556666);
    check(ctrl_get(0) == 0x11112222, "ctrl0 rw");
    check(ctrl_get(1) == 0x33334444, "ctrl1 rw");
    check(ctrl_get(2) == 0x55556666, "ctrl2 rw");

    // boot_ctrl STATUS readback through the CPU port (trap must be 0)
    check((REG32(BOOT_STATUS) & 0x2) == 0, "cpu trap clear");
    check((REG32(BOOT_STATUS) & 0x1) == 1, "cpu running (reset released)");
}

// ---------------------------------------------------------------------
static void test_gpio(void)
{
    // all inputs: read the TB-driven pattern
    gpio_set_dir(GPIO_BASE, 0x0000);
    uint16_t in = gpio_get_in(GPIO_BASE);
    printf_("  gpio_in       = 0x%04x\n", in);
    check(in == 0x00AA, "gpio input (tb)");

    // all outputs: write + read back
    gpio_set_dir(GPIO_BASE, 0xFFFF);
    gpio_set_out(GPIO_BASE, 0x5A5A);
    check(gpio_get_out(GPIO_BASE) == 0x5A5A, "gpio output 0x5A5A");
    gpio_set_out(GPIO_BASE, 0xA5A5);
    check(gpio_get_out(GPIO_BASE) == 0xA5A5, "gpio output 0xA5A5");
    gpio_set_dir(GPIO_BASE, 0x0000);
}

// ---------------------------------------------------------------------
static void test_uart_tx(void)
{
    uart_t u;
    u.base = UART0_BASE;
    uart_puts(&u, "UART0 TX: Hello from PicoRV32 SoC! 0123456789 abcdef\n");

    uart_t u1;
    u1.base = UART1_BASE;
    uart_init(&u1, UART_PRESCALE_VAL);
    uart_puts(&u1, "UART1 TX: secondary serial port alive.\n");
}

// ---------------------------------------------------------------------
static void test_uart_rx(void)
{
    uart_t u;
    u.base = UART0_BASE;

    printf_("RXREADY");                       // TB marker -> sends 'A'
    char c = uart_getc(&u);
    printf_("\n  uart0 rx byte = 0x%02x '%c'\n",
            (unsigned char)c, (c >= 0x20 && c < 0x7f) ? c : '.');
    check(c == 'A', "uart0 rx");
}

// ---------------------------------------------------------------------
static void test_timer_poll(void)
{
    uint32_t spins = 0;

    timer_init(TIMER0_BASE, 1000, 0);          // one-shot
    timer_enable(TIMER0_BASE, 0);
    while (timer_get_count(TIMER0_BASE) != 0 && spins < 200000)
        spins++;
    timer_disable(TIMER0_BASE);
    check(spins < 200000, "timer0 one-shot expired");
}

// ---------------------------------------------------------------------
static void test_timer_irq(void)
{
    uint32_t spins = 0;

    irq_timer0_fired = 0;
    irq_set_enable(0);
    irq_set_master(0);

    timer_init(TIMER0_BASE, 500, 1);           // autoreload
    irq_enable_src(IRQ_SRC_TIMER0);
    irq_set_master(1);
    timer_enable(TIMER0_BASE, 1);

    while (!irq_timer0_fired && spins < 200000)
        spins++;

    timer_disable(TIMER0_BASE);
    irq_set_master(0);
    irq_set_enable(0);
    check(irq_timer0_fired != 0, "timer0 irq");
}

// ---------------------------------------------------------------------
static void test_gpio_irq(void)
{
    uint32_t spins = 0;

    irq_gpio_fired = 0;
    irq_set_enable(0);
    irq_set_master(0);

    gpio_set_dir(GPIO_BASE, 0x0000);
    gpio_clear_ipr(GPIO_BASE, 0xFFFF);
    printf_("GPIOIRQ");                        // TB marker -> toggles gpio_in[0]
    gpio_set_int_en(GPIO_BASE, 0x0001);
    irq_enable_src(IRQ_SRC_GPIO);
    irq_set_master(1);

    while (!irq_gpio_fired && spins < 200000)
        spins++;

    irq_set_master(0);
    irq_set_enable(0);
    gpio_set_int_en(GPIO_BASE, 0x0000);
    check(irq_gpio_fired != 0, "gpio irq");
}

// ---------------------------------------------------------------------
static void test_i2c(void)
{
    i2c_t i2c;
    uint8_t w[4] = { 0x00, 0xAA, 0xBB, 0xCC };
    uint8_t w1[1] = { 0x00 };
    uint8_t r[4] = { 0, 0, 0, 0 };
    int rc;

    i2c.base = I2C0_BASE;
    i2c.prescale = I2C_PRESCALE_VAL;
    i2c.timeout = 0;                            // infinite
    i2c_init(&i2c);

    rc = i2c_write(&i2c, I2C_SLAVE_ADDR, w, 4);
    printf_("  i2c write rc   = %d\n", rc);
    check(rc == I2C_OK, "i2c0 write");

    rc = i2c_write_read(&i2c, I2C_SLAVE_ADDR, w1, 1, r, 4);
    printf_("  i2c read rc    = %d  data = %02x %02x %02x %02x\n",
            rc, r[0], r[1], r[2], r[3]);
    check(rc == I2C_OK && r[0] == 0xAA && r[1] == 0xBB && r[2] == 0xCC,
          "i2c0 read back");
}

// ---------------------------------------------------------------------
int main(void)
{
    print_init(UART_PRESCALE_VAL);

    printf_("\n=== PicoRV32 SoC peripheral test ===\n");
    failures = 0;

    test_ctrl();
    test_gpio();
    test_uart_tx();
    test_uart_rx();
    test_timer_poll();
    test_timer_irq();
    test_gpio_irq();
    test_i2c();

    if (failures == 0) {
        printf_("RESULT: PASS\n");
        ctrl_set(1, 0x0000BEEF);
    } else {
        printf_("RESULT: FAIL (%d)\n", failures);
        ctrl_set(1, 0x0000DEAD);
    }

    while (1)
        ;
    return 0;
}
