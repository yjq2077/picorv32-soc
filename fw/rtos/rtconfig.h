/* rtconfig.h - RT-Thread Nano configuration for PicoRV32 SoC
 *
 * Minimal configuration: scheduler + threads + semaphore IPC + console.
 * No dynamic heap (threads are created statically with rt_thread_init),
 * no software timers, no device framework.
 */
#ifndef __RTTHREAD_CFG_H__
#define __RTTHREAD_CFG_H__

/* ---------------- Basic Configuration ---------------- */
/* Maximal level of thread priority (0 = highest) */
#define RT_THREAD_PRIORITY_MAX         32

/* OS tick per second (1 kHz tick) */
#define RT_TICK_PER_SECOND             1000

/* Alignment size for CPU architecture data access */
#define RT_ALIGN_SIZE                  4

/* the max length of object name */
#define RT_NAME_MAX                    8

/* idle thread stack size (bytes) */
#define RT_IDLE_THREAD_STACK_SIZE      512

/* ---------------- Debug Configuration ---------------- */
/* #define RT_DEBUG */
#define RT_DEBUG_INIT                  0
/* #define RT_USING_OVERFLOW_CHECK */

/* ---------------- Hook Configuration ---------------- */
/* #define RT_USING_HOOK */
/* #define RT_USING_IDLE_HOOK */

/* ---------------- Software timers Configuration ---------------- */
/* #define RT_USING_TIMER_SOFT */
#define RT_TIMER_THREAD_PRIO           4
#define RT_TIMER_THREAD_STACK_SIZE     512

/* ---------------- IPC Configuration ---------------- */
#define RT_USING_SEMAPHORE
/* #define RT_USING_MUTEX */
/* #define RT_USING_EVENT */
/* #define RT_USING_MAILBOX */
/* #define RT_USING_MESSAGEQUEUE */

/* ---------------- Memory Management Configuration ---------------- */
/* no dynamic heap: threads use pre-allocated static stacks */
/* #define RT_USING_HEAP */
/* #define RT_USING_SMALL_MEM */

/* ---------------- Console Configuration ---------------- */
#define RT_USING_CONSOLE
#define RT_CONSOLEBUF_SIZE              128

#endif /* __RTTHREAD_CFG_H__ */
