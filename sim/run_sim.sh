#!/bin/bash
# run_sim.sh - run the Verilator SoC simulation with a timeout (streaming output)
cd "$(dirname "$0")"
cp -f ../fw/fw.hex . 2>/dev/null
# count data words in fw.hex (skip @address directive lines)
FW_WORDS=$(awk '!/^@/ {n += NF} END {print n}' fw.hex)
echo "[run_sim] FW_WORDS=$FW_WORDS"
timeout 120 stdbuf -o0 ./obj_dir/Vsoc_tb +FW_WORDS=$FW_WORDS 2>&1
echo "SIM_EXIT=$?"
