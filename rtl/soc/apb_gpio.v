`resetall
`timescale 1ns / 1ps
`default_nettype none

// apb_gpio.v - APB GPIO, 16 bits
// Registers (offset from slave base):
//   0x00  OUT    (RW) [15:0] output data
//   0x04  IN     (RO) [15:0] input data
//   0x08  DIR    (RW) [15:0] 1=output, 0=input
//   0x0C  INT_EN (RW) [15:0] enable interrupt per bit
//   0x10  IPR    (RO) [15:0] latched rising-edge pending
//   0x14  IC     (WO)        write 1 to clear pending bits
module apb_gpio #(
    parameter integer DATA_WIDTH = 32
) (
    input  wire clk,
    input  wire rst,

    // APB slave
    input  wire                    psel,
    input  wire                    penable,
    input  wire [11:0]             paddr,
    input  wire                    pwrite,
    input  wire [DATA_WIDTH-1:0]   pwdata,
    input  wire [DATA_WIDTH/8-1:0] pstrb,
    output wire [DATA_WIDTH-1:0]   prdata,
    output wire                    pready,
    output wire                    pslverr,

    // GPIO
    output wire [15:0]             gpio_out,
    output wire [15:0]             gpio_oe,
    input  wire [15:0]             gpio_in,
    output wire                    gpio_intr
);

    reg [15:0] out_reg;
    reg [15:0] dir_reg;
    reg [15:0] int_en_reg;
    reg [15:0] ipr_reg;

    wire pen = psel && penable;

    assign gpio_out = out_reg;
    assign gpio_oe  = dir_reg;
    assign gpio_intr = |(ipr_reg & int_en_reg);
    // combinational read (valid throughout APB ACCESS phase)
    assign prdata =
        (paddr[5:2] == 4'd0) ? {16'b0, out_reg} :
        (paddr[5:2] == 4'd1) ? {16'b0, gpio_in} :
        (paddr[5:2] == 4'd2) ? {16'b0, dir_reg} :
        (paddr[5:2] == 4'd3) ? {16'b0, int_en_reg} :
        (paddr[5:2] == 4'd4) ? {16'b0, ipr_reg} :
        32'h0;
    assign pready = 1'b1;
    assign pslverr = 1'b0;

    // write access
    always @(posedge clk) begin
        if (rst) begin
            out_reg <= 0;
            dir_reg <= 0;
            int_en_reg <= 0;
        end else if (pen && pwrite) begin
            case (paddr[5:2])
                4'd0: begin
                    if (pstrb[0]) out_reg[ 7:0] <= pwdata[ 7:0];
                    if (pstrb[1]) out_reg[15:8] <= pwdata[15:8];
                end
                4'd2: begin
                    if (pstrb[0]) dir_reg[ 7:0] <= pwdata[ 7:0];
                    if (pstrb[1]) dir_reg[15:8] <= pwdata[15:8];
                end
                4'd3: begin
                    if (pstrb[0]) int_en_reg[ 7:0] <= pwdata[ 7:0];
                    if (pstrb[1]) int_en_reg[15:8] <= pwdata[15:8];
                end
                4'd5: ipr_reg <= ipr_reg & ~pwdata[15:0]; // clear
                default: ;
            endcase
        end
    end

    // rising edge detect -> pending
    reg [15:0] in_prev;
    always @(posedge clk) begin
        if (rst) begin
            in_prev <= 0;
            ipr_reg <= 0;
        end else begin
            in_prev <= gpio_in;
            ipr_reg  <= ipr_reg | (gpio_in & ~in_prev);
        end
    end

endmodule
