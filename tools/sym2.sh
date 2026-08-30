#!/bin/bash
O=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump
cd /home/jiaqi/picorv32-soc/fw
echo "=== raw disasm 0x0f00-0x1010 ==="
"$O" -d fw.elf | awk '$1 ~ /^0f[0-9a-f]{2}:/ || $1 ~ /^0[0-9a-f]f[0-9a-f]:/ || $1 ~ /^100[0-9a-f]:/' | head -40
echo "=== symbol table (nm) ==="
/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-nm -n fw.elf | awk '$1 ~ /^0?0fc4|^0?0f00|^0?0f|^0?1000/' | head -20
echo "=== which function contains 0x0fc4 ==="
"$O" -d fw.elf | awk 'NR==FNR{next}' /dev/null | grep -n '^0000' | awk -F: '{split($2,a," "); if (a[1]+0 <= 0x0fc4) last=$0} END{print last}'
