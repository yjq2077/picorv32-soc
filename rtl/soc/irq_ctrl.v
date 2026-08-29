// irq_ctrl.v - AXI-Lite interrupt controller
// Collects up to 16 level/edge interrupt sources, applies per-source
// enable mask, and produces a single combined interrupt output that
// feeds the PicoRV32 irq[5] line.
//
// Registers (4-bit address):
//   0x00  IER  (RW) [15:0] interrupt enable
//   0x04  IPR  (RO) [15:0] pending = irq_src & IER
//   0x08  MER  (RW) [0]    master enable
module irq_ctrl #(
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

    // Interrupt sources
    input  wire [15:0]            irq_src,
    output wire                   intr
);

    localparam [1:0] IDLE = 2'd0, W_RESP = 2'd1, R_RESP = 2'd2;

    reg [1:0] state;
    reg [DATA_WIDTH-1:0] ier;
    reg [DATA_WIDTH-1:0] mer;
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

    wire [15:0] pending = irq_src & ier[15:0];
    assign intr = (|pending) & mer[0];

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            ier   <= 0;
            mer   <= 0;
            rdata <= 0;
            aw_hs <= 0;
            w_hs  <= 0;
            ar_hs <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (aw_hs && w_hs) begin
                        case (s_axil_awaddr)
                            4'h0: if (s_axil_wstrb[0]) ier[15:0] <= s_axil_wdata[15:0];
                            4'h8: if (s_axil_wstrb[0]) mer       <= s_axil_wdata;
                            default: ;
                        endcase
                        aw_hs <= 0; w_hs <= 0;
                        state <= W_RESP;
                    end else begin
                        if (s_axil_awvalid && !aw_hs) aw_hs <= 1;
                        if (s_axil_wvalid  && !w_hs)  w_hs  <= 1;
                        if (s_axil_arvalid && !ar_hs) begin
                            case (s_axil_araddr)
                                4'h0: rdata <= ier;
                                4'h4: rdata <= {16'b0, pending};
                                4'h8: rdata <= mer;
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
