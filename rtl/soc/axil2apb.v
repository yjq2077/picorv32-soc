`resetall
`timescale 1ns / 1ps
`default_nettype none

// axil2apb.v - AXI4-Lite slave to APB3 master bridge
// One transaction at a time; supports independent AW/W or combined handshake.
module axil2apb #(
    parameter integer ADDR_WIDTH = 16,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH/8
) (
    input  wire clk,
    input  wire rst,

    // AXI-Lite slave interface
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

    // APB master interface
    output wire [ADDR_WIDTH-1:0]   apb_paddr,
    output wire                    apb_psel,
    output wire                    apb_penable,
    output wire                    apb_pwrite,
    output wire [DATA_WIDTH-1:0]   apb_pwdata,
    output wire [STRB_WIDTH-1:0]   apb_pstrb,
    input  wire [DATA_WIDTH-1:0]   apb_prdata,
    input  wire                    apb_pready,
    input  wire                    apb_pslverr
);

    localparam [1:0] IDLE = 2'd0, SETUP = 2'd1, ACCESS = 2'd2, RESP = 2'd3;

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [DATA_WIDTH-1:0] wdata_reg;
    reg [STRB_WIDTH-1:0] wstrb_reg;
    reg [DATA_WIDTH-1:0] rdata_reg;
    reg is_write;
    reg bvalid_reg, rvalid_reg;

    assign s_axil_awready = (state == IDLE) && s_axil_awvalid && s_axil_wvalid;
    assign s_axil_wready  = (state == IDLE) && s_axil_awvalid && s_axil_wvalid;
    assign s_axil_arready = (state == IDLE) && !s_axil_awvalid;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_bvalid  = bvalid_reg;
    assign s_axil_rvalid  = rvalid_reg;
    assign s_axil_rdata   = rdata_reg;

    assign apb_paddr  = addr_reg;
    assign apb_pwdata = wdata_reg;
    assign apb_pstrb  = wstrb_reg;
    assign apb_pwrite = is_write;

    reg apb_psel_reg, apb_penable_reg;
    assign apb_psel   = apb_psel_reg;
    assign apb_penable = apb_penable_reg;

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            apb_psel_reg <= 0;
            apb_penable_reg <= 0;
            bvalid_reg   <= 0;
            rvalid_reg   <= 0;
        end else begin
            apb_penable_reg <= 0;
            case (state)
                IDLE: begin
                    if (bvalid_reg && s_axil_bready) bvalid_reg <= 0;
                    if (rvalid_reg && s_axil_rready) rvalid_reg <= 0;
                    if (s_axil_arvalid) begin
                        addr_reg <= s_axil_araddr;
                        is_write <= 0;
                        apb_psel_reg <= 1;
                        state    <= SETUP;
                    end else if (s_axil_awvalid && s_axil_wvalid) begin
                        addr_reg  <= s_axil_awaddr;
                        wdata_reg <= s_axil_wdata;
                        wstrb_reg <= s_axil_wstrb;
                        is_write  <= 1;
                        apb_psel_reg <= 1;
                        state     <= SETUP;
                    end
                end
                SETUP: begin
                    // setup phase complete, move to access
                    apb_penable_reg <= 1;
                    state <= ACCESS;
                end
                ACCESS: begin
                    apb_psel_reg <= 1;
                    apb_penable_reg <= 1;
                    if (apb_pready) begin
                        apb_psel_reg <= 0;
                        apb_penable_reg <= 0;
                        if (is_write) begin
                            bvalid_reg <= 1;
                        end else begin
                            rdata_reg <= apb_prdata;
                            rvalid_reg <= 1;
                        end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
