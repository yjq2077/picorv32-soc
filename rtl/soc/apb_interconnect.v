`resetall
`timescale 1ns / 1ps
`default_nettype none

// apb_interconnect.v - APB address decoder / read mux (1 master, N slaves)
// Slave regions are defined by S_BASE_ADDR / S_ADDR_WIDTH concatenated
// fields; field 0 (LSB) belongs to slave port 0.
module apb_interconnect #(
    parameter integer ADDR_WIDTH = 16,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH/8,
    parameter integer S_COUNT    = 2,
    parameter S_BASE_ADDR  = {S_COUNT{1'b0}},
    parameter S_ADDR_WIDTH = {S_COUNT{32'd12}}
) (
    input  wire clk,
    input  wire rst,

    // APB master interface
    input  wire [ADDR_WIDTH-1:0]  apb_paddr,
    input  wire                   apb_psel,
    input  wire                   apb_penable,
    input  wire                   apb_pwrite,
    input  wire [DATA_WIDTH-1:0]  apb_pwdata,
    input  wire [STRB_WIDTH-1:0]  apb_pstrb,
    output wire [DATA_WIDTH-1:0]  apb_prdata,
    output wire                   apb_pready,
    output wire                   apb_pslverr,

    // APB slave interfaces
    output wire [S_COUNT-1:0]     s_psel,
    output wire [ADDR_WIDTH-1:0]  s_paddr,
    output wire                   s_penable,
    output wire                   s_pwrite,
    output wire [DATA_WIDTH-1:0]  s_pwdata,
    output wire [STRB_WIDTH-1:0]  s_pstrb,
    input  wire [S_COUNT*DATA_WIDTH-1:0] s_prdata,
    input  wire [S_COUNT-1:0]     s_pready,
    input  wire [S_COUNT-1:0]     s_pslverr
);

    integer i;
    reg [S_COUNT-1:0] psel_int;
    reg [DATA_WIDTH-1:0] prdata_mux;

    always @* begin
        psel_int = {S_COUNT{1'b0}};
        for (i = 0; i < S_COUNT; i = i + 1) begin
            if (apb_psel &&
                (apb_paddr & ({ADDR_WIDTH{1'b1}} << S_ADDR_WIDTH[i*32 +: 32])) ==
                (S_BASE_ADDR[i*ADDR_WIDTH +: ADDR_WIDTH] & ({ADDR_WIDTH{1'b1}} << S_ADDR_WIDTH[i*32 +: 32])))
                psel_int[i] = 1'b1;
        end
    end

    always @* begin
        prdata_mux = {DATA_WIDTH{1'b0}};
        for (i = 0; i < S_COUNT; i = i + 1)
            if (psel_int[i])
                prdata_mux = s_prdata[i*DATA_WIDTH +: DATA_WIDTH];
    end

    assign s_psel    = psel_int;
    assign s_paddr   = apb_paddr;
    assign s_penable = apb_penable;
    assign s_pwrite  = apb_pwrite;
    assign s_pwdata  = apb_pwdata;
    assign s_pstrb   = apb_pstrb;

    assign apb_prdata = prdata_mux;

    // pready: selected slave's pready, OR of all (unselected slaves report ready)
    assign apb_pready = (apb_psel && !(|psel_int)) ? 1'b1 : (|(s_pready & psel_int));

    // pslverr: selected slave's error
    assign apb_pslverr = (|(s_pslverr & psel_int));

endmodule
