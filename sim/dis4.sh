#!/bin/bash
# dis4.sh - disassemble firmware ELF around an address range
cd "$(dirname "$0")"
OBJ=~/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump
LO=$1
HI=$2
[ -z "$HI" ] && HI=$((LO + 0x100))
$OBJ -d ../fw/fw.elf | awk -v lo="$LO" -v hi="$HI" '
  /^[0-9a-f]+ </ {
    split($1, a, ":");
    addr = strtonum("0x" a[1]);
    if (addr >= lo && addr <= hi) show = 1; else show = 0;
    if (show) print;
    next;
  }
  show { print }
'
