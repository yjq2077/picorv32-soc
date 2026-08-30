#!/bin/bash
# dis2.sh - disassemble a list of address ranges and show function names
TOOL=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
ELF=/home/jiaqi/picorv32-soc/fw/fw.elf
echo "=== symbol table (sorted) ==="
${TOOL}nm -n "$ELF" | grep -E " [tT] " | awk '$1>="00000000" && $1<="00003000"' 
echo
echo "=== uart_it_putc 0x133c - 0x1420 ==="
${TOOL}objdump -d "$ELF" | awk '/^[0-9a-f]+:/ { addr=$1; sub(/:/,"",addr); a=strtonum("0x"addr); if (a>=0x133c && a<=0x1420) print }'
