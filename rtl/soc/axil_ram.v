`resetall
`timescale 1ns / 1ps
`default_nettype none

// axil_ram.v - AXI4-Lite slave RAM (up to 64KB)
// Byte-write strobes, word-aligned addressing, one transfer at a time.
module axil_ram #(
    parameter integer ADDR_WIDTH = 16,   // byte address width (64KB)
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH/8
) (
    input  wire clk,
    input  wire rst,

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
    input  wire                    s_axil_rready
);

    localparam [2:0] IDLE = 3'd0, WRITE = 3'd1, WRITE_RESP = 3'd2,
                     READ  = 3'd3, READ_RESP = 3'd4;

    localparam integer AW   = $clog2(STRB_WIDTH);         // word index bits (2)
    localparam integer WORDS = 1 << (ADDR_WIDTH - AW);    // number of words

    reg [DATA_WIDTH-1:0] mem [0:WORDS-1];

    reg [2:0] state;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [DATA_WIDTH-1:0] wdata_reg;
    reg [STRB_WIDTH-1:0] wstrb_reg;
    reg [DATA_WIDTH-1:0] rdata_reg;

    assign s_axil_awready = (state == IDLE) && !s_axil_arvalid;
    assign s_axil_wready  = (state == IDLE) && !s_axil_arvalid;
    assign s_axil_arready = (state == IDLE) && !s_axil_awvalid && !s_axil_wvalid;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_bvalid  = (state == WRITE_RESP);
    assign s_axil_rvalid  = (state == READ_RESP);
    assign s_axil_rdata   = rdata_reg;

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            rdata_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (s_axil_arvalid) begin
                        addr_reg  <= s_axil_araddr;
                        state     <= READ;
                    end else if (s_axil_awvalid && s_axil_wvalid) begin
                        addr_reg  <= s_axil_awaddr;
                        wdata_reg <= s_axil_wdata;
                        wstrb_reg <= s_axil_wstrb;
                        state     <= WRITE;
                    end
                end
                WRITE: begin
                    if (wstrb_reg[0]) mem[addr_reg[ADDR_WIDTH-1:AW]][ 7: 0] <= wdata_reg[ 7: 0];
                    if (wstrb_reg[1]) mem[addr_reg[ADDR_WIDTH-1:AW]][15: 8] <= wdata_reg[15: 8];
                    if (wstrb_reg[2]) mem[addr_reg[ADDR_WIDTH-1:AW]][23:16] <= wdata_reg[23:16];
                    if (wstrb_reg[3]) mem[addr_reg[ADDR_WIDTH-1:AW]][31:24] <= wdata_reg[31:24];
                    state <= WRITE_RESP;
                end
                WRITE_RESP: begin
                    if (s_axil_bready) state <= IDLE;
                end
                READ: begin
                    rdata_reg <= mem[addr_reg[ADDR_WIDTH-1:AW]];
                    state     <= READ_RESP;
                end
                READ_RESP: begin
                    if (s_axil_rready) state <= IDLE;
                end
            endcase
        end
    end

endmodule
