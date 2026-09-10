`resetall
`timescale 1ns / 1ps
`default_nettype none

// soc_top.v - PicoRV32 SoC with dual-master AXI-Lite interconnect
//
// Masters:
//   0: PicoRV32 CPU (internal)
//   1: External host / firmware download port (top-level AXI-Lite slave)
//
// Slaves (compact map: all within 2 MB, one 64 KB window per port):
//   0: 0x00000000  RAM        (axil_ram, 64KB)
//   1: 0x00010000  BOOT       (boot_ctrl: CPU reset control + APB base addrs)
//   2: 0x00020000  IRQ        (irq_ctrl: interrupt controller)
//   3: 0x00030000  I2C0
//   4: 0x00040000  I2C1
//   5: 0x00050000  I2C2
//   6: 0x00060000  I2C3
//   7: 0x00070000  UART0
//   8: 0x00080000  UART1
//   9: 0x00090000  APB0       (GPIO @ +0x0000, TIMER0 @ +0x1000)
//  10: 0x000A0000  APB1       (CTRL @ +0x0000, TIMER1 @ +0x1000)
//
// APB0/APB1 windows are relocatable: boot_ctrl APB0_BASE / APB1_BASE
// registers (default 0) override the fixed bases above when non-zero.
//
// Interrupt mapping (irq_ctrl inputs):
//   [0] uart0_rx  [1] uart0_tx  [2] uart1_rx  [3] uart1_tx
//   [4] timer0    [5] timer1    [6] gpio
module soc_top #(
    parameter integer RAM_ADDR_WIDTH = 16,   // 64KB
    parameter integer ADDR_WIDTH     = 32,
    parameter integer DATA_WIDTH     = 32,
    parameter integer STRB_WIDTH     = DATA_WIDTH/8
) (
    input  wire clk,
    input  wire rst_n,

    // External host AXI-Lite slave port (download + full peripheral access)
    input  wire [ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  wire [ 2:0]             s_axil_awprot,
    input  wire                    s_axil_awvalid,
    output wire                    s_axil_awready,
    input  wire [DATA_WIDTH-1:0]   s_axil_wdata,
    input  wire [STRB_WIDTH-1:0]   s_axil_wstrb,
    input  wire                    s_axil_wvalid,
    output wire                    s_axil_wready,
    output wire [ 1:0]             s_axil_bresp,
    output wire                    s_axil_bvalid,
    input  wire                    s_axil_bready,
    input  wire [ADDR_WIDTH-1:0]   s_axil_araddr,
    input  wire [ 2:0]             s_axil_arprot,
    input  wire                    s_axil_arvalid,
    output wire                    s_axil_arready,
    output wire [DATA_WIDTH-1:0]   s_axil_rdata,
    output wire [ 1:0]             s_axil_rresp,
    output wire                    s_axil_rvalid,
    input  wire                    s_axil_rready,

    // CPU status
    output wire                    cpu_trap,
    output wire                    cpu_resetn,

    // UART
    output wire                    uart0_txd,
    input  wire                    uart0_rxd,
    output wire                    uart1_txd,
    input  wire                    uart1_rxd,

    // I2C (open drain)
    inout  wire                    i2c0_scl, i2c0_sda,
    inout  wire                    i2c1_scl, i2c1_sda,
    inout  wire                    i2c2_scl, i2c2_sda,
    inout  wire                    i2c3_scl, i2c3_sda,

    // GPIO
    input  wire [15:0]             gpio_in,
    output wire [15:0]             gpio_out,
    output wire [15:0]             gpio_oe,

    // APB1 control outputs
    output wire [31:0]             ctrl0,
    output wire [31:0]             ctrl1,
    output wire [31:0]             ctrl2,

    // Interrupt debug
    output wire                    irq_out
);

    wire rst = ~rst_n;

    // ------------------------------------------------------------------
    // CPU AXI-Lite master bus
    // ------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] mem_axi_awaddr;
    wire [ 2:0]           mem_axi_awprot;
    wire                  mem_axi_awvalid;
    wire                  mem_axi_awready;
    wire [DATA_WIDTH-1:0] mem_axi_wdata;
    wire [STRB_WIDTH-1:0] mem_axi_wstrb;
    wire                  mem_axi_wvalid;
    wire                  mem_axi_wready;
    wire [ 1:0]           mem_axi_bresp;
    wire                  mem_axi_bvalid;
    wire                  mem_axi_bready;
    wire [ADDR_WIDTH-1:0] mem_axi_araddr;
    wire [ 2:0]           mem_axi_arprot;
    wire                  mem_axi_arvalid;
    wire                  mem_axi_arready;
    wire [DATA_WIDTH-1:0] mem_axi_rdata;
    wire [ 1:0]           mem_axi_rresp;
    wire                  mem_axi_rvalid;
    wire                  mem_axi_rready;

    wire [31:0] irq_vec;
    assign irq_vec = {26'b0, irq_intr, 5'b0};   // external irq on line 5

    picorv32_axi #(
        .ENABLE_COUNTERS  (1),
        .ENABLE_COUNTERS64(1),
        .ENABLE_REGS_16_31(1),
        .ENABLE_REGS_DUALPORT(1),
        .TWO_STAGE_SHIFT  (1),
        .BARREL_SHIFTER   (0),
        .TWO_CYCLE_COMPARE(0),
        .TWO_CYCLE_ALU    (0),
        .COMPRESSED_ISA   (0),
        .CATCH_MISALIGN   (1),
        .CATCH_ILLINSN    (1),
        .ENABLE_PCPI      (0),
        .ENABLE_MUL       (1),
        .ENABLE_FAST_MUL  (0),
        .ENABLE_DIV       (1),
        .ENABLE_IRQ       (1),
        .ENABLE_IRQ_QREGS (1),
        .ENABLE_IRQ_TIMER (1),
        .ENABLE_TRACE     (1),
        .REGS_INIT_ZERO   (0),
        .MASKED_IRQ       (32'h00000000),
        .LATCHED_IRQ      (32'hffffffff),
        .PROGADDR_RESET   (32'h00000000),
        .PROGADDR_IRQ     (32'h00000010),
        .STACKADDR        (32'h00010000)
    ) cpu_inst (
        .clk            (clk),
        .resetn         (cpu_resetn),
        .trap           (cpu_trap),
        .mem_axi_awvalid(mem_axi_awvalid),
        .mem_axi_awready(mem_axi_awready),
        .mem_axi_awaddr (mem_axi_awaddr),
        .mem_axi_awprot (mem_axi_awprot),
        .mem_axi_wvalid (mem_axi_wvalid),
        .mem_axi_wready (mem_axi_wready),
        .mem_axi_wdata  (mem_axi_wdata),
        .mem_axi_wstrb  (mem_axi_wstrb),
        .mem_axi_bvalid (mem_axi_bvalid),
        .mem_axi_bready (mem_axi_bready),
        .mem_axi_arvalid(mem_axi_arvalid),
        .mem_axi_arready(mem_axi_arready),
        .mem_axi_araddr (mem_axi_araddr),
        .mem_axi_arprot (mem_axi_arprot),
        .mem_axi_rvalid (mem_axi_rvalid),
        .mem_axi_rready (mem_axi_rready),
        .mem_axi_rdata  (mem_axi_rdata),
        .irq            (irq_vec),
        .eoi            (),
        .pcpi_valid     (),
        .pcpi_insn      (),
        .pcpi_rs1       (),
        .pcpi_rs2       (),
        .pcpi_wr        (1'b0),
        .pcpi_rd        (32'h0),
        .pcpi_wait      (1'b0),
        .pcpi_ready     (1'b0),
        .trace_valid    (),
        .trace_data     ()
    );

    // ------------------------------------------------------------------
    // Slave AXI-Lite buses (from interconnect)
    // ------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] ram_awaddr;   wire [ 2:0] ram_awprot;   wire ram_awvalid;   wire ram_awready;
    wire [DATA_WIDTH-1:0] ram_wdata;    wire [STRB_WIDTH-1:0] ram_wstrb; wire ram_wvalid; wire ram_wready;
    wire [ 1:0] ram_bresp;              wire ram_bvalid;         wire ram_bready;
    wire [ADDR_WIDTH-1:0] ram_araddr;   wire [ 2:0] ram_arprot;   wire ram_arvalid;   wire ram_arready;
    wire [DATA_WIDTH-1:0] ram_rdata;    wire [ 1:0] ram_rresp;    wire ram_rvalid;    wire ram_rready;

    wire [ADDR_WIDTH-1:0] boot_awaddr;  wire [ 2:0] boot_awprot;  wire boot_awvalid;  wire boot_awready;
    wire [DATA_WIDTH-1:0] boot_wdata;   wire [STRB_WIDTH-1:0] boot_wstrb; wire boot_wvalid; wire boot_wready;
    wire [ 1:0] boot_bresp;             wire boot_bvalid;        wire boot_bready;
    wire [ADDR_WIDTH-1:0] boot_araddr;  wire [ 2:0] boot_arprot;  wire boot_arvalid;  wire boot_arready;
    wire [DATA_WIDTH-1:0] boot_rdata;   wire [ 1:0] boot_rresp;   wire boot_rvalid;   wire boot_rready;

    wire [DATA_WIDTH-1:0] boot_apb0_base;   // APB0 window base (0 = fixed default)
    wire [DATA_WIDTH-1:0] boot_apb1_base;   // APB1 window base (0 = fixed default)

    wire [ADDR_WIDTH-1:0] irq_awaddr;   wire [ 2:0] irq_awprot;   wire irq_awvalid;   wire irq_awready;
    wire [DATA_WIDTH-1:0] irq_wdata;    wire [STRB_WIDTH-1:0] irq_wstrb; wire irq_wvalid; wire irq_wready;
    wire [ 1:0] irq_bresp;              wire irq_bvalid;         wire irq_bready;
    wire [ADDR_WIDTH-1:0] irq_araddr;   wire [ 2:0] irq_arprot;   wire irq_arvalid;   wire irq_arready;
    wire [DATA_WIDTH-1:0] irq_rdata;    wire [ 1:0] irq_rresp;    wire irq_rvalid;    wire irq_rready;

    wire [ADDR_WIDTH-1:0] i2c0_awaddr;  wire [ 2:0] i2c0_awprot;  wire i2c0_awvalid;  wire i2c0_awready;
    wire [DATA_WIDTH-1:0] i2c0_wdata;   wire [STRB_WIDTH-1:0] i2c0_wstrb; wire i2c0_wvalid; wire i2c0_wready;
    wire [ 1:0] i2c0_bresp;             wire i2c0_bvalid;        wire i2c0_bready;
    wire [ADDR_WIDTH-1:0] i2c0_araddr;  wire [ 2:0] i2c0_arprot;  wire i2c0_arvalid;  wire i2c0_arready;
    wire [DATA_WIDTH-1:0] i2c0_rdata;   wire [ 1:0] i2c0_rresp;   wire i2c0_rvalid;   wire i2c0_rready;

    wire [ADDR_WIDTH-1:0] i2c1_awaddr;  wire [ 2:0] i2c1_awprot;  wire i2c1_awvalid;  wire i2c1_awready;
    wire [DATA_WIDTH-1:0] i2c1_wdata;   wire [STRB_WIDTH-1:0] i2c1_wstrb; wire i2c1_wvalid; wire i2c1_wready;
    wire [ 1:0] i2c1_bresp;             wire i2c1_bvalid;        wire i2c1_bready;
    wire [ADDR_WIDTH-1:0] i2c1_araddr;  wire [ 2:0] i2c1_arprot;  wire i2c1_arvalid;  wire i2c1_arready;
    wire [DATA_WIDTH-1:0] i2c1_rdata;   wire [ 1:0] i2c1_rresp;   wire i2c1_rvalid;   wire i2c1_rready;

    wire [ADDR_WIDTH-1:0] i2c2_awaddr;  wire [ 2:0] i2c2_awprot;  wire i2c2_awvalid;  wire i2c2_awready;
    wire [DATA_WIDTH-1:0] i2c2_wdata;   wire [STRB_WIDTH-1:0] i2c2_wstrb; wire i2c2_wvalid; wire i2c2_wready;
    wire [ 1:0] i2c2_bresp;             wire i2c2_bvalid;        wire i2c2_bready;
    wire [ADDR_WIDTH-1:0] i2c2_araddr;  wire [ 2:0] i2c2_arprot;  wire i2c2_arvalid;  wire i2c2_arready;
    wire [DATA_WIDTH-1:0] i2c2_rdata;   wire [ 1:0] i2c2_rresp;   wire i2c2_rvalid;   wire i2c2_rready;

    wire [ADDR_WIDTH-1:0] i2c3_awaddr;  wire [ 2:0] i2c3_awprot;  wire i2c3_awvalid;  wire i2c3_awready;
    wire [DATA_WIDTH-1:0] i2c3_wdata;   wire [STRB_WIDTH-1:0] i2c3_wstrb; wire i2c3_wvalid; wire i2c3_wready;
    wire [ 1:0] i2c3_bresp;             wire i2c3_bvalid;        wire i2c3_bready;
    wire [ADDR_WIDTH-1:0] i2c3_araddr;  wire [ 2:0] i2c3_arprot;  wire i2c3_arvalid;  wire i2c3_arready;
    wire [DATA_WIDTH-1:0] i2c3_rdata;   wire [ 1:0] i2c3_rresp;   wire i2c3_rvalid;   wire i2c3_rready;

    wire [ADDR_WIDTH-1:0] uart0_awaddr; wire [ 2:0] uart0_awprot; wire uart0_awvalid; wire uart0_awready;
    wire [DATA_WIDTH-1:0] uart0_wdata;  wire [STRB_WIDTH-1:0] uart0_wstrb; wire uart0_wvalid; wire uart0_wready;
    wire [ 1:0] uart0_bresp;            wire uart0_bvalid;       wire uart0_bready;
    wire [ADDR_WIDTH-1:0] uart0_araddr; wire [ 2:0] uart0_arprot; wire uart0_arvalid; wire uart0_arready;
    wire [DATA_WIDTH-1:0] uart0_rdata;  wire [ 1:0] uart0_rresp;  wire uart0_rvalid;  wire uart0_rready;

    wire [ADDR_WIDTH-1:0] uart1_awaddr; wire [ 2:0] uart1_awprot; wire uart1_awvalid; wire uart1_awready;
    wire [DATA_WIDTH-1:0] uart1_wdata;  wire [STRB_WIDTH-1:0] uart1_wstrb; wire uart1_wvalid; wire uart1_wready;
    wire [ 1:0] uart1_bresp;            wire uart1_bvalid;       wire uart1_bready;
    wire [ADDR_WIDTH-1:0] uart1_araddr; wire [ 2:0] uart1_arprot; wire uart1_arvalid; wire uart1_arready;
    wire [DATA_WIDTH-1:0] uart1_rdata;  wire [ 1:0] uart1_rresp;  wire uart1_rvalid;  wire uart1_rready;

    wire [ADDR_WIDTH-1:0] apb0_awaddr;  wire [ 2:0] apb0_awprot;  wire apb0_awvalid;  wire apb0_awready;
    wire [DATA_WIDTH-1:0] apb0_wdata;   wire [STRB_WIDTH-1:0] apb0_wstrb; wire apb0_wvalid; wire apb0_wready;
    wire [ 1:0] apb0_bresp;             wire apb0_bvalid;        wire apb0_bready;
    wire [ADDR_WIDTH-1:0] apb0_araddr;  wire [ 2:0] apb0_arprot;  wire apb0_arvalid;  wire apb0_arready;
    wire [DATA_WIDTH-1:0] apb0_rdata;   wire [ 1:0] apb0_rresp;   wire apb0_rvalid;   wire apb0_rready;

    wire [ADDR_WIDTH-1:0] apb1_awaddr;  wire [ 2:0] apb1_awprot;  wire apb1_awvalid;  wire apb1_awready;
    wire [DATA_WIDTH-1:0] apb1_wdata;   wire [STRB_WIDTH-1:0] apb1_wstrb; wire apb1_wvalid; wire apb1_wready;
    wire [ 1:0] apb1_bresp;             wire apb1_bvalid;        wire apb1_bready;
    wire [ADDR_WIDTH-1:0] apb1_araddr;  wire [ 2:0] apb1_arprot;  wire apb1_arvalid;  wire apb1_arready;
    wire [DATA_WIDTH-1:0] apb1_rdata;   wire [ 1:0] apb1_rresp;   wire apb1_rvalid;   wire apb1_rready;

    // ------------------------------------------------------------------
    // AXI-Lite interconnect: 2 masters (CPU + host), 11 slaves
    // ------------------------------------------------------------------
    axil_interconnect #(
        .S_COUNT        (2),
        .M_COUNT        (11),
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .STRB_WIDTH     (STRB_WIDTH),
        .M_REGIONS      (1),
        // field 0 (LSB) = slave port 0 = RAM; every port gets a 64KB (2^16) window
        .M_BASE_ADDR    ({32'h000A0000, 32'h00090000, 32'h00080000, 32'h00070000,
                          32'h00060000, 32'h00050000, 32'h00040000, 32'h00030000,
                          32'h00020000, 32'h00010000, 32'h00000000}),
        .M_ADDR_WIDTH   ({32'd16, 32'd16, 32'd16, 32'd16, 32'd16, 32'd16,
                          32'd16, 32'd16, 32'd16, 32'd16, 32'd16}),
        // ports 9 (APB0) and 10 (APB1) take their base address from the
        // boot_ctrl APB0_BASE / APB1_BASE registers (0 = fixed map above)
        .M_DYNAMIC_BASE (11'b11000000000)
    ) u_ic (
        .clk            (clk),
        .rst            (rst),

        // S0 = CPU, S1 = host
        .s_axil_awaddr  ({s_axil_awaddr,  mem_axi_awaddr}),
        .s_axil_awprot  ({s_axil_awprot,  mem_axi_awprot}),
        .s_axil_awvalid ({s_axil_awvalid, mem_axi_awvalid}),
        .s_axil_awready ({s_axil_awready, mem_axi_awready}),
        .s_axil_wdata   ({s_axil_wdata,   mem_axi_wdata}),
        .s_axil_wstrb   ({s_axil_wstrb,   mem_axi_wstrb}),
        .s_axil_wvalid  ({s_axil_wvalid,  mem_axi_wvalid}),
        .s_axil_wready  ({s_axil_wready,  mem_axi_wready}),
        .s_axil_bresp   ({s_axil_bresp,   mem_axi_bresp}),
        .s_axil_bvalid  ({s_axil_bvalid,  mem_axi_bvalid}),
        .s_axil_bready  ({s_axil_bready,  mem_axi_bready}),
        .s_axil_araddr  ({s_axil_araddr,  mem_axi_araddr}),
        .s_axil_arprot  ({s_axil_arprot,  mem_axi_arprot}),
        .s_axil_arvalid ({s_axil_arvalid, mem_axi_arvalid}),
        .s_axil_arready ({s_axil_arready, mem_axi_arready}),
        .s_axil_rdata   ({s_axil_rdata,   mem_axi_rdata}),
        .s_axil_rresp   ({s_axil_rresp,   mem_axi_rresp}),
        .s_axil_rvalid  ({s_axil_rvalid,  mem_axi_rvalid}),
        .s_axil_rready  ({s_axil_rready,  mem_axi_rready}),

        // M0=RAM M1=BOOT M2=IRQ M3=I2C0 M4=I2C1 M5=I2C2 M6=I2C3
        // M7=UART0 M8=UART1 M9=APB0 M10=APB1
        .m_axil_awaddr  ({apb1_awaddr, apb0_awaddr, uart1_awaddr, uart0_awaddr,
                          i2c3_awaddr, i2c2_awaddr, i2c1_awaddr, i2c0_awaddr,
                          irq_awaddr, boot_awaddr, ram_awaddr}),
        .m_axil_awprot  ({apb1_awprot, apb0_awprot, uart1_awprot, uart0_awprot,
                          i2c3_awprot, i2c2_awprot, i2c1_awprot, i2c0_awprot,
                          irq_awprot, boot_awprot, ram_awprot}),
        .m_axil_awvalid ({apb1_awvalid, apb0_awvalid, uart1_awvalid, uart0_awvalid,
                          i2c3_awvalid, i2c2_awvalid, i2c1_awvalid, i2c0_awvalid,
                          irq_awvalid, boot_awvalid, ram_awvalid}),
        .m_axil_awready ({apb1_awready, apb0_awready, uart1_awready, uart0_awready,
                          i2c3_awready, i2c2_awready, i2c1_awready, i2c0_awready,
                          irq_awready, boot_awready, ram_awready}),
        .m_axil_wdata   ({apb1_wdata, apb0_wdata, uart1_wdata, uart0_wdata,
                          i2c3_wdata, i2c2_wdata, i2c1_wdata, i2c0_wdata,
                          irq_wdata, boot_wdata, ram_wdata}),
        .m_axil_wstrb   ({apb1_wstrb, apb0_wstrb, uart1_wstrb, uart0_wstrb,
                          i2c3_wstrb, i2c2_wstrb, i2c1_wstrb, i2c0_wstrb,
                          irq_wstrb, boot_wstrb, ram_wstrb}),
        .m_axil_wvalid  ({apb1_wvalid, apb0_wvalid, uart1_wvalid, uart0_wvalid,
                          i2c3_wvalid, i2c2_wvalid, i2c1_wvalid, i2c0_wvalid,
                          irq_wvalid, boot_wvalid, ram_wvalid}),
        .m_axil_wready  ({apb1_wready, apb0_wready, uart1_wready, uart0_wready,
                          i2c3_wready, i2c2_wready, i2c1_wready, i2c0_wready,
                          irq_wready, boot_wready, ram_wready}),
        .m_axil_bresp   ({apb1_bresp, apb0_bresp, uart1_bresp, uart0_bresp,
                          i2c3_bresp, i2c2_bresp, i2c1_bresp, i2c0_bresp,
                          irq_bresp, boot_bresp, ram_bresp}),
        .m_axil_bvalid  ({apb1_bvalid, apb0_bvalid, uart1_bvalid, uart0_bvalid,
                          i2c3_bvalid, i2c2_bvalid, i2c1_bvalid, i2c0_bvalid,
                          irq_bvalid, boot_bvalid, ram_bvalid}),
        .m_axil_bready  ({apb1_bready, apb0_bready, uart1_bready, uart0_bready,
                          i2c3_bready, i2c2_bready, i2c1_bready, i2c0_bready,
                          irq_bready, boot_bready, ram_bready}),
        .m_axil_araddr  ({apb1_araddr, apb0_araddr, uart1_araddr, uart0_araddr,
                          i2c3_araddr, i2c2_araddr, i2c1_araddr, i2c0_araddr,
                          irq_araddr, boot_araddr, ram_araddr}),
        .m_axil_arprot  ({apb1_arprot, apb0_arprot, uart1_arprot, uart0_arprot,
                          i2c3_arprot, i2c2_arprot, i2c1_arprot, i2c0_arprot,
                          irq_arprot, boot_arprot, ram_arprot}),
        .m_axil_arvalid ({apb1_arvalid, apb0_arvalid, uart1_arvalid, uart0_arvalid,
                          i2c3_arvalid, i2c2_arvalid, i2c1_arvalid, i2c0_arvalid,
                          irq_arvalid, boot_arvalid, ram_arvalid}),
        .m_axil_arready ({apb1_arready, apb0_arready, uart1_arready, uart0_arready,
                          i2c3_arready, i2c2_arready, i2c1_arready, i2c0_arready,
                          irq_arready, boot_arready, ram_arready}),
        .m_axil_rdata   ({apb1_rdata, apb0_rdata, uart1_rdata, uart0_rdata,
                          i2c3_rdata, i2c2_rdata, i2c1_rdata, i2c0_rdata,
                          irq_rdata, boot_rdata, ram_rdata}),
        .m_axil_rresp   ({apb1_rresp, apb0_rresp, uart1_rresp, uart0_rresp,
                          i2c3_rresp, i2c2_rresp, i2c1_rresp, i2c0_rresp,
                          irq_rresp, boot_rresp, ram_rresp}),
        .m_axil_rvalid  ({apb1_rvalid, apb0_rvalid, uart1_rvalid, uart0_rvalid,
                          i2c3_rvalid, i2c2_rvalid, i2c1_rvalid, i2c0_rvalid,
                          irq_rvalid, boot_rvalid, ram_rvalid}),
        .m_axil_rready  ({apb1_rready, apb0_rready, uart1_rready, uart0_rready,
                          i2c3_rready, i2c2_rready, i2c1_rready, i2c0_rready,
                          irq_rready, boot_rready, ram_rready}),
        // dynamic bases: port 10=APB1, port 9=APB0, others unused (0)
        .m_axil_base_addr ({boot_apb1_base, boot_apb0_base, 9*{32'd0}})
    );

    // ------------------------------------------------------------------
    // Slave 0: RAM
    // ------------------------------------------------------------------
    axil_ram #(
        .ADDR_WIDTH (RAM_ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .STRB_WIDTH (STRB_WIDTH)
    ) u_ram (
        .clk            (clk),
        .rst            (rst),
        .s_axil_awaddr  (ram_awaddr[RAM_ADDR_WIDTH-1:0]),
        .s_axil_awprot  (ram_awprot),
        .s_axil_awvalid (ram_awvalid),
        .s_axil_awready (ram_awready),
        .s_axil_wdata   (ram_wdata),
        .s_axil_wstrb   (ram_wstrb),
        .s_axil_wvalid  (ram_wvalid),
        .s_axil_wready  (ram_wready),
        .s_axil_bresp   (ram_bresp),
        .s_axil_bvalid  (ram_bvalid),
        .s_axil_bready  (ram_bready),
        .s_axil_araddr  (ram_araddr[RAM_ADDR_WIDTH-1:0]),
        .s_axil_arprot  (ram_arprot),
        .s_axil_arvalid (ram_arvalid),
        .s_axil_arready (ram_arready),
        .s_axil_rdata   (ram_rdata),
        .s_axil_rresp   (ram_rresp),
        .s_axil_rvalid  (ram_rvalid),
        .s_axil_rready  (ram_rready)
    );

    // ------------------------------------------------------------------
    // Slave 1: boot control (CPU reset)
    // ------------------------------------------------------------------
    boot_ctrl #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_boot (
        .clk            (clk),
        .rst            (rst),
        .s_axil_awaddr  (boot_awaddr[3:0]),
        .s_axil_awprot  (boot_awprot),
        .s_axil_awvalid (boot_awvalid),
        .s_axil_awready (boot_awready),
        .s_axil_wdata   (boot_wdata),
        .s_axil_wstrb   (boot_wstrb),
        .s_axil_wvalid  (boot_wvalid),
        .s_axil_wready  (boot_wready),
        .s_axil_bresp   (boot_bresp),
        .s_axil_bvalid  (boot_bvalid),
        .s_axil_bready  (boot_bready),
        .s_axil_araddr  (boot_araddr[3:0]),
        .s_axil_arprot  (boot_arprot),
        .s_axil_arvalid (boot_arvalid),
        .s_axil_arready (boot_arready),
        .s_axil_rdata   (boot_rdata),
        .s_axil_rresp   (boot_rresp),
        .s_axil_rvalid  (boot_rvalid),
        .s_axil_rready  (boot_rready),
        .cpu_trap       (cpu_trap),
        .cpu_resetn     (cpu_resetn),
        .apb0_base      (boot_apb0_base),
        .apb1_base      (boot_apb1_base)
    );

    // ------------------------------------------------------------------
    // Slave 2: interrupt controller
    // ------------------------------------------------------------------
    wire [15:0] irq_src;
    wire        irq_intr;

    assign irq_src[0] = uart0_int_rx;
    assign irq_src[1] = uart0_int_tx;
    assign irq_src[2] = uart1_int_rx;
    assign irq_src[3] = uart1_int_tx;
    assign irq_src[4] = timer0_irq;
    assign irq_src[5] = timer1_irq;
    assign irq_src[6] = gpio_intr;
    assign irq_src[15:7] = 9'b0;

    irq_ctrl #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_irq (
        .clk            (clk),
        .rst            (rst),
        .s_axil_awaddr  (irq_awaddr[3:0]),
        .s_axil_awprot  (irq_awprot),
        .s_axil_awvalid (irq_awvalid),
        .s_axil_awready (irq_awready),
        .s_axil_wdata   (irq_wdata),
        .s_axil_wstrb   (irq_wstrb),
        .s_axil_wvalid  (irq_wvalid),
        .s_axil_wready  (irq_wready),
        .s_axil_bresp   (irq_bresp),
        .s_axil_bvalid  (irq_bvalid),
        .s_axil_bready  (irq_bready),
        .s_axil_araddr  (irq_araddr[3:0]),
        .s_axil_arprot  (irq_arprot),
        .s_axil_arvalid (irq_arvalid),
        .s_axil_arready (irq_arready),
        .s_axil_rdata   (irq_rdata),
        .s_axil_rresp   (irq_rresp),
        .s_axil_rvalid  (irq_rvalid),
        .s_axil_rready  (irq_rready),
        .irq_src        (irq_src),
        .intr           (irq_intr)
    );

    assign irq_out = irq_intr;

    // ------------------------------------------------------------------
    // Slaves 3-6: I2C
    // ------------------------------------------------------------------
    wire i2c0_scl_i, i2c0_scl_o, i2c0_scl_t, i2c0_sda_i, i2c0_sda_o, i2c0_sda_t;
    wire i2c1_scl_i, i2c1_scl_o, i2c1_scl_t, i2c1_sda_i, i2c1_sda_o, i2c1_sda_t;
    wire i2c2_scl_i, i2c2_scl_o, i2c2_scl_t, i2c2_sda_i, i2c2_sda_o, i2c2_sda_t;
    wire i2c3_scl_i, i2c3_scl_o, i2c3_scl_t, i2c3_sda_i, i2c3_sda_o, i2c3_sda_t;

    // open-drain pads
    assign i2c0_scl = i2c0_scl_t ? 1'bz : i2c0_scl_o;
    assign i2c0_sda = i2c0_sda_t ? 1'bz : i2c0_sda_o;
    assign i2c0_scl_i = i2c0_scl;
    assign i2c0_sda_i = i2c0_sda;
    assign i2c1_scl = i2c1_scl_t ? 1'bz : i2c1_scl_o;
    assign i2c1_sda = i2c1_sda_t ? 1'bz : i2c1_sda_o;
    assign i2c1_scl_i = i2c1_scl;
    assign i2c1_sda_i = i2c1_sda;
    assign i2c2_scl = i2c2_scl_t ? 1'bz : i2c2_scl_o;
    assign i2c2_sda = i2c2_sda_t ? 1'bz : i2c2_sda_o;
    assign i2c2_scl_i = i2c2_scl;
    assign i2c2_sda_i = i2c2_sda;
    assign i2c3_scl = i2c3_scl_t ? 1'bz : i2c3_scl_o;
    assign i2c3_sda = i2c3_sda_t ? 1'bz : i2c3_sda_o;
    assign i2c3_scl_i = i2c3_scl;
    assign i2c3_sda_i = i2c3_sda;

    i2c_master_axil #(
        .DEFAULT_PRESCALE (1),
        .FIXED_PRESCALE   (0),
        .CMD_FIFO         (1),
        .CMD_FIFO_DEPTH   (32),
        .WRITE_FIFO       (1),
        .WRITE_FIFO_DEPTH (32),
        .READ_FIFO        (1),
        .READ_FIFO_DEPTH  (32)
    ) u_i2c0 (
        .clk        (clk),
        .rst        (rst),
        .s_axil_awaddr (i2c0_awaddr[3:0]),
        .s_axil_awprot (i2c0_awprot),
        .s_axil_awvalid(i2c0_awvalid),
        .s_axil_awready(i2c0_awready),
        .s_axil_wdata  (i2c0_wdata),
        .s_axil_wstrb  (i2c0_wstrb),
        .s_axil_wvalid (i2c0_wvalid),
        .s_axil_wready (i2c0_wready),
        .s_axil_bresp  (i2c0_bresp),
        .s_axil_bvalid (i2c0_bvalid),
        .s_axil_bready (i2c0_bready),
        .s_axil_araddr (i2c0_araddr[3:0]),
        .s_axil_arprot (i2c0_arprot),
        .s_axil_arvalid(i2c0_arvalid),
        .s_axil_arready(i2c0_arready),
        .s_axil_rdata  (i2c0_rdata),
        .s_axil_rresp  (i2c0_rresp),
        .s_axil_rvalid (i2c0_rvalid),
        .s_axil_rready (i2c0_rready),
        .i2c_scl_i (i2c0_scl_i),
        .i2c_scl_o (i2c0_scl_o),
        .i2c_scl_t (i2c0_scl_t),
        .i2c_sda_i (i2c0_sda_i),
        .i2c_sda_o (i2c0_sda_o),
        .i2c_sda_t (i2c0_sda_t)
    );

    i2c_master_axil #(
        .DEFAULT_PRESCALE (1),
        .FIXED_PRESCALE   (0),
        .CMD_FIFO         (1),
        .CMD_FIFO_DEPTH   (32),
        .WRITE_FIFO       (1),
        .WRITE_FIFO_DEPTH (32),
        .READ_FIFO        (1),
        .READ_FIFO_DEPTH  (32)
    ) u_i2c1 (
        .clk        (clk),
        .rst        (rst),
        .s_axil_awaddr (i2c1_awaddr[3:0]),
        .s_axil_awprot (i2c1_awprot),
        .s_axil_awvalid(i2c1_awvalid),
        .s_axil_awready(i2c1_awready),
        .s_axil_wdata  (i2c1_wdata),
        .s_axil_wstrb  (i2c1_wstrb),
        .s_axil_wvalid (i2c1_wvalid),
        .s_axil_wready (i2c1_wready),
        .s_axil_bresp  (i2c1_bresp),
        .s_axil_bvalid (i2c1_bvalid),
        .s_axil_bready (i2c1_bready),
        .s_axil_araddr (i2c1_araddr[3:0]),
        .s_axil_arprot (i2c1_arprot),
        .s_axil_arvalid(i2c1_arvalid),
        .s_axil_arready(i2c1_arready),
        .s_axil_rdata  (i2c1_rdata),
        .s_axil_rresp  (i2c1_rresp),
        .s_axil_rvalid (i2c1_rvalid),
        .s_axil_rready (i2c1_rready),
        .i2c_scl_i (i2c1_scl_i),
        .i2c_scl_o (i2c1_scl_o),
        .i2c_scl_t (i2c1_scl_t),
        .i2c_sda_i (i2c1_sda_i),
        .i2c_sda_o (i2c1_sda_o),
        .i2c_sda_t (i2c1_sda_t)
    );

    i2c_master_axil #(
        .DEFAULT_PRESCALE (1),
        .FIXED_PRESCALE   (0),
        .CMD_FIFO         (1),
        .CMD_FIFO_DEPTH   (32),
        .WRITE_FIFO       (1),
        .WRITE_FIFO_DEPTH (32),
        .READ_FIFO        (1),
        .READ_FIFO_DEPTH  (32)
    ) u_i2c2 (
        .clk        (clk),
        .rst        (rst),
        .s_axil_awaddr (i2c2_awaddr[3:0]),
        .s_axil_awprot (i2c2_awprot),
        .s_axil_awvalid(i2c2_awvalid),
        .s_axil_awready(i2c2_awready),
        .s_axil_wdata  (i2c2_wdata),
        .s_axil_wstrb  (i2c2_wstrb),
        .s_axil_wvalid (i2c2_wvalid),
        .s_axil_wready (i2c2_wready),
        .s_axil_bresp  (i2c2_bresp),
        .s_axil_bvalid (i2c2_bvalid),
        .s_axil_bready (i2c2_bready),
        .s_axil_araddr (i2c2_araddr[3:0]),
        .s_axil_arprot (i2c2_arprot),
        .s_axil_arvalid(i2c2_arvalid),
        .s_axil_arready(i2c2_arready),
        .s_axil_rdata  (i2c2_rdata),
        .s_axil_rresp  (i2c2_rresp),
        .s_axil_rvalid (i2c2_rvalid),
        .s_axil_rready (i2c2_rready),
        .i2c_scl_i (i2c2_scl_i),
        .i2c_scl_o (i2c2_scl_o),
        .i2c_scl_t (i2c2_scl_t),
        .i2c_sda_i (i2c2_sda_i),
        .i2c_sda_o (i2c2_sda_o),
        .i2c_sda_t (i2c2_sda_t)
    );

    i2c_master_axil #(
        .DEFAULT_PRESCALE (1),
        .FIXED_PRESCALE   (0),
        .CMD_FIFO         (1),
        .CMD_FIFO_DEPTH   (32),
        .WRITE_FIFO       (1),
        .WRITE_FIFO_DEPTH (32),
        .READ_FIFO        (1),
        .READ_FIFO_DEPTH  (32)
    ) u_i2c3 (
        .clk        (clk),
        .rst        (rst),
        .s_axil_awaddr (i2c3_awaddr[3:0]),
        .s_axil_awprot (i2c3_awprot),
        .s_axil_awvalid(i2c3_awvalid),
        .s_axil_awready(i2c3_awready),
        .s_axil_wdata  (i2c3_wdata),
        .s_axil_wstrb  (i2c3_wstrb),
        .s_axil_wvalid (i2c3_wvalid),
        .s_axil_wready (i2c3_wready),
        .s_axil_bresp  (i2c3_bresp),
        .s_axil_bvalid (i2c3_bvalid),
        .s_axil_bready (i2c3_bready),
        .s_axil_araddr (i2c3_araddr[3:0]),
        .s_axil_arprot (i2c3_arprot),
        .s_axil_arvalid(i2c3_arvalid),
        .s_axil_arready(i2c3_arready),
        .s_axil_rdata  (i2c3_rdata),
        .s_axil_rresp  (i2c3_rresp),
        .s_axil_rvalid (i2c3_rvalid),
        .s_axil_rready (i2c3_rready),
        .i2c_scl_i (i2c3_scl_i),
        .i2c_scl_o (i2c3_scl_o),
        .i2c_scl_t (i2c3_scl_t),
        .i2c_sda_i (i2c3_sda_i),
        .i2c_sda_o (i2c3_sda_o),
        .i2c_sda_t (i2c3_sda_t)
    );

    // ------------------------------------------------------------------
    // Slaves 7-8: UART
    // ------------------------------------------------------------------
    wire uart0_int_rx, uart0_int_tx;
    wire uart1_int_rx, uart1_int_tx;

    uart_axil #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_uart0 (
        .clk         (clk),
        .rst         (rst),
        .s_axil_awaddr (uart0_awaddr[3:0]),
        .s_axil_awprot (uart0_awprot),
        .s_axil_awvalid(uart0_awvalid),
        .s_axil_awready(uart0_awready),
        .s_axil_wdata  (uart0_wdata),
        .s_axil_wstrb  (uart0_wstrb),
        .s_axil_wvalid (uart0_wvalid),
        .s_axil_wready (uart0_wready),
        .s_axil_bresp  (uart0_bresp),
        .s_axil_bvalid (uart0_bvalid),
        .s_axil_bready (uart0_bready),
        .s_axil_araddr (uart0_araddr[3:0]),
        .s_axil_arprot (uart0_arprot),
        .s_axil_arvalid(uart0_arvalid),
        .s_axil_arready(uart0_arready),
        .s_axil_rdata  (uart0_rdata),
        .s_axil_rresp  (uart0_rresp),
        .s_axil_rvalid (uart0_rvalid),
        .s_axil_rready (uart0_rready),
        .ser_tx        (uart0_txd),
        .ser_rx        (uart0_rxd),
        .int_rx        (uart0_int_rx),
        .int_tx        (uart0_int_tx)
    );

    uart_axil #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_uart1 (
        .clk         (clk),
        .rst         (rst),
        .s_axil_awaddr (uart1_awaddr[3:0]),
        .s_axil_awprot (uart1_awprot),
        .s_axil_awvalid(uart1_awvalid),
        .s_axil_awready(uart1_awready),
        .s_axil_wdata  (uart1_wdata),
        .s_axil_wstrb  (uart1_wstrb),
        .s_axil_wvalid (uart1_wvalid),
        .s_axil_wready (uart1_wready),
        .s_axil_bresp  (uart1_bresp),
        .s_axil_bvalid (uart1_bvalid),
        .s_axil_bready (uart1_bready),
        .s_axil_araddr (uart1_araddr[3:0]),
        .s_axil_arprot (uart1_arprot),
        .s_axil_arvalid(uart1_arvalid),
        .s_axil_arready(uart1_arready),
        .s_axil_rdata  (uart1_rdata),
        .s_axil_rresp  (uart1_rresp),
        .s_axil_rvalid (uart1_rvalid),
        .s_axil_rready (uart1_rready),
        .ser_tx        (uart1_txd),
        .ser_rx        (uart1_rxd),
        .int_rx        (uart1_int_rx),
        .int_tx        (uart1_int_tx)
    );

    // ------------------------------------------------------------------
    // Slave 9: APB0 (GPIO + TIMER0)
    // ------------------------------------------------------------------
    wire        apb0_psel, apb0_penable, apb0_pwrite;
    wire [15:0] apb0_paddr;
    wire [DATA_WIDTH-1:0] apb0_pwdata;
    wire [STRB_WIDTH-1:0] apb0_pstrb;
    wire [DATA_WIDTH-1:0] apb0_prdata;
    wire        apb0_pready;
    wire        apb0_pslverr;

    wire gpio_intr;
    wire timer0_irq;

    axil2apb #(
        .ADDR_WIDTH (16),
        .DATA_WIDTH (DATA_WIDTH),
        .STRB_WIDTH (STRB_WIDTH)
    ) u_apb0_bridge (
        .clk         (clk),
        .rst         (rst),
        .s_axil_awaddr (apb0_awaddr[15:0]),
        .s_axil_awprot (apb0_awprot),
        .s_axil_awvalid(apb0_awvalid),
        .s_axil_awready(apb0_awready),
        .s_axil_wdata  (apb0_wdata),
        .s_axil_wstrb  (apb0_wstrb),
        .s_axil_wvalid (apb0_wvalid),
        .s_axil_wready (apb0_wready),
        .s_axil_bresp  (apb0_bresp),
        .s_axil_bvalid (apb0_bvalid),
        .s_axil_bready (apb0_bready),
        .s_axil_araddr (apb0_araddr[15:0]),
        .s_axil_arprot (apb0_arprot),
        .s_axil_arvalid(apb0_arvalid),
        .s_axil_arready(apb0_arready),
        .s_axil_rdata  (apb0_rdata),
        .s_axil_rresp  (apb0_rresp),
        .s_axil_rvalid (apb0_rvalid),
        .s_axil_rready (apb0_rready),
        .apb_paddr   (apb0_paddr),
        .apb_psel    (apb0_psel),
        .apb_penable (apb0_penable),
        .apb_pwrite  (apb0_pwrite),
        .apb_pwdata  (apb0_pwdata),
        .apb_pstrb   (apb0_pstrb),
        .apb_prdata  (apb0_prdata),
        .apb_pready  (apb0_pready),
        .apb_pslverr (apb0_pslverr)
    );

    wire        apb0_s0_psel, apb0_s1_psel;
    wire [DATA_WIDTH-1:0] apb0_s0_prdata, apb0_s1_prdata;
    wire        apb0_s0_pready, apb0_s1_pready;
    wire        apb0_s0_pslverr, apb0_s1_pslverr;

    apb_interconnect #(
        .ADDR_WIDTH   (16),
        .DATA_WIDTH   (DATA_WIDTH),
        .S_COUNT      (2),
        .S_BASE_ADDR  ({16'h1000, 16'h0000}),   // S0=GPIO@0x0000, S1=TIMER0@0x1000
        .S_ADDR_WIDTH ({32'd12, 32'd12})
    ) u_apb0_ic (
        .clk         (clk),
        .rst         (rst),
        .apb_paddr   (apb0_paddr),
        .apb_psel    (apb0_psel),
        .apb_penable (apb0_penable),
        .apb_pwrite  (apb0_pwrite),
        .apb_pwdata  (apb0_pwdata),
        .apb_pstrb   (apb0_pstrb),
        .apb_prdata  (apb0_prdata),
        .apb_pready  (apb0_pready),
        .apb_pslverr (apb0_pslverr),
        .s_psel      ({apb0_s1_psel, apb0_s0_psel}),
        .s_paddr     (),
        .s_penable   (),
        .s_pwrite    (),
        .s_pwdata    (),
        .s_pstrb     (),
        .s_prdata    ({apb0_s1_prdata, apb0_s0_prdata}),
        .s_pready    ({apb0_s1_pready, apb0_s0_pready}),
        .s_pslverr   ({apb0_s1_pslverr, apb0_s0_pslverr})
    );

    apb_gpio #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_gpio (
        .clk       (clk),
        .rst       (rst),
        .psel      (apb0_s0_psel),
        .penable   (apb0_penable),
        .paddr     (apb0_paddr[11:0]),
        .pwrite    (apb0_pwrite),
        .pwdata    (apb0_pwdata),
        .pstrb     (apb0_pstrb),
        .prdata    (apb0_s0_prdata),
        .pready    (apb0_s0_pready),
        .pslverr   (apb0_s0_pslverr),
        .gpio_out  (gpio_out),
        .gpio_oe   (gpio_oe),
        .gpio_in   (gpio_in),
        .gpio_intr (gpio_intr)
    );

    apb_timer #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_timer0 (
        .clk       (clk),
        .rst       (rst),
        .psel      (apb0_s1_psel),
        .penable   (apb0_penable),
        .paddr     (apb0_paddr[11:0]),
        .pwrite    (apb0_pwrite),
        .pwdata    (apb0_pwdata),
        .pstrb     (apb0_pstrb),
        .prdata    (apb0_s1_prdata),
        .pready    (apb0_s1_pready),
        .pslverr   (apb0_s1_pslverr),
        .timer_irq (timer0_irq)
    );

    // ------------------------------------------------------------------
    // Slave 10: APB1 (CTRL + TIMER1)
    // ------------------------------------------------------------------
    wire        apb1_psel, apb1_penable, apb1_pwrite;
    wire [15:0] apb1_paddr;
    wire [DATA_WIDTH-1:0] apb1_pwdata;
    wire [STRB_WIDTH-1:0] apb1_pstrb;
    wire [DATA_WIDTH-1:0] apb1_prdata;
    wire        apb1_pready;
    wire        apb1_pslverr;

    wire timer1_irq;

    axil2apb #(
        .ADDR_WIDTH (16),
        .DATA_WIDTH (DATA_WIDTH),
        .STRB_WIDTH (STRB_WIDTH)
    ) u_apb1_bridge (
        .clk         (clk),
        .rst         (rst),
        .s_axil_awaddr (apb1_awaddr[15:0]),
        .s_axil_awprot (apb1_awprot),
        .s_axil_awvalid(apb1_awvalid),
        .s_axil_awready(apb1_awready),
        .s_axil_wdata  (apb1_wdata),
        .s_axil_wstrb  (apb1_wstrb),
        .s_axil_wvalid (apb1_wvalid),
        .s_axil_wready (apb1_wready),
        .s_axil_bresp  (apb1_bresp),
        .s_axil_bvalid (apb1_bvalid),
        .s_axil_bready (apb1_bready),
        .s_axil_araddr (apb1_araddr[15:0]),
        .s_axil_arprot (apb1_arprot),
        .s_axil_arvalid(apb1_arvalid),
        .s_axil_arready(apb1_arready),
        .s_axil_rdata  (apb1_rdata),
        .s_axil_rresp  (apb1_rresp),
        .s_axil_rvalid (apb1_rvalid),
        .s_axil_rready (apb1_rready),
        .apb_paddr   (apb1_paddr),
        .apb_psel    (apb1_psel),
        .apb_penable (apb1_penable),
        .apb_pwrite  (apb1_pwrite),
        .apb_pwdata  (apb1_pwdata),
        .apb_pstrb   (apb1_pstrb),
        .apb_prdata  (apb1_prdata),
        .apb_pready  (apb1_pready),
        .apb_pslverr (apb1_pslverr)
    );

    wire        apb1_s0_psel, apb1_s1_psel;
    wire [DATA_WIDTH-1:0] apb1_s0_prdata, apb1_s1_prdata;
    wire        apb1_s0_pready, apb1_s1_pready;
    wire        apb1_s0_pslverr, apb1_s1_pslverr;

    apb_interconnect #(
        .ADDR_WIDTH   (16),
        .DATA_WIDTH   (DATA_WIDTH),
        .S_COUNT      (2),
        .S_BASE_ADDR  ({16'h1000, 16'h0000}),   // S0=CTRL@0x0000, S1=TIMER1@0x1000
        .S_ADDR_WIDTH ({32'd12, 32'd12})
    ) u_apb1_ic (
        .clk         (clk),
        .rst         (rst),
        .apb_paddr   (apb1_paddr),
        .apb_psel    (apb1_psel),
        .apb_penable (apb1_penable),
        .apb_pwrite  (apb1_pwrite),
        .apb_pwdata  (apb1_pwdata),
        .apb_pstrb   (apb1_pstrb),
        .apb_prdata  (apb1_prdata),
        .apb_pready  (apb1_pready),
        .apb_pslverr (apb1_pslverr),
        .s_psel      ({apb1_s1_psel, apb1_s0_psel}),
        .s_paddr     (),
        .s_penable   (),
        .s_pwrite    (),
        .s_pwdata    (),
        .s_pstrb     (),
        .s_prdata    ({apb1_s1_prdata, apb1_s0_prdata}),
        .s_pready    ({apb1_s1_pready, apb1_s0_pready}),
        .s_pslverr   ({apb1_s1_pslverr, apb1_s0_pslverr})
    );

    apb_ctrl #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_ctrl (
        .clk       (clk),
        .rst       (rst),
        .psel      (apb1_s0_psel),
        .penable   (apb1_penable),
        .paddr     (apb1_paddr[11:0]),
        .pwrite    (apb1_pwrite),
        .pwdata    (apb1_pwdata),
        .pstrb     (apb1_pstrb),
        .prdata    (apb1_s0_prdata),
        .pready    (apb1_s0_pready),
        .pslverr   (apb1_s0_pslverr),
        .ctrl0     (ctrl0),
        .ctrl1     (ctrl1),
        .ctrl2     (ctrl2)
    );

    apb_timer #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_timer1 (
        .clk       (clk),
        .rst       (rst),
        .psel      (apb1_s1_psel),
        .penable   (apb1_penable),
        .paddr     (apb1_paddr[11:0]),
        .pwrite    (apb1_pwrite),
        .pwdata    (apb1_pwdata),
        .pstrb     (apb1_pstrb),
        .prdata    (apb1_s1_prdata),
        .pready    (apb1_s1_pready),
        .pslverr   (apb1_s1_pslverr),
        .timer_irq (timer1_irq)
    );

endmodule
