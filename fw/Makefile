# Makefile - PicoRV32 SoC firmware (RT-Thread Nano + peripheral library + app)
# Usage: make fw.hex   (build firmware image for simulation download)
#        make clean

# RISC-V cross toolchain prefix.  The default is the toolchain used during
# development; override per-machine (command line or environment), e.g.
#   make CROSS=riscv-none-elf- fw.hex
#   make CROSS=/opt/riscv32/bin/riscv-none-elf- fw.hex
CROSS    ?= /home/jiaqi/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
CC        = $(CROSS)gcc
OBJCOPY   = $(CROSS)objcopy
SIZE      = $(CROSS)size
OBJDUMP   = $(CROSS)objdump

ARCH      = -march=rv32im -mabi=ilp32
CFLAGS    = -Os -g -ffreestanding -nostdlib -fno-builtin -fno-stack-protector \
            -Wall -Wextra -Ilib -Irtos -Irtos/include -Irtos/libcpu $(ARCH)

APP_DIR   = app
LIB_DIR   = lib
RTOS_DIR  = rtos

APP_SRCS  = $(APP_DIR)/start.S $(APP_DIR)/main.c $(APP_DIR)/irq.c
LIB_SRCS  = $(LIB_DIR)/uart.c $(LIB_DIR)/i2c.c $(LIB_DIR)/gpio.c \
            $(LIB_DIR)/timer.c $(LIB_DIR)/irq_ctrl.c $(LIB_DIR)/ctrl.c \
            $(LIB_DIR)/print.c
LIB_ASM   = $(LIB_DIR)/riscv_cpu.S
RTOS_SRCS = $(RTOS_DIR)/board.c $(RTOS_DIR)/libcpu/cpuport.c \
            $(RTOS_DIR)/libcpu/context_gcc.S \
            $(RTOS_DIR)/src/clock.c $(RTOS_DIR)/src/components.c \
            $(RTOS_DIR)/src/cpu.c $(RTOS_DIR)/src/idle.c \
            $(RTOS_DIR)/src/ipc.c $(RTOS_DIR)/src/irq.c \
            $(RTOS_DIR)/src/kservice.c $(RTOS_DIR)/src/object.c \
            $(RTOS_DIR)/src/scheduler.c $(RTOS_DIR)/src/thread.c \
            $(RTOS_DIR)/src/timer.c
APP_OBJS  = $(patsubst %.S,%.o,$(patsubst %.c,%.o,$(APP_SRCS)))
LIB_OBJS  = $(patsubst %.c,%.o,$(LIB_SRCS)) $(patsubst %.S,%.o,$(LIB_ASM))
RTOS_OBJS = $(patsubst %.S,%.o,$(patsubst %.c,%.o,$(RTOS_SRCS)))
OBJS      = $(APP_OBJS) $(LIB_OBJS) $(RTOS_OBJS)

LDSCRIPT  = $(APP_DIR)/soc.ld

all: fw.hex fw.elf

# link
fw.elf: $(OBJS) $(LDSCRIPT)
	$(CC) $(ARCH) -T $(LDSCRIPT) -nostdlib -nostartfiles \
	    -Wl,--no-relax -Wl,--gc-sections -o $@ $(OBJS)
	$(SIZE) $@

# verilog hex for $readmemh (word-addresses, '@' markers)
fw.hex: fw.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

dis: fw.elf
	$(OBJDUMP) -d fw.elf > fw.dis

clean:
	rm -f $(OBJS) fw.elf fw.hex fw.dis

.PHONY: all clean dis
