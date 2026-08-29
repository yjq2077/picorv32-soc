#!/usr/bin/env python3
"""Parse sim_dbg.log and reconstruct peripheral verification data & timing."""
import re, sys, collections

LOG = sys.argv[1] if len(sys.argv) > 1 else "sim_dbg.log"

uart0_chars = []   # (time_ns, char)
uart1_chars = []
apb0_rd, apb0_wr = [], []   # (time_ns, addr, data)
apb1_rd, apb1_wr = [], []
irq_aw, irq_rv = [], []
ram_ar = []
cpu_rstn_events = []
irq_edges = []
i2c_scl_fall = []
first_fetch = None
result = None
cpu_trap_t = None
apb0_wr_cnt_marker = apb1_wr_cnt_marker = 0

with open(LOG, "r", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n")
        m = re.match(r"^UART0: (.*)$", line)
        if m:
            frag = m.group(1)
            # strip any trailing [dbg] noise that landed on same line
            frag = re.sub(r"\[dbg\].*$", "", frag)
            uart0_chars.append(frag)
            continue
        m = re.match(r"^UART1: (.*)$", line)
        if m:
            frag = re.sub(r"\[dbg\].*$", "", m.group(1))
            uart1_chars.append(frag)
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB0 AR#(\d+) addr=0x([0-9a-fA-F]+)", line)
        if m:
            apb0_rd.append((int(m.group(1)), int(m.group(3), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB0 RVALID#(\d+) data=0x([0-9a-fA-F]+)", line)
        if m:
            apb0_rd.append((int(m.group(1)) + 0.5, int(m.group(3), 16)))  # mark read-data
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB0 AW#(\d+) addr=0x([0-9a-fA-F]+) data=0x([0-9a-fA-F]+)", line)
        if m:
            apb0_wr.append((int(m.group(1)), int(m.group(3), 16), int(m.group(4), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB0 BVALID#(\d+)", line)
        if m:
            apb0_wr_cnt_marker = int(m.group(2))
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB1 AR#(\d+) addr=0x([0-9a-fA-F]+)", line)
        if m:
            apb1_rd.append((int(m.group(1)), int(m.group(3), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB1 RVALID#(\d+) data=0x([0-9a-fA-F]+)", line)
        if m:
            apb1_rd.append((int(m.group(1)) + 0.5, int(m.group(3), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB1 AW#(\d+) addr=0x([0-9a-fA-F]+) data=0x([0-9a-fA-F]+)", line)
        if m:
            apb1_wr.append((int(m.group(1)), int(m.group(3), 16), int(m.group(4), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) APB1 BVALID#(\d+)", line)
        if m:
            apb1_wr_cnt_marker = int(m.group(2))
            continue
        m = re.match(r"\[dbg\] t=(\d+) IRQ AW addr=0x([0-9a-fA-F]+) data=0x([0-9a-fA-F]+)", line)
        if m:
            irq_aw.append((int(m.group(1)), int(m.group(2), 16), int(m.group(3), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) IRQ RVALID addr=0x([0-9a-fA-F]+) data=0x([0-9a-fA-F]+)", line)
        if m:
            irq_rv.append((int(m.group(1)), int(m.group(2), 16), int(m.group(3), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) RAM AR addr=0x([0-9a-fA-F]+)", line)
        if m:
            ram_ar.append((int(m.group(1)), int(m.group(2), 16)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) (cpu_resetn HIGH|cpu_resetn LOW)", line)
        if m:
            cpu_rstn_events.append((int(m.group(1)), m.group(2)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) (IRQ_OUT rising|IRQ_OUT falling)", line)
        if m:
            irq_edges.append((int(m.group(1)), m.group(2)))
            continue
        m = re.match(r"\[dbg\] t=(\d+) I2C0 SCL fall #(\d+)", line)
        if m:
            i2c_scl_fall.append((int(m.group(1)), int(m.group(2))))
            continue
        m = re.match(r"\[dbg\] t=(\d+) CPU first instr fetch addr=0x([0-9a-fA-F]+)", line)
        if m:
            first_fetch = (int(m.group(1)), int(m.group(2), 16))
            continue
        m = re.match(r"\[dbg\] t=(\d+) CPU trap asserted", line)
        if m:
            cpu_trap_t = int(m.group(1))
            continue
        m = re.match(r"=== TEST RESULT: (\w+).*", line)
        if m:
            result = (m.group(1), line)
            continue
        m = re.match(r"\[host\] (.*)", line)
        if m:
            sys.stdout.write("[host] %s\n" % m.group(1))
            continue

print("=" * 70)
print("TEST RESULT:", result)
if first_fetch:
    print("CPU first instr fetch: t=%d ns addr=0x%08x" % first_fetch)
for t, ev in cpu_rstn_events:
    print("cpu_resetn: t=%d ns %s" % (t, ev))
if cpu_trap_t:
    print("cpu trap asserted: t=%d ns" % cpu_trap_t)

print()
print("=" * 70)
print("IRQ_OUT edges:")
for t, ev in irq_edges:
    print("  t=%10d ns  %s" % (t, ev))

print()
print("=" * 70)
print("IRQ controller AXI-Lite writes (addr,data):")
for t, a, d in irq_aw:
    print("  t=%10d ns  aw=0x%08x data=0x%08x" % (t, a, d))
print("IRQ controller AXI-Lite reads:")
for t, a, d in irq_rv:
    print("  t=%10d ns  ar=0x%08x data=0x%08x" % (t, a, d))

print()
print("=" * 70)
print("APB0 transactions (%d writes, %d read samples):" % (len(apb0_wr), len(apb0_rd)))
prev = None
for t, a, d in apb0_wr:
    print("  W t=%10d ns  addr=0x%05x data=0x%08x" % (t, a, d))
for t, a in apb0_rd:
    tag = "  R t=%10d ns  addr=0x%05x" % (t, a)
    if isinstance(t, float):
        tag += "  ->data=0x%08x" % a
    print(tag)

print()
print("=" * 70)
print("APB1 transactions (%d writes, %d read samples):" % (len(apb1_wr), len(apb1_rd)))
for t, a, d in apb1_wr:
    print("  W t=%10d ns  addr=0x%05x data=0x%08x" % (t, a, d))
for t, a in apb1_rd:
    tag = "  R t=%10d ns  addr=0x%05x" % (t, a)
    if isinstance(t, float):
        tag += "  ->data=0x%08x" % a
    print(tag)

print()
print("=" * 70)
print("RAM read (AR) accesses: %d" % len(ram_ar))
if ram_ar:
    print("  first: t=%d ns addr=0x%08x" % ram_ar[0])
    print("  last : t=%d ns addr=0x%08x" % ram_ar[-1])

print()
print("=" * 70)
print("I2C0 SCL falling edges: %d" % len(i2c_scl_fall))
if i2c_scl_fall:
    print("  first: t=%d ns (#%d)" % i2c_scl_fall[0])
    print("  last : t=%d ns (#%d)" % i2c_scl_fall[-1])

print()
print("=" * 70)
print("UART0 decoded stream (chars=%d):" % sum(len(c) for c in uart0_chars))
print("".join(uart0_chars))
print()
print("UART1 decoded stream (chars=%d):" % sum(len(c) for c in uart1_chars))
print("".join(uart1_chars))
