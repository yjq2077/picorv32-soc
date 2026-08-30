#!/bin/bash
echo "=== soc_addr.h UART defines ==="
grep -nE "UART_STATUS|UART_TXDATA|UART_PRESCALE|UART_RXDATA|TX_PENDING|RX_AVAIL|UART0_BASE|UART1_BASE|IRQ_SRC" /home/jiaqi/picorv32-soc/fw/lib/soc_addr.h
echo
echo "=== uart_axil.v register & irq ==="
grep -nE "prescale|TX_PENDING|tx_pending|TXDATA|STATUS|interrupt|irq|S_AXIL" /home/jiaqi/picorv32-soc/rtl/third_party/verilog-uart/rtl/uart_axil.v | head -60
