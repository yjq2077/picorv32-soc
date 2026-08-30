#!/bin/bash
# restore_rtos.sh - (re)populate fw/rtos/src from the vendored rtthread-nano tree
set -e
cd /home/jiaqi
mkdir -p picorv32-soc/fw/rtos/src picorv32-soc/fw/rtos/libcpu
for f in clock.c components.c cpu.c idle.c ipc.c irq.c kservice.c object.c scheduler.c thread.c timer.c; do
    cp rtthread-nano/rt-thread/src/$f picorv32-soc/fw/rtos/src/
done
ls -la picorv32-soc/fw/rtos/src/
wc -l picorv32-soc/fw/rtos/src/*.c | tail -1
