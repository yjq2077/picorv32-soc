#!/bin/bash
cd "$(dirname "$0")"
cp -f ../fw/fw.hex . 2>/dev/null
FW_WORDS=$(awk '!/^@/ {n += NF} END {print n}' fw.hex)
echo "[run_now] FW_WORDS=$FW_WORDS"
timeout 90 stdbuf -o0 ./obj_dir/Vsoc_tb +FW_WORDS=$FW_WORDS 2>&1
echo "SIM_EXIT=$?"
