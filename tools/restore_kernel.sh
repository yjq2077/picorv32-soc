#!/bin/bash
# restore_kernel.sh - copy the RT-Thread Nano kernel sources needed by fw/Makefile
set -e
SRC=/home/jiaqi/rtthread-nano/rt-thread/src
DST=/home/jiaqi/picorv32-soc/fw/rtos/src
mkdir -p "$DST"
for f in clock.c components.c cpu.c idle.c ipc.c irq.c kservice.c object.c scheduler.c thread.c timer.c; do
    cp "$SRC/$f" "$DST/$f"
done
echo "kernel sources restored:"
ls -la "$DST"
