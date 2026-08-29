`resetall
`timescale 1ns / 1ps
`default_nettype none

// apb_ctrl.v - APB general-purpose control/scratch registers
// Registers (offset from slave base):
//   0x00  REG0    (RW)
//   0x04  REG1    (RW)
//   0x08  REG2    (RW)
//   0x0C  VERSION (RO) = 0x00000001
module apb_ctrl #(
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

    output wire [31:0]             ctrl0,
    output wire [31:0]             ctrl1,
    output wire [31:0]             ctrl2
);

    reg [DATA_WIDTH-1:0] reg0, reg1, reg2;

    wire pen = psel && penable;

    assign ctrl0 = reg0;
    assign ctrl1 = reg1;
    assign ctrl2 = reg2;
    // combinational read (valid throughout APB ACCESS phase)
    assign prdata =
        (paddr[5:2] == 4'd0) ? reg0 :
        (paddr[5:2] == 4'd1) ? reg1 :
        (paddr[5:2] == 4'd2) ? reg2 :
        (paddr[5:2] == 4'd3) ? 32'h00000001 : // VERSION
        32'h0;
    assign pready = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            reg0 <= 0;
            reg1 <= 0;
            reg2 <= 0;
        end else if (pen && pwrite) begin
            case (paddr[5:2])
                4'd0: reg0 <= pwdata;
                4'd1: reg1 <= pwdata;
                4'd2: reg2 <= pwdata;
                default: ;
            endcase
        end
    end

endmodule
