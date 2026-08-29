// files_rtl.f - Verilator RTL source list (paths relative to sim/)
// Resolved from the sim/ directory, which build_sim.sh cd's into first.

// PicoRV32 core (ISC)
../rtl/pico32/picorv32.v

// Alex Forencich AXI infrastructure (MIT) - axil_interconnect
../rtl/third_party/verilog-axi/rtl/priority_encoder.v
../rtl/third_party/verilog-axi/rtl/arbiter.v
../rtl/third_party/verilog-axi/rtl/axil_interconnect.v

// Alex Forencich UART (MIT)
../rtl/third_party/verilog-uart/rtl/uart.v
../rtl/third_party/verilog-uart/rtl/uart_rx.v
../rtl/third_party/verilog-uart/rtl/uart_tx.v

// Alex Forencich I2C master (MIT)
../rtl/third_party/verilog-i2c/rtl/i2c_master_axil.v
../rtl/third_party/verilog-i2c/rtl/i2c_master.v
../rtl/third_party/verilog-i2c/rtl/i2c_init.v
../rtl/third_party/verilog-i2c/rtl/axis_fifo.v

// SoC-specific RTL
../rtl/soc/soc_top.v
../rtl/soc/axil_ram.v
../rtl/soc/boot_ctrl.v
../rtl/soc/irq_ctrl.v
../rtl/soc/uart_axil.v
../rtl/soc/axil2apb.v
../rtl/soc/apb_gpio.v
../rtl/soc/apb_timer.v
../rtl/soc/apb_ctrl.v
../rtl/soc/apb_interconnect.v
