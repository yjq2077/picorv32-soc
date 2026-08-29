// print.c - minimal console output on UART0 (implementation)
#include "print.h"
#include "uart.h"
#include "soc_addr.h"
#include <stdarg.h>

static uart_t console;

void print_init(uint16_t prescale)
{
    console.base = UART0_BASE;
    uart_init(&console, prescale);
}

void putchar_(char c)
{
    if (c == '\n')
        uart_putc(&console, '\r');
    uart_putc(&console, c);
}

void puts_(const char *s)
{
    while (*s)
        putchar_(*s++);
}

static void print_unsigned(uint32_t v, int base, int upper, int pad, int width)
{
    static const char ldig[] = "0123456789abcdef";
    static const char udig[] = "0123456789ABCDEF";
    const char *dig = upper ? udig : ldig;
    char buf[12];
    int n = 0;

    if (base == 10) {
        do { buf[n++] = dig[v % 10]; v /= 10; } while (v);
    } else {
        do { buf[n++] = dig[v & 0xF]; v >>= 4; } while (v);
    }
    while (n < width)
        buf[n++] = pad ? '0' : ' ';
    while (n > 0)
        putchar_(buf[--n]);
}

int printf_(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);

    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            putchar_(*fmt);
            continue;
        }
        fmt++;
        int pad = 0, width = 0;
        if (*fmt == '0') { pad = 1; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') { width = width * 10 + (*fmt - '0'); fmt++; }
        if (*fmt == 'l') fmt++;   // ignore long modifier

        switch (*fmt) {
        case 'd': case 'i': {
            int v = va_arg(ap, int);
            if (v < 0) { putchar_('-'); print_unsigned((uint32_t)(-v), 10, 0, 0, width); }
            else       print_unsigned((uint32_t)v, 10, 0, 0, width);
            break;
        }
        case 'u': print_unsigned(va_arg(ap, uint32_t), 10, 0, 0, width); break;
        case 'x': print_unsigned(va_arg(ap, uint32_t), 16, 0, pad, width); break;
        case 'X': print_unsigned(va_arg(ap, uint32_t), 16, 1, pad, width); break;
        case 'c': putchar_((char)va_arg(ap, int)); break;
        case 's': {
            const char *s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            while (*s) putchar_(*s++);
            break;
        }
        case 'p': putchar_('0'); putchar_('x'); print_unsigned((uint32_t)(uintptr_t)va_arg(ap, void *), 16, 0, 1, 8); break;
        case '%': putchar_('%'); break;
        default: putchar_('%'); if (*fmt) putchar_(*fmt); break;
        }
    }
    va_end(ap);
    return 0;
}
