#!/bin/bash
# build_sim.sh - build the Verilator SoC simulation
#   +define+ENABLE_DBG adds extra simulation-time monitors (noisy)
cd "$(dirname "$0")"
DEFINE=""
[ "$1" = "dbg" ] && DEFINE="-DENABLE_DBG"
verilator --cc --exe --main --timing \
    -Wno-fatal -Wno-SELRANGE -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    -O3 --Mdir obj_dir --build --top-module soc_tb \
    -f files_rtl.f soc_tb.v \
    $DEFINE \
    2>&1 | tail -20
echo "BUILD_EXIT=$?"
