`resetall
`timescale 1ns / 1ps
`default_nettype none

// uart_axil.v - AXI-Lite UART wrapper around alexforencich's uart core
// Registers (4-bit address, 32-bit data):
//   0x00  TXDATA    (WO) write byte to transmit
//   0x04  RXDATA    (RO) read received byte
//   0x08  STATUS    (RO) bit0=tx_pending, bit1=rx_avail,
//                        bit2=rx_overrun, bit3=rx_frame_error
//   0x0C  PRESCALE  (RW) clock prescale (clk_hz / baud / 4)
module uart_axil #(
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

    // UART interface
    output wire                   ser_tx,
    input  wire                   ser_rx,

    // Interrupt outputs
    output wire                   int_rx,   // receive data available
    output wire                   int_tx    // transmit buffer empty
);

    localparam [1:0] IDLE = 2'd0, W_RESP = 2'd1, R_RESP = 2'd2;

    reg [1:0] state;
    reg [DATA_WIDTH-1:0] rdata;
    reg aw_hs, w_hs, ar_hs;

    // TX path
    reg tx_pending;
    reg [7:0] tx_data;
    wire s_axis_tready;

    // RX path (driven by uart core)
    wire [7:0] rx_data;
    wire       rx_avail;
    reg        rx_rd_pulse;
    wire       rx_overrun_pulse;
    wire       rx_frame_pulse;
    reg        rx_overrun;
    reg        rx_frame_err;

    reg [15:0] prescale;

    assign s_axil_awready = (state == IDLE) && !aw_hs && !ar_hs;
    assign s_axil_wready  = (state == IDLE) && !w_hs  && !ar_hs;
    assign s_axil_arready = (state == IDLE) && !aw_hs && !ar_hs;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_bvalid  = (state == W_RESP);
    assign s_axil_rvalid  = (state == R_RESP);
    assign s_axil_rdata   = rdata;

    assign int_tx = !tx_pending;
    assign int_rx = rx_avail;

    uart #(
        .DATA_WIDTH(8)
    ) uart_inst (
        .clk             (clk),
        .rst             (rst),
        .s_axis_tdata    (tx_data),
        .s_axis_tvalid   (tx_pending),
        .s_axis_tready   (s_axis_tready),
        .m_axis_tdata    (rx_data),
        .m_axis_tvalid   (rx_avail),
        .m_axis_tready   (rx_rd_pulse),
        .rxd             (ser_rx),
        .txd             (ser_tx),
        .tx_busy         (),
        .rx_busy         (),
        .rx_overrun_error(rx_overrun_pulse),
        .rx_frame_error  (rx_frame_pulse),
        .prescale        (prescale)
    );

    // Latch rx error pulses, clear on RXDATA read
    always @(posedge clk) begin
        if (rst) begin
            rx_overrun  <= 0;
            rx_frame_err <= 0;
        end else begin
            if (rx_overrun_pulse) rx_overrun <= 1;
            if (rx_frame_pulse)   rx_frame_err <= 1;
            if (rx_rd_pulse) begin
                rx_overrun  <= 0;
                rx_frame_err <= 0;
            end
        end
    end

`ifdef ENABLE_DBG
    reg rx_avail_d;
    always @(posedge clk) begin
        rx_avail_d <= rx_avail;
        if (rx_avail && !rx_avail_d)
            $display("[dbg] uart rx byte valid: 0x%02x", rx_data);
        if (rx_overrun_pulse) $display("[dbg] uart rx OVERRUN");
        if (rx_frame_pulse)   $display("[dbg] uart rx FRAME ERR");
    end
`endif

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            rdata       <= 0;
            aw_hs       <= 0;
            w_hs        <= 0;
            ar_hs       <= 0;
            tx_pending  <= 0;
            rx_rd_pulse <= 0;
            prescale    <= 16'd0;
        end else begin
            rx_rd_pulse <= 0;

            // clear tx_pending when uart core accepted the byte
            if (tx_pending && s_axis_tready)
                tx_pending <= 0;

            case (state)
                IDLE: begin
                    if (aw_hs && w_hs) begin
                        case (s_axil_awaddr)
                            4'h0: begin // TXDATA
                                if (s_axil_wstrb[0] && !tx_pending) begin
                                    tx_data    <= s_axil_wdata[7:0];
                                    tx_pending <= 1;
                                end
                            end
                            4'hc: if (s_axil_wstrb[0]) prescale <= s_axil_wdata[15:0];
                            default: ;
                        endcase
                        aw_hs <= 0; w_hs <= 0;
                        state <= W_RESP;
                    end else begin
                        if (s_axil_awvalid && !aw_hs) aw_hs <= 1;
                        if (s_axil_wvalid  && !w_hs)  w_hs  <= 1;
                        if (s_axil_arvalid && !ar_hs) begin
                            case (s_axil_araddr)
                                4'h4: begin // RXDATA
                                    rdata       <= {24'b0, rx_data};
                                    rx_rd_pulse <= 1;
                                end
                                4'h8: rdata <= {28'b0, rx_frame_err, rx_overrun, rx_avail, tx_pending};
                                4'hc: rdata <= {16'b0, prescale};
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
