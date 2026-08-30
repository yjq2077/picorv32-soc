#!/bin/bash
O=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump
cd /home/jiaqi/picorv32-soc/fw
echo "=== 0x0fc4 context ==="
"$O" -d fw.elf | awk '/^00000fc4/{p=1} p{print; c++} c>14{exit}'
echo "=== 0x1ca8/0x1cdc context ==="
"$O" -d fw.elf | grep -B4 -A8 '1cdc:'
echo "=== uart_it_putc @0x133c ==="
"$O" -d fw.elf | awk '/^0000133c/{p=1} p{print; c++} c>40{exit}'
