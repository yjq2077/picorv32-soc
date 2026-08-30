// main.c - PicoRV32 SoC peripheral tests running as RT-Thread tasks
//
// 8 tasks: ctrl / gpio / uarttx / uartrx / timer / gpioirq / i2c run the
// peripheral tests once each (interrupt-driven where possible), then park.
// A lowest-priority "report" task waits on a counting semaphore for all
// 7 tests, then flags the result to the testbench via ctrl1 (0xBEEF/0xDEAD).
#include <rthw.h>
#include <rtthread.h>
#include "board.h"
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

#define NUM_TESTS   7
#define THREAD_STACK_SIZE   1024

// semaphores (g_gpio_irq_sem is also referenced from irq.c)
static struct rt_semaphore done_sem;
static struct rt_semaphore rx_sem;     // uart0 receive_it complete
static struct rt_semaphore tx1_sem;    // uart1 transmit_it complete
struct rt_semaphore g_gpio_irq_sem;

static int failures;

// ---- STM32-HAL style UART completion callbacks (ISR context) ----
void uart_tx_cplt(uart_t *u)
{
    if (u == &uart1_inst)
        rt_sem_release(&tx1_sem);
}

void uart_rx_cplt(uart_t *u)
{
    if (u == &uart0_inst)
        rt_sem_release(&rx_sem);
}

// ---- common helpers ----
static void check(int ok, const char *name)
{
    rt_base_t level;

    if (ok) {
        printf_("  [PASS] %s\n", name);
    } else {
        printf_("  [FAIL] %s\n", name);
        level = rt_hw_interrupt_disable();
        failures++;
        rt_hw_interrupt_enable(level);
    }
}

// suspend the current thread permanently (one-shot task)
static void task_park(void)
{
    rt_thread_suspend(rt_thread_self());
    rt_schedule();
    for (;;)
        ;
}

#define TEST_DONE()  do { rt_sem_release(&done_sem); task_park(); } while (0)

// ---- test tasks ----
static void task_ctrl(void *param)
{
    (void)param;
    printf_("task ctrl: control registers\n");
    printf_("  ctrl.version   = 0x%08x\n", ctrl_version());

    ctrl_set(0, 0x11112222);
    ctrl_set(1, 0x33334444);
    ctrl_set(2, 0x55556666);
    check(ctrl_get(0) == 0x11112222, "ctrl0 rw");
    check(ctrl_get(1) == 0x33334444, "ctrl1 rw");
    check(ctrl_get(2) == 0x55556666, "ctrl2 rw");

    // boot_ctrl STATUS readback through the CPU port
    check((REG32(BOOT_STATUS) & 0x2) == 0, "cpu trap clear");
    check((REG32(BOOT_STATUS) & 0x1) == 1, "cpu running (reset released)");
    TEST_DONE();
}

static void task_gpio(void *param)
{
    (void)param;
    printf_("task gpio: GPIO\n");
    gpio_set_dir(GPIO_BASE, 0x0000);
    uint16_t in = gpio_get_in(GPIO_BASE);
    printf_("  gpio_in       = 0x%04x\n", in);
    check(in == 0x00AA, "gpio input (tb)");

    gpio_set_dir(GPIO_BASE, 0xFFFF);
    gpio_set_out(GPIO_BASE, 0x5A5A);
    check(gpio_get_out(GPIO_BASE) == 0x5A5A, "gpio output 0x5A5A");
    gpio_set_out(GPIO_BASE, 0xA5A5);
    check(gpio_get_out(GPIO_BASE) == 0xA5A5, "gpio output 0xA5A5");
    gpio_set_dir(GPIO_BASE, 0x0000);
    TEST_DONE();
}

static void task_uarttx(void *param)
{
    static const char msg0[] = "UART0 TX: Hello from PicoRV32 SoC! 0123456789 abcdef\n";
    static const char msg1[] = "UART1 TX: interrupt-driven secondary serial port alive.\n";
    int rc;

    (void)param;
    printf_("task uarttx: interrupt-driven TX\n");
    printf_("%s", msg0);                // console: TX ring + TX IRQ

    // async transmit on UART1 (completion via uart_tx_cplt -> tx1_sem)
    rc = uart_transmit_it(&uart1_inst, (const uint8_t *)msg1, sizeof(msg1) - 1);
    check(rc == 0, "uart1 transmit_it start");
    if (rc == 0) {
        rt_sem_take(&tx1_sem, RT_WAITING_FOREVER);
        check(1, "uart1 transmit_it complete (IRQ)");
    }
    TEST_DONE();
}

static void task_uartrx(void *param)
{
    uint8_t c = 0;
    int rc;

    (void)param;
    printf_("task uartrx: interrupt-driven RX\n");
    printf_("RXREADY");                 // TB marker -> sends 'A'
    rc = uart_receive_it(&uart0_inst, &c, 1);
    check(rc == 0, "uart0 receive_it start");
    if (rc == 0) {
        rt_sem_take(&rx_sem, RT_WAITING_FOREVER);   // released by uart_rx_cplt
        printf_("\n  uart0 rx byte = 0x%02x '%c'\n", c,
                (c >= 0x20 && c < 0x7f) ? c : '.');
        check(c == 'A', "uart0 rx (IRQ)");
    } else {
        printf_("\n");
    }
    TEST_DONE();
}

