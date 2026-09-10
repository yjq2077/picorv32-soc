// soc_addr.h - PicoRV32 SoC memory map / register definitions
// This header is shared by the peripheral library (lib) and the APP.
// It must stay in sync with soc_top.v in ../rtl/

#ifndef SOC_ADDR_H
#define SOC_ADDR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// AXI-Lite slave regions (see soc_top.v address map comment)
// Compact map: all within 2 MB, one 64 KB (0x10000) window per port
#define RAM_BASE        0x00000000UL
#define BOOT_BASE       0x00010000UL
#define IRQ_BASE        0x00020000UL
#define I2C0_BASE       0x00030000UL
#define I2C1_BASE       0x00040000UL
#define I2C2_BASE       0x00050000UL
#define I2C3_BASE       0x00060000UL
#define UART0_BASE      0x00070000UL
#define UART1_BASE      0x00080000UL
#define APB0_BASE       0x00090000UL
#define APB1_BASE       0x000A0000UL

// APB0 slaves:  GPIO @ +0x0000, TIMER0 @ +0x1000
#define GPIO_BASE       (APB0_BASE + 0x0000UL)
#define TIMER0_BASE     (APB0_BASE + 0x1000UL)

// APB1 slaves:  CTRL @ +0x0000, TIMER1 @ +0x1000
#define CTRL_BASE       (APB1_BASE + 0x0000UL)
#define TIMER1_BASE     (APB1_BASE + 0x1000UL)

// boot_ctrl registers (0x00010000)
#define BOOT_CTRL       (BOOT_BASE + 0x00UL)   // RW bit0 = cpu_resetn
#define BOOT_STATUS     (BOOT_BASE + 0x04UL)   // RO bit0=cpu_resetn, bit1=cpu_trap
#define BOOT_APB0_BASE  (BOOT_BASE + 0x08UL)   // RW APB0 window base (0 = fixed default)
#define BOOT_APB1_BASE  (BOOT_BASE + 0x0CUL)   // RW APB1 window base (0 = fixed default)

// irq_ctrl registers (0x00020000)
#define IRQ_IER         (IRQ_BASE + 0x00UL)   // RW [15:0] interrupt enable
#define IRQ_IPR         (IRQ_BASE + 0x04UL)   // RO [15:0] pending = irq_src & IER
#define IRQ_MER         (IRQ_BASE + 0x08UL)   // RW [0]    master enable

// Interrupt source indices (into IER/IPR)
#define IRQ_SRC_UART0_RX  0
#define IRQ_SRC_UART0_TX  1
#define IRQ_SRC_UART1_RX  2
#define IRQ_SRC_UART1_TX  3
#define IRQ_SRC_TIMER0    4
#define IRQ_SRC_TIMER1    5
#define IRQ_SRC_GPIO      6

// uart_axil registers (offset within each UART block)
#define UART_TXDATA     0x00UL   // WO
#define UART_RXDATA     0x04UL   // RO
#define UART_STATUS     0x08UL   // RO
#define UART_PRESCALE   0x0CUL   // RW [15:0]
#define UART_STATUS_TX_PENDING (1u << 0)
#define UART_STATUS_RX_AVAIL   (1u << 1)
#define UART_STATUS_RX_OVERRUN (1u << 2)
#define UART_STATUS_RX_FRAME   (1u << 3)

// i2c_master_axil registers (offset within each I2C block)
#define I2C_STATUS      0x00UL
#define I2C_COMMAND     0x04UL
#define I2C_DATA        0x08UL
#define I2C_PRESCALE    0x0CUL

#define I2C_STATUS_BUSY       (1u << 0)
#define I2C_STATUS_BUS_CONT   (1u << 1)
#define I2C_STATUS_BUS_ACT    (1u << 2)
#define I2C_STATUS_MISS_ACK   (1u << 3)
#define I2C_STATUS_CMD_EMPTY  (1u << 8)
#define I2C_STATUS_CMD_FULL   (1u << 9)
#define I2C_STATUS_CMD_OVF    (1u << 10)
#define I2C_STATUS_WR_EMPTY   (1u << 11)
#define I2C_STATUS_WR_FULL    (1u << 12)
#define I2C_STATUS_WR_OVF     (1u << 13)
#define I2C_STATUS_RD_EMPTY   (1u << 14)
#define I2C_STATUS_RD_FULL    (1u << 15)

// bit8=start, bit9=read, bit10=write, bit11=write_multiple, bit12=stop
#define I2C_COMMAND_START     (1u << 8)
#define I2C_COMMAND_READ      (1u << 9)
#define I2C_COMMAND_WRITE     (1u << 10)
#define I2C_COMMAND_WR_MULTI  (1u << 11)
#define I2C_COMMAND_STOP      (1u << 12)

// bit8=data_valid, bit9=data_last (atomic 16-bit write for write_multiple)
#define I2C_DATA_VALID        (1u << 8)
#define I2C_DATA_LAST         (1u << 9)

// apb_gpio registers (0x00090000)
#define GPIO_OUT        (GPIO_BASE + 0x00UL)
#define GPIO_IN         (GPIO_BASE + 0x04UL)
#define GPIO_DIR        (GPIO_BASE + 0x08UL)
#define GPIO_INT_EN     (GPIO_BASE + 0x0CUL)
#define GPIO_IPR        (GPIO_BASE + 0x10UL)
#define GPIO_IC         (GPIO_BASE + 0x14UL)

// apb_timer registers (0x00091000 / 0x000A1000)
#define TIMER_CTRL      (TIMER_BASE + 0x00UL)
#define TIMER_RELOAD    (TIMER_BASE + 0x04UL)
#define TIMER_COUNT     (TIMER_BASE + 0x08UL)
#define TIMER_IACK      (TIMER_BASE + 0x0CUL)
#define TIMER_CTRL_ENABLE     (1u << 0)
#define TIMER_CTRL_IRQ_EN     (1u << 1)
#define TIMER_CTRL_AUTORELOAD (1u << 2)

// apb_ctrl registers (0x000A0000)
#define CTRL_REG0       (CTRL_BASE + 0x00UL)
#define CTRL_REG1       (CTRL_BASE + 0x04UL)
#define CTRL_REG2       (CTRL_BASE + 0x08UL)
#define CTRL_VERSION    (CTRL_BASE + 0x0CUL)

// MMIO accessor
#define REG32(addr) (*(volatile uint32_t *)(addr))
#define REG8(addr)  (*(volatile uint8_t  *)(addr))

#ifdef __cplusplus
}
#endif

#endif // SOC_ADDR_H
