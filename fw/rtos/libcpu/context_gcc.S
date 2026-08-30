/*
 * context_gcc.S - PicoRV32 (rv32im) RT-Thread context switching
 *
 * PicoRV32 has no mstatus/mepc CSRs.  Interrupts are gated by the custom
 * `maskirq` instruction and the ISR vector is entered at PROGADDR_IRQ with
 * the return PC kept in the q0 register.  A thread context is therefore a
 * plain 32-word GPR frame (see cpuport.h):
 *
 *   frame[ 0] pc    (resume program counter)
 *   frame[ 1] ra
 *   frame[ 2] sp    (sp value at capture time)
 *   frame[ 3] gp
 *   frame[ 4..31] x4..x31
 *
 * maskirq encodings (opcode 0x0B, funct3 0b110, funct7 0b0000011):
 *   rd = old irq_mask; irq_mask = rs1
 *     0x0600600b  maskirq zero, zero   (unmask every irq line)
 *     0x0605600b  maskirq zero, a0     (set mask from a0)
 *     0x0603650b  maskirq a0,  t1      (read old mask into a0, mask = t1)
 */
    .section .text

/* rt_base_t rt_hw_interrupt_disable(void) */
    .globl rt_hw_interrupt_disable
rt_hw_interrupt_disable:
    li   t1, -1
    .word 0x0603650b          /* maskirq a0, t1 : a0 = old mask, mask = all ones */
    ret

/* void rt_hw_interrupt_enable(rt_base_t level) */
    .globl rt_hw_interrupt_enable
rt_hw_interrupt_enable:
    .word 0x0605600b          /* maskirq zero, a0 : mask = level */
    ret

/*
 * void rt_hw_context_switch_to(rt_ubase_t to);
 * a0 = &to_thread->sp.  Called exactly once from rt_system_scheduler_start()
 * to launch the first thread; this is the safe point to unmask every irq
 * line (the scheduler is already initialised).
 */
    .globl rt_hw_context_switch_to
rt_hw_context_switch_to:
    .word 0x0600600b          /* maskirq zero, zero : unmask every irq line */
    lw   sp, 0(a0)
    j    rt_hw_context_switch_exit

/*
 * void rt_hw_context_switch(rt_ubase_t from, rt_ubase_t to);
 * a0 = &from_thread->sp, a1 = &to_thread->sp.
 * Called at task level with interrupts disabled (rt_schedule holds a
 * critical section), so no IRQ can disturb the save sequence.
 */
    .globl rt_hw_context_switch
rt_hw_context_switch:
    addi sp, sp, -32 * 4
    sw   sp, 0(a0)            /* from->sp = frame base */

    sw   x1, 0 * 4(sp)        /* frame[0] = pc (resume point) */
    sw   x1, 1 * 4(sp)        /* frame[1] = ra */
    sw   x3, 3 * 4(sp)        /* frame[3] = gp */
    sw   x4, 4 * 4(sp)        /* frame[4] = tp */
    sw   x5, 5 * 4(sp)        /* save t0 before using it as scratch */
    addi t0, sp, 32 * 4
    sw   t0, 2 * 4(sp)        /* frame[2] = sp value at capture */
    sw   x6, 6 * 4(sp)
    sw   x7, 7 * 4(sp)
    sw   x8, 8 * 4(sp)
    sw   x9, 9 * 4(sp)
    sw   x10, 10 * 4(sp)
    sw   x11, 11 * 4(sp)
    sw   x12, 12 * 4(sp)
    sw   x13, 13 * 4(sp)
    sw   x14, 14 * 4(sp)
    sw   x15, 15 * 4(sp)
    sw   x16, 16 * 4(sp)
    sw   x17, 17 * 4(sp)
    sw   x18, 18 * 4(sp)
    sw   x19, 19 * 4(sp)
    sw   x20, 20 * 4(sp)
    sw   x21, 21 * 4(sp)
    sw   x22, 22 * 4(sp)
    sw   x23, 23 * 4(sp)
    sw   x24, 24 * 4(sp)
    sw   x25, 25 * 4(sp)
    sw   x26, 26 * 4(sp)
    sw   x27, 27 * 4(sp)
    sw   x28, 28 * 4(sp)
    sw   x29, 29 * 4(sp)
    sw   x30, 30 * 4(sp)
    sw   x31, 31 * 4(sp)

    lw   sp, 0(a1)            /* sp = to->sp (to-thread frame) */
    j    rt_hw_context_switch_exit

/*
 * Restore a 32-word thread frame and resume.  sp = frame base; the pc to
 * resume lives in frame[0].  sp itself is restored last from frame[2].
 * t1 (x6) is used as the jump-target scratch: its frame[6] slot is restored
 * first, then overwritten with the resume pc right before `jr t1`.  This is
 * the standard RISC-V RTOS tradeoff - t1 is a caller-saved temporary, so the
 * resumed code (at a function-call boundary) never relies on its value.
 */
    .globl rt_hw_context_switch_exit
rt_hw_context_switch_exit:
    lw   x1, 1 * 4(sp)        /* ra */
    lw   x3, 3 * 4(sp)        /* gp */
    lw   x4, 4 * 4(sp)
    lw   x5, 5 * 4(sp)
    lw   x6, 6 * 4(sp)
    lw   x7, 7 * 4(sp)
    lw   x8, 8 * 4(sp)
    lw   x9, 9 * 4(sp)
    lw   x10, 10 * 4(sp)
    lw   x11, 11 * 4(sp)
    lw   x12, 12 * 4(sp)
    lw   x13, 13 * 4(sp)
    lw   x14, 14 * 4(sp)
    lw   x15, 15 * 4(sp)
    lw   x16, 16 * 4(sp)
    lw   x17, 17 * 4(sp)
    lw   x18, 18 * 4(sp)
    lw   x19, 19 * 4(sp)
    lw   x20, 20 * 4(sp)
    lw   x21, 21 * 4(sp)
    lw   x22, 22 * 4(sp)
    lw   x23, 23 * 4(sp)
    lw   x24, 24 * 4(sp)
    lw   x25, 25 * 4(sp)
    lw   x26, 26 * 4(sp)
    lw   x27, 27 * 4(sp)
    lw   x28, 28 * 4(sp)
    lw   x29, 29 * 4(sp)
    lw   x30, 30 * 4(sp)
    lw   x31, 31 * 4(sp)
    lw   t1, 0 * 4(sp)        /* t1 = resume pc (after x6 is restored) */
    lw   sp, 2 * 4(sp)        /* restore sp last */

    /*
     * The thread frame does not carry an irq mask.  rt_hw_context_switch()
     * runs inside rt_schedule's critical section (irqs masked), so resume the
     * new thread with every irq line enabled - the ISR path restores its own
     * saved mask via start.S, only the task-level switch reaches this point.
     */
    .word 0x0600600b          /* maskirq zero, zero : unmask every irq line */
    jr   t1
