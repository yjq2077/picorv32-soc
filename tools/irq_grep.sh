#!/bin/bash
grep -n "irq_mask <=\|irq_mask\b\|irq_active <=\|irq_active\|reg_next_pc <= 32" \
  /home/jiaqi/picorv32-soc/rtl/pico32/picorv32.v | head -50
echo "=== irq_regs / qregs ==="
grep -n "q0\|q1\|q2\|q3\|irqregs_offset\|irq_retirq\|irq_vec\|PROGADDR_IRQ" \
  /home/jiaqi/picorv32-soc/rtl/pico32/picorv32.v | head -40
