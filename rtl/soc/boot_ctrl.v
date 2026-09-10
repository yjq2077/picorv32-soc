// boot_ctrl.v - AXI-Lite slave register block on the download port
// Controls the PicoRV32 reset: host holds CPU in reset, downloads
// firmware to RAM, then releases reset by setting CTRL[0].
//
// Registers (4-bit address, 32-bit data):
//   0x00  CTRL      (RW) bit0 = cpu_resetn  (1=release, 0=hold reset)
//   0x04  STATUS    (RO) bit0 = cpu_resetn readback
//                         bit1 = cpu_trap (PicoRV32 trap output)
//   0x08  APB0_BASE (RW) base added to the APB0 address lines (0 = offset only)
//   0x0C  APB1_BASE (RW) base added to the APB1 address lines (0 = offset only)
module boot_ctrl #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32
) (
    input  wire clk,
    input  wire rst,

    // AXI-Lite slave interface
    input  wire [3:0]             s_axil_awaddr,
    input  wire [ 2:0]            s_axil_awprot,
    input  wire                   s_axil_awvalid,
    output wire                   s_axil_awready,
    input  wire [DATA_WIDTH-1:0]  s_axil_wdata,
    input  wire [DATA_WIDTH/8-1:0]s_axil_wstrb,
    input  wire                   s_axil_wvalid,
    output wire                   s_axil_wready,
    output wire [ 1:0]            s_axil_bresp,
    output wire                   s_axil_bvalid,
    input  wire                   s_axil_bready,
    input  wire [3:0]             s_axil_araddr,
    input  wire [ 2:0]            s_axil_arprot,
    input  wire                   s_axil_arvalid,
    output wire                   s_axil_arready,
    output wire [DATA_WIDTH-1:0]  s_axil_rdata,
    output wire [ 1:0]            s_axil_rresp,
    output wire                   s_axil_rvalid,
    input  wire                   s_axil_rready,

    // Control interface
    input  wire                   cpu_trap,
    output wire                   cpu_resetn,

    // APB window base addresses (0 = use fixed default map in soc_top)
    output wire [DATA_WIDTH-1:0]  apb0_base,
    output wire [DATA_WIDTH-1:0]  apb1_base
);

    localparam [1:0] IDLE = 2'd0, W_RESP = 2'd1, R_RESP = 2'd2;

    reg [1:0] state;
    reg [DATA_WIDTH-1:0] ctrl;
    reg [DATA_WIDTH-1:0] apb0_base_reg;
    reg [DATA_WIDTH-1:0] apb1_base_reg;
    reg [DATA_WIDTH-1:0] rdata;
    reg aw_hs, w_hs, ar_hs;

    assign s_axil_awready = (state == IDLE) && !aw_hs && !ar_hs;
    assign s_axil_wready  = (state == IDLE) && !w_hs  && !ar_hs;
    assign s_axil_arready = (state == IDLE) && !aw_hs && !ar_hs;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_bvalid  = (state == W_RESP);
    assign s_axil_rvalid  = (state == R_RESP);
    assign s_axil_rdata   = rdata;
    assign cpu_resetn     = ctrl[0];
    assign apb0_base      = apb0_base_reg;
    assign apb1_base      = apb1_base_reg;

    wire write_en = aw_hs && w_hs;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            ctrl  <= 0;            // default: hold CPU in reset
            apb0_base_reg <= 0;    // default: fixed APB0 map (0x00090000)
            apb1_base_reg <= 0;    // default: fixed APB1 map (0x000A0000)
            rdata <= 0;
            aw_hs <= 0;
            w_hs  <= 0;
            ar_hs <= 0;
        end else begin
            case (state)
                IDLE: begin
                    // capture address/data handshakes independently
                    if (aw_hs && w_hs) begin
                        // write data
                        if (s_axil_awaddr == 4'h0) begin
                            if (s_axil_wstrb[0]) ctrl[7:0] <= s_axil_wdata[7:0];
                        end else if (s_axil_awaddr == 4'h8) begin
                            if (s_axil_wstrb[0]) apb0_base_reg[7:0]   <= s_axil_wdata[7:0];
                            if (s_axil_wstrb[1]) apb0_base_reg[15:8]  <= s_axil_wdata[15:8];
                            if (s_axil_wstrb[2]) apb0_base_reg[23:16] <= s_axil_wdata[23:16];
                            if (s_axil_wstrb[3]) apb0_base_reg[31:24] <= s_axil_wdata[31:24];
                        end else if (s_axil_awaddr == 4'hC) begin
                            if (s_axil_wstrb[0]) apb1_base_reg[7:0]   <= s_axil_wdata[7:0];
                            if (s_axil_wstrb[1]) apb1_base_reg[15:8]  <= s_axil_wdata[15:8];
                            if (s_axil_wstrb[2]) apb1_base_reg[23:16] <= s_axil_wdata[23:16];
                            if (s_axil_wstrb[3]) apb1_base_reg[31:24] <= s_axil_wdata[31:24];
                        end
                        aw_hs <= 0; w_hs <= 0;
                        state <= W_RESP;
                    end else begin
                        if (s_axil_awvalid && !aw_hs) aw_hs <= 1;
                        if (s_axil_wvalid  && !w_hs)  w_hs  <= 1;
                        if (s_axil_arvalid && !ar_hs) begin
                            // read data
                            case (s_axil_araddr)
                                4'h0: rdata <= {31'b0, ctrl[0]};
                                4'h4: rdata <= {30'b0, cpu_trap, ctrl[0]};
                                4'h8: rdata <= apb0_base_reg;
                                4'hC: rdata <= apb1_base_reg;
                                default: rdata <= 32'h0;
                            endcase
                            ar_hs <= 1;
                            state <= R_RESP;
                        end
                    end
                end
                W_RESP: begin
                    if (s_axil_bready) state <= IDLE;
                end
                R_RESP: begin
                    if (s_axil_rready) begin
                        ar_hs <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
