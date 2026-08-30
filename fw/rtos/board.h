/*
 * board.h - PicoRV32 SoC board support for RT-Thread Nano
 */
#ifndef BOARD_H__
#define BOARD_H__

#include <rtthread.h>
#include "uart.h"

/* Global UART instances (console + IRQ dispatch) */
extern uart_t uart0_inst;
extern uart_t uart1_inst;

/* Board-level init: console UART in interrupt mode */
void rt_hw_board_init(void);

/* Start the OS tick (TIMER0). Call after rt_system_scheduler_init(). */
void board_tick_start(void);

#endif /* BOARD_H__ */
