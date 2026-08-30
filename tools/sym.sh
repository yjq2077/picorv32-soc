#!/bin/bash
O=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump
cd /home/jiaqi/picorv32-soc/fw
echo "=== full symbol list ==="
"$O" -t fw.elf | sort -k1 | grep -E ' [0-9a-f]{8} [a-z] ' | grep -iE '0fc4|1acc|133c|putchar|printf|uart_it|irq|switch|board|main|thread|scheduler|console|ring|stack|irq_regs|uart0_inst|uart1_inst' | head -50
echo "=== 0x0fc4 exact ==="
"$O" -d fw.elf | grep -n '0fc4' | head
"$O" -d fw.elf | sed -n '/^00000fc4/,+14p'
