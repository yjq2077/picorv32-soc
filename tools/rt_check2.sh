#!/bin/bash
cd /home/jiaqi/rtthread-nano/rt-thread
echo "=== mem.c heap functions ==="
grep -n "rt_system_heap_init\|rt_smem_init\|void \*rt_malloc\|RT_USING_HEAP\|#if\|#ifdef\|#ifndef\|#else\|#endif" src/mem.c | head -40
echo "=== which src use RT_USING_* ==="
for f in src/*.c; do echo "--- $f"; grep -o "RT_USING_[A-Z_]*\|RT_USING_HEAP\|RT_USING_SMALL_MEM" $f | sort -u | head -20; done
echo "=== rt_hw_us_delay weak? ==="
grep -rn "rt_hw_us_delay" src/ include/ | head
echo "=== rtm.h ==="
head -40 include/rtm.h
echo "=== kservice weak funcs ==="
grep -n "RT_WEAK" src/kservice.c
