#!/bin/bash
# dis3.sh - dump disassembly around a PC range from the firmware ELF
cd "$(dirname "$0")"
FW=../fw/fw.elf
if [ ! -f "$FW" ]; then
    FW=$(ls ../fw/*.elf 2>/dev/null | head -1)
fi
echo "== ELF: $FW =="
RANGE=${1:-0x1a00:0x1b00}
LO=$(echo $RANGE | cut -d: -f1)
HI=$(echo $RANGE | cut -d: -f2)
riscv-none-elf-objdump -d "$FW" | awk -v lo="0x$LO" -v hi="0x$HI" '
  /^[0-9a-f]+ </ { addr="0x" $1; gsub(":","",addr); inrange=(strtonum(addr)>=strtonum(lo) && strtonum(addr)<=strtonum(hi)); print; next }
  inrange { print }
'
