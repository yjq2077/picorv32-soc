#!/bin/bash
echo "=== UART0 output ==="
grep -E '^UART0:' /tmp/rt_dbg2.log
echo "=== UART1 output ==="
grep -E '^UART1:' /tmp/rt_dbg2.log
echo "=== result markers ==="
grep -E 'TEST RESULT|RESULT|PASS|FAIL|SUMMARY|result_t' /tmp/rt_dbg2.log | head -30
