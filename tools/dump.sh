#!/bin/bash
cd /home/jiaqi/picorv32-soc/fw
O=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump
N=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-nm
echo "=== raw bytes at 0x0fc0-0x0fe0 (little-endian words) ==="
"$O" -s fw.elf | awk '$1 ~ /^0fc[0-9a-f]0$|^0fc[0-9a-f]8$/ || $1 >= "0fc0" && $1 <= "0fe0"'
echo "=== sections ==="
/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump -h fw.elf | head -20
echo "=== irq / switch symbols ==="
"$N" -n fw.elf | grep -iE 'irq|switch|rt_hw_context|rt_interrupt|rt_schedule|rt_thread_switch|rt_hw_irq' | head -30
echo "=== disasm 0x0f00-0x0fd0 any lines ==="
"$O" -d fw.elf | awk '$1 >= "0f00:" && $1 <= "0fd0:"'
