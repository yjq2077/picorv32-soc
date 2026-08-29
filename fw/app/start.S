// start.S - PicoRV32 SoC startup + IRQ vector
// reset_vec @ 0x00000000 (PROGADDR_RESET), irq_vec @ 0x00000010 (PROGADDR_IRQ)
#include "custom_ops.S"

        .section .text
        .global irq
        .global _start

// reset_vec: unmask all IRQs (irq_mask = 0), jump to start
_start:
reset_vec:
        picorv32_maskirq_insn(zero, zero)
        j start

/* Interrupt handler
 **********************************/

.balign 16
irq_vec:
        // save ra/sp into q2/q3, keep q0=PC q1=irq#
        picorv32_setq_insn(q2, x1)
        picorv32_setq_insn(q3, x2)

        lui x1, %hi(irq_regs)
        addi x1, x1, %lo(irq_regs)

        picorv32_getq_insn(x2, q0)
        sw x2,   0*4(x1)          // regs[0] = saved PC
        picorv32_getq_insn(x2, q2)
        sw x2,   1*4(x1)          // regs[1] = ra
        picorv32_getq_insn(x2, q3)
        sw x2,   2*4(x1)          // regs[2] = sp
        sw x3,   3*4(x1)
        sw x4,   4*4(x1)
        sw x5,   5*4(x1)
        sw x6,   6*4(x1)
        sw x7,   7*4(x1)
        sw x8,   8*4(x1)
        sw x9,   9*4(x1)
        sw x10, 10*4(x1)
        sw x11, 11*4(x1)
        sw x12, 12*4(x1)
        sw x13, 13*4(x1)
        sw x14, 14*4(x1)
        sw x15, 15*4(x1)
        sw x16, 16*4(x1)
        sw x17, 17*4(x1)
        sw x18, 18*4(x1)
        sw x19, 19*4(x1)
        sw x20, 20*4(x1)
        sw x21, 21*4(x1)
        sw x22, 22*4(x1)
        sw x23, 23*4(x1)
        sw x24, 24*4(x1)
        sw x25, 25*4(x1)
        sw x26, 26*4(x1)
        sw x27, 27*4(x1)
        sw x28, 28*4(x1)
        sw x29, 29*4(x1)
        sw x30, 30*4(x1)
        sw x31, 31*4(x1)

        // switch to IRQ stack
        lui sp, %hi(irq_stack)
        addi sp, sp, %lo(irq_stack)

        // call C: a0 = &irq_regs, a1 = irq number (q1)
        addi a0, x1, 0
        picorv32_getq_insn(a1, q1)
        jal ra, irq

        // restore registers from regs; a0 = new regs pointer
        addi x1, a0, 0

        lw x2,   0*4(x1)          // regs[0] -> q0 (PC)
        picorv32_setq_insn(q0, x2)
        lw x2,   1*4(x1)          // regs[1] -> q1 (ra)
        picorv32_setq_insn(q1, x2)
        lw x2,   2*4(x1)          // regs[2] -> q2 (sp)
        picorv32_setq_insn(q2, x2)
        lw x3,   3*4(x1)
        lw x4,   4*4(x1)
        lw x5,   5*4(x1)
        lw x6,   6*4(x1)
        lw x7,   7*4(x1)
        lw x8,   8*4(x1)
        lw x9,   9*4(x1)
        lw x10, 10*4(x1)
        lw x11, 11*4(x1)
        lw x12, 12*4(x1)
        lw x13, 13*4(x1)
        lw x14, 14*4(x1)
        lw x15, 15*4(x1)
        lw x16, 16*4(x1)
        lw x17, 17*4(x1)
        lw x18, 18*4(x1)
        lw x19, 19*4(x1)
        lw x20, 20*4(x1)
        lw x21, 21*4(x1)
        lw x22, 22*4(x1)
        lw x23, 23*4(x1)
        lw x24, 24*4(x1)
        lw x25, 25*4(x1)
        lw x26, 26*4(x1)
        lw x27, 27*4(x1)
        lw x28, 28*4(x1)
        lw x29, 29*4(x1)
        lw x30, 30*4(x1)
        lw x31, 31*4(x1)

        picorv32_getq_insn(x1, q1)   // restore ra
        picorv32_getq_insn(x2, q2)   // restore sp

        picorv32_retirq_insn()

.balign 0x200
irq_regs:
        // registers are saved here during interrupt handling (regs[0]=PC)
        .fill 32,4
        // stack for the interrupt handler
        .fill 128,4
irq_stack:

/* Main program
 **********************************/

start:
        // stack pointer = STACKADDR (top of 64KB RAM, grows down)
        lui sp, 0x00010000>>12
        addi sp, sp, 0x00010000&0xfff

        // zero the .bss section
        lui a0, %hi(__bss_start)
        addi a0, a0, %lo(__bss_start)
        lui a1, %hi(__bss_end)
        addi a1, a1, %lo(__bss_end)
1:      bgeu a0, a1, 2f
        sw zero, 0(a0)
        addi a0, a0, 4
        j 1b
2:

        jal ra, main

        // main returned - signal trap to end simulation
        ebreak

// Helper: set CPU interrupt mask (bit n = 1 -> masked/disabled)
//   void picorv32_irq_mask(uint32_t mask)
        .global picorv32_irq_mask
picorv32_irq_mask:
        picorv32_maskirq_insn(zero, a0)
        ret

// Helper: read current CPU interrupt mask
//   uint32_t picorv32_irq_get_mask(void)
        .global picorv32_irq_get_mask
picorv32_irq_get_mask:
        addi a0, zero, 0
        picorv32_maskirq_insn(a0, a0)
        ret
