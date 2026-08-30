/*
 * cpuport.h - PicoRV32 (rv32im) port for RT-Thread Nano
 *
 * PicoRV32 does not implement the standard RISC-V mstatus/mepc CSRs.
 * Interrupts are gated by the custom `maskirq` instruction and ISRs are
 * entered at a fixed vector (PROGADDR_IRQ) with the return PC preserved
 * in the q0 register, so the thread context is a plain 32-word GPR frame.
 *
 * Thread stack frame layout (32 words, 128 bytes):
 *   [ 0] pc      resume program counter
 *   [ 1] ra      x1
 *   [ 2] sp      x2  (the value sp had when the frame was captured)
 *   [ 3] gp      x3  (constant in the bare-metal build)
 *   [ 4..31]     x4..x31
 *
 * The frame is pushed with `addi sp, sp, -32*REGBYTES` and popped with
 * `addi sp, sp, +32*REGBYTES`.  A frame captured at ISR level is stored
 * on the interrupted thread's own stack so both the task-level restore
 * (rt_hw_context_switch_exit) and the ISR-level restore (start.S irq_vec,
 * which copies the 32 words back into irq_regs) consume the same layout.
 */
#ifndef CPUPORT_H__
#define CPUPORT_H__

#include <rtconfig.h>
#include <stdint.h>

/* PicoRV32 is always 32-bit */
#define STORE                   sw
#define LOAD                    lw
#define REGBYTES                4

/*
 * ISR epilogue: called from the SoC irq() handler (app/irq.c) after
 * dispatching peripheral interrupts.  Performs a context switch if
 * rt_hw_context_switch_interrupt() was invoked by rt_schedule(); returns the
 * frame pointer that start.S restores before retirq.
 */
uint32_t *rt_hw_irq_handle_switch(uint32_t *regs);

/* set by rt_hw_context_switch_interrupt(), consumed by the ISR epilogue */
extern volatile rt_uint32_t rt_thread_switch_interrupt_flag;

#endif /* CPUPORT_H__ */
