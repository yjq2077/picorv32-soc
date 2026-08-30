#!/bin/bash
cd /home/jiaqi/rtthread-nano/rt-thread
echo "=== _MEM_ macro defs anywhere ==="
grep -rn "define _MEM_MALLOC\|define _MEM_INIT\|define _MEM_FREE\|define _MEM_REALLOC\|define _MEM_INFO\|define _heap_lock" . 2>/dev/null | grep -v "\.git" | head -20
echo "=== RT_IDLE_THREAD_STACK_SIZE ==="
grep -rn "RT_IDLE_THREAD_STACK_SIZE\|rt_thread_stack\[" src/idle.c | head
echo "=== rtdef.h heap-related macros ==="
grep -n "_MEM\|RT_USING_SMALL_MEM_AS_HEAP\|RT_USING_SLAB_AS_HEAP\|RT_USING_MEMHEAP_AS_HEAP" include/rtdef.h | head -30
