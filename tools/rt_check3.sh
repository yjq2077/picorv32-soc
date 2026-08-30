#!/bin/bash
cd /home/jiaqi/rtthread-nano/rt-thread
echo "=== kservice weak heap 1480-1620 ==="
sed -n '1480,1620p' src/kservice.c
echo "=== bsp dirs ==="
ls bsp/ 2>/dev/null | head
echo "=== any rtconfig examples ==="
find bsp -name "rtconfig.h" 2>/dev/null | head -20
