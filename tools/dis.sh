#!/bin/bash
# dis.sh - disassemble fw.elf around a given address (default 0x1a80-0x1b40)
TOOL=/home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
ELF=/home/jiaqi/picorv32-soc/fw/fw.elf
FROM=${1:-0x1a80}
TO=${2:-0x1b40}
echo "=== disassembly $FROM-$TO ==="
${TOOL}objdump -d "$ELF" | awk -v f=$FROM -v t=$TO '
  /^[0-9a-f]+:/ {
    addr = $1; sub(/:/, "", addr); a = strtonum("0x" addr);
    if (a >= f && a <= t) print
  }'