static void task_timer(void *param)
{
    uint32_t spins = 0;
    rt_tick_t t0, t1;

    (void)param;
    printf_("task timer: TIMER1 one-shot + OS tick\n");

    // OS tick sanity: sleeping 10 ms must advance the tick counter
    t0 = rt_tick_get();
    rt_thread_mdelay(10);
    t1 = rt_tick_get();
    printf_("  rt_tick  %u -> %u\n", (unsigned)t0, (unsigned)t1);
    check((t1 - t0) >= 8, "os tick advances (mdelay 10ms)");

    // TIMER1 one-shot: count reaches zero and stays there
    timer_init(TIMER1_BASE, 1000, 0);
    timer_enable(TIMER1_BASE, 0);
    while (timer_get_count(TIMER1_BASE) != 0 && spins < 200000)
        spins++;
    timer_disable(TIMER1_BASE);
    check(spins < 200000, "timer1 one-shot expired");
    TEST_DONE();
}

static void task_gpioirq(void *param)
{
    (void)param;
    printf_("task gpioirq: GPIO interrupt\n");
    gpio_set_dir(GPIO_BASE, 0x0000);
    gpio_clear_ipr(GPIO_BASE, 0xFFFF);
    printf_("GPIOIRQ");                 // TB marker -> toggles gpio_in[0]
    gpio_set_int_en(GPIO_BASE, 0x0001);
    irq_enable_src(IRQ_SRC_GPIO);
    rt_sem_take(&g_gpio_irq_sem, RT_WAITING_FOREVER);   // released by irq()
    gpio_set_int_en(GPIO_BASE, 0x0000);
    irq_disable_src(IRQ_SRC_GPIO);
    check(1, "gpio irq (IRQ)");
    TEST_DONE();
}

static void task_i2c(void *param)
{
    // I2C stays polling: i2c_master_axil.v has no interrupt output (AXI-Lite
    // slave + I2C pins only), so there is no IRQ source to wire to irq_ctrl.
    i2c_t i2c;
    uint8_t w[4]  = { 0x00, 0xAA, 0xBB, 0xCC };
    uint8_t w1[1] = { 0x00 };
    uint8_t r[4]  = { 0, 0, 0, 0 };
    int rc;

    (void)param;
    printf_("task i2c: I2C0 eeprom\n");
    i2c.base = I2C0_BASE;
    i2c.prescale = I2C_PRESCALE_VAL;
    i2c.timeout = 0;
    i2c_init(&i2c);

    rc = i2c_write(&i2c, I2C_SLAVE_ADDR, w, 4);
    printf_("  i2c write rc   = %d\n", rc);
    check(rc == I2C_OK, "i2c0 write");

    rc = i2c_write_read(&i2c, I2C_SLAVE_ADDR, w1, 1, r, 4);
    printf_("  i2c read rc    = %d  data = %02x %02x %02x %02x\n",
            rc, r[0], r[1], r[2], r[3]);
    check(rc == I2C_OK && r[0] == 0xAA && r[1] == 0xBB && r[2] == 0xCC,
          "i2c0 read back");
    TEST_DONE();
}

// ---- report task: wait for all tests, then flag the result ----
static void task_report(void *param)
{
    int i;

    (void)param;
    for (i = 0; i < NUM_TESTS; i++)
        rt_sem_take(&done_sem, RT_WAITING_FOREVER);

    rt_kprintf("=== PicoRV32 SoC RT-Thread test complete ===\n");
    if (failures == 0) {
        rt_kprintf("RESULT: PASS\n");
        ctrl_set(1, 0x0000BEEF);
    } else {
        rt_kprintf("RESULT: FAIL (%d)\n", failures);
        ctrl_set(1, 0x0000DEAD);
    }
    task_park();
}

// ---- thread objects & stacks ----
static struct rt_thread test_threads[NUM_TESTS + 1];
static rt_uint8_t       test_stacks[NUM_TESTS + 1][THREAD_STACK_SIZE];

static void create_task(int idx, const char *name, void (*entry)(void *),
                        rt_uint8_t prio)
{
    rt_thread_init(&test_threads[idx], name, entry, RT_NULL,
                   &test_stacks[idx][0], sizeof(test_stacks[idx]),
                   prio, 20);
    rt_thread_startup(&test_threads[idx]);
}

int main(void)
{
    // UART prescale must be configured before any console output, otherwise
    // the core transmits at prescale=0 and blocking uart_putc() hangs
    rt_hw_board_init();                 // UARTs in interrupt mode, IRQ gate off
    rt_system_scheduler_init();

    printf_("\n=== PicoRV32 SoC + RT-Thread ===\n");

    rt_sem_init(&done_sem, "done", 0, RT_IPC_FLAG_PRIO);
    rt_sem_init(&rx_sem,   "rx",   0, RT_IPC_FLAG_PRIO);
    rt_sem_init(&tx1_sem,  "tx1",  0, RT_IPC_FLAG_PRIO);
    rt_sem_init(&g_gpio_irq_sem, "gpioirq", 0, RT_IPC_FLAG_PRIO);

    create_task(0, "ctrl",   task_ctrl,   10);
    create_task(1, "gpio",   task_gpio,   11);
    create_task(2, "uarttx", task_uarttx, 12);
    create_task(3, "uartrx", task_uartrx, 13);
    create_task(4, "timer",  task_timer,  14);
    create_task(5, "gpioirq",task_gpioirq,15);
    create_task(6, "i2c",    task_i2c,    16);
    create_task(7, "report", task_report, 17);

    board_tick_start();                 // start TIMER0 tick, enable IRQ master
    rt_system_scheduler_start();        // never returns (unmasks CPU irqs)

    return 0;
}
