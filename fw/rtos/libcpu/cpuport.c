/*
 * cpuport.c - PicoRV32 (rv32im) RT-Thread port
 *
 * Thread frame layout (32 words) matches start.S irq_vec and context_gcc.S:
 *   [0] pc [1] ra [2] sp [3] gp [4..31] x4..x31
 */
#include <rthw.h>
#include <rtthread.h>
#include "cpuport.h"

/* set by rt_hw_context_switch_interrupt(), consumed by rt_hw_irq_handle_switch() */
volatile rt_ubase_t *rt_interrupt_from_thread;
volatile rt_ubase_t *rt_interrupt_to_thread;
volatile rt_uint32_t rt_thread_switch_interrupt_flag = 0;

rt_uint8_t *rt_hw_stack_init(void       *tentry,
                             void       *parameter,
                             rt_uint8_t *stack_addr,
                             void       *texit)
{
    rt_ubase_t *frame;
    rt_uint8_t *stk;
    int i;

    stk  = stack_addr + sizeof(rt_ubase_t);
    stk  = (rt_uint8_t *)RT_ALIGN_DOWN((rt_ubase_t)stk, REGBYTES);
    stk -= 32 * REGBYTES;

    frame = (rt_ubase_t *)stk;

    for (i = 0; i < 32; i++)
        frame[i] = 0xdeadbeef;

    frame[0]  = (rt_ubase_t)tentry;              /* pc */
    frame[1]  = (rt_ubase_t)texit;               /* ra */
    frame[2]  = (rt_ubase_t)stk + 32 * REGBYTES; /* sp */
    /* gp: capture the value start.S established (never changes in this
     * build); a zero gp would break gp-relative accesses in the thread */
    __asm__ volatile("addi %0, gp, 0" : "=r"(frame[3]));
    frame[10] = (rt_ubase_t)parameter;           /* a0 */

    return stk;
}

#ifndef RT_USING_SMP
RT_WEAK void rt_hw_context_switch_interrupt(rt_ubase_t from, rt_ubase_t to)
{
    if (rt_thread_switch_interrupt_flag == 0)
        rt_interrupt_from_thread = (volatile rt_ubase_t *)from;

    rt_interrupt_to_thread = (volatile rt_ubase_t *)to;
    rt_thread_switch_interrupt_flag = 1;
}
#endif /* RT_USING_SMP */

/*
 * ISR epilogue: called from the SoC irq() handler after RT-Thread has
 * requested a context switch.  `regs` points at the static irq_regs[] frame
 * that start.S restores before retirq.  Push the interrupted context onto
 * the from-thread's own stack (below the sp it had when interrupted),
 * update from_thread->sp, load the to-thread's frame into irq_regs and
 * return the (possibly new) frame pointer.
 */
uint32_t *rt_hw_irq_handle_switch(uint32_t *regs)
{
    rt_ubase_t *frame;
    rt_ubase_t *to;
    int i;

    if (!rt_thread_switch_interrupt_flag)
        return regs;

    rt_thread_switch_interrupt_flag = 0;

    /* the interrupted sp is regs[2]; place the frame below it */
    frame = (rt_ubase_t *)((rt_ubase_t)regs[2] - 32 * REGBYTES);
    for (i = 0; i < 32; i++)
        frame[i] = regs[i];
    *rt_interrupt_from_thread = (rt_ubase_t)frame;

    /* load the to-thread context into irq_regs (same frame layout) */
    to = (rt_ubase_t *)(*rt_interrupt_to_thread);
    for (i = 0; i < 32; i++)
        regs[i] = to[i];

    return regs;
}

RT_WEAK void rt_hw_cpu_shutdown(void)
{
    rt_kprintf("shutdown...\n");
    while (1)
        ;
}
