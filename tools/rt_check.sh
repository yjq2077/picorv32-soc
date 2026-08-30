#!/bin/bash
cd /home/jiaqi/rtthread-nano/rt-thread
echo "=== BSP-required symbols in src ==="
grep -rl "rt_hw_us_delay\|rt_hw_console_output\|rt_hw_interrupt_handle\|rt_hw_backtrace\|rt_components" src/ | sort
echo "=== RT_ALIGN in rtdef.h ==="
grep -n "RT_ALIGN" include/rtdef.h | head -20
echo "=== idle.c stack_init usage ==="
grep -n "rt_hw_stack_init\|rt_thread_idle" src/idle.c | head
echo "=== components.c ==="
grep -n "rt_components\|rt_components_board" src/components.c | head
echo "=== kservice references to hw ==="
grep -rn "rt_hw_console_output\|rt_hw_backtrace" src/*.c | head
echo "=== mem.c heap ==="
grep -n "rt_system_heap_init\|RT_USING_HEAP" src/mem.c | head
echo "=== version of RT-Thread ==="
grep -n "RT_VERSION" include/rtdef.h | head
