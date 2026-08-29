`resetall
`timescale 1ns / 1ps
`default_nettype none

// apb_timer.v - APB down-counter timer with interrupt
// Registers (offset from slave base):
//   0x00  CTRL   (RW) bit0=enable, bit1=irq enable, bit2=autoreload
//   0x04  RELOAD (RW) [31:0] reload value
//   0x08  COUNT  (RO) [31:0] current count
//   0x0C  IACK   (WO) write 1 to clear pending irq
module apb_timer #(
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

    output wire                    timer_irq
);

    reg [2:0] ctrl_reg;
    reg [31:0] reload_reg;
    reg [31:0] count_reg;
    reg irq_flag;
    reg was_enabled;

    assign timer_irq = irq_flag && ctrl_reg[1];
    // combinational read (valid throughout APB ACCESS phase)
    assign prdata =
        (paddr[5:2] == 4'd0) ? {30'b0, ctrl_reg} :
        (paddr[5:2] == 4'd1) ? reload_reg :
        (paddr[5:2] == 4'd2) ? count_reg :
        32'h0;
    assign pready = 1'b1;
    assign pslverr = 1'b0;

    wire pen = psel && penable;

    always @(posedge clk) begin
        if (rst) begin
            ctrl_reg   <= 0;
            reload_reg <= 0;
        end else if (pen && pwrite) begin
`ifdef ENABLE_DBG
            $display("[dbg-timer] write paddr[5:2]=%0d pstrb=0x%0x pwdata=0x%08x", paddr[5:2], pstrb, pwdata);
`endif
            case (paddr[5:2])
                4'd0: if (pstrb[0]) ctrl_reg   <= pwdata[2:0];
                4'd1: reload_reg <= pwdata;
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            count_reg   <= 0;
            irq_flag    <= 0;
            was_enabled <= 0;
        end else begin
            // clear irq on ack
            if (pen && pwrite && (paddr[5:2] == 4'd3))
                irq_flag <= 0;

            // load reload on the enable edge so a one-shot holds count at 0
            if (ctrl_reg[0] && !was_enabled) begin
                count_reg <= reload_reg;
            end else if (ctrl_reg[0]) begin
                if (count_reg == 0) begin
                    irq_flag  <= 1;
                    if (ctrl_reg[2])
                        count_reg <= reload_reg;  // autoreload
                    else
                        ctrl_reg[0] <= 0;         // one-shot: stop, hold at 0
                end else begin
                    count_reg <= count_reg - 1;
                end
            end

            was_enabled <= ctrl_reg[0];
        end
    end

endmodule
