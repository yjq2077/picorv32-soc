# Makefile - PicoRV32 SoC firmware (library + app)
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
            -Wall -Wextra -Ilib $(ARCH)

APP_DIR   = app
LIB_DIR   = lib

APP_SRCS  = $(APP_DIR)/start.S $(APP_DIR)/main.c $(APP_DIR)/irq.c
LIB_SRCS  = $(LIB_DIR)/uart.c $(LIB_DIR)/i2c.c $(LIB_DIR)/gpio.c \
            $(LIB_DIR)/timer.c $(LIB_DIR)/irq_ctrl.c $(LIB_DIR)/ctrl.c \
            $(LIB_DIR)/print.c
APP_OBJS  = $(patsubst %.S,%.o,$(patsubst %.c,%.o,$(APP_SRCS)))
LIB_OBJS  = $(LIB_SRCS:.c=.o)
OBJS      = $(APP_OBJS) $(LIB_OBJS)

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
