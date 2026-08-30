#!/bin/bash
cd /home/jiaqi/rtthread-nano/rt-thread
echo "=== _MEM_MALLOC definitions ==="
grep -rn "_MEM_MALLOC\|_MEM_INIT\|_MEM_FREE\|_MEM_REALLOC\|_MEM_INFO\|_heap_lock" include/ | head -30
echo "=== idle.c idle thread creation ==="
sed -n '240,330p' src/idle.c
echo "=== timer.c rt_system_timer_init ==="
grep -n "rt_system_timer_init\|rt_system_timer_thread_init\|rt_timer_check" src/timer.c | head
