#!/bin/bash
N=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-nm
cd /home/jiaqi/picorv32-soc/fw
echo "=== symbols around 0x5ab4 ==="
"$N" -n fw.elf | awk '{a=strtonum("0x"$1); if (a>=0x5400 && a<=0x6000) print}'
echo "=== bss/data layout ==="
"$N" -n fw.elf | grep -iE ' b | d | s | t ' | awk '{a=strtonum("0x"$1); if (a>=0x3000 && a<=0x8000) print}' | head -60
