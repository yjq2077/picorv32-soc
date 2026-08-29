// soc_tb.v - PicoRV32 SoC testbench
//
// Environment models:
//   - External host AXI-Lite master: downloads fw.hex into RAM through the
//     interconnect slave port, then releases the CPU reset via boot_ctrl.
//   - UART0 RX driver: sends 'A' when it sees the "RXREADY" marker on TX.
//   - UART0/1 TX monitors: decode the serial stream and print to console.
//   - GPIO input driver: 0x00AA pattern; toggles bit 0 on the "GPIOIRQ" marker.
//   - I2C0 eeprom-style slave model (7-bit addr 0x50).
//   - Result watchdog: ctrl1 == 0xBEEF => PASS, 0xDEAD => FAIL.
`resetall
`timescale 1ns / 1ps
`default_nettype none

module soc_tb;

    localparam CLK_PERIOD       = 10;          // 100 MHz
    localparam UART_PRESCALE    = 2;           // must match main.c
    localparam UART_BIT_CYCLES  = UART_PRESCALE * 8;   // cycles per UART bit
    localparam TIMEOUT_NS       = 4000000;     // global watchdog

    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg rst_n = 0;

    // ------------------------------------------------------------------
    // Host AXI-Lite master port
    // ------------------------------------------------------------------
    reg  [31:0] s_axil_awaddr = 0;
    reg  [ 2:0] s_axil_awprot = 0;
    reg         s_axil_awvalid = 0;
    wire        s_axil_awready;
    reg  [31:0] s_axil_wdata = 0;
    reg  [ 3:0] s_axil_wstrb = 4'hF;
    reg         s_axil_wvalid = 0;
    wire        s_axil_wready;
    wire [ 1:0] s_axil_bresp;
    wire        s_axil_bvalid;
    reg         s_axil_bready = 0;
    reg  [31:0] s_axil_araddr = 0;
    reg  [ 2:0] s_axil_arprot = 0;
    reg         s_axil_arvalid = 0;
    wire        s_axil_arready;
    wire [31:0] s_axil_rdata;
    wire [ 1:0] s_axil_rresp;
    wire        s_axil_rvalid;
    reg         s_axil_rready = 0;

    wire        cpu_trap;
    wire        cpu_resetn;

    wire        uart0_txd, uart1_txd;
    reg         uart0_rxd = 1;      // idle high
    reg         uart1_rxd = 1;

    wire        i2c0_scl, i2c0_sda;
    wire        i2c1_scl, i2c1_sda;
    wire        i2c2_scl, i2c2_sda;
    wire        i2c3_scl, i2c3_sda;

    reg  [15:0] gpio_in = 16'h00AA;
    wire [15:0] gpio_out, gpio_oe;
    wire [31:0] ctrl0, ctrl1, ctrl2;
    wire        irq_out;

    soc_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axil_awaddr (s_axil_awaddr),
        .s_axil_awprot (s_axil_awprot),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata  (s_axil_wdata),
        .s_axil_wstrb  (s_axil_wstrb),
        .s_axil_wvalid (s_axil_wvalid),
        .s_axil_wready (s_axil_wready),
        .s_axil_bresp  (s_axil_bresp),
        .s_axil_bvalid (s_axil_bvalid),
        .s_axil_bready (s_axil_bready),
        .s_axil_araddr (s_axil_araddr),
        .s_axil_arprot (s_axil_arprot),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata  (s_axil_rdata),
        .s_axil_rresp  (s_axil_rresp),
        .s_axil_rvalid (s_axil_rvalid),
        .s_axil_rready (s_axil_rready),
        .cpu_trap      (cpu_trap),
        .cpu_resetn    (cpu_resetn),
        .uart0_txd     (uart0_txd),
        .uart0_rxd     (uart0_rxd),
        .uart1_txd     (uart1_txd),
        .uart1_rxd     (uart1_rxd),
        .i2c0_scl      (i2c0_scl),
        .i2c0_sda      (i2c0_sda),
        .i2c1_scl      (i2c1_scl),
        .i2c1_sda      (i2c1_sda),
        .i2c2_scl      (i2c2_scl),
        .i2c2_sda      (i2c2_sda),
        .i2c3_scl      (i2c3_scl),
        .i2c3_sda      (i2c3_sda),
        .gpio_in       (gpio_in),
        .gpio_out      (gpio_out),
        .gpio_oe       (gpio_oe),
        .ctrl0         (ctrl0),
        .ctrl1         (ctrl1),
        .ctrl2         (ctrl2),
        .irq_out       (irq_out)
    );

    // I2C pullups (open-drain buses)
    pullup(i2c0_scl);
    pullup(i2c0_sda);
    pullup(i2c1_scl);
    pullup(i2c1_sda);
    pullup(i2c2_scl);
    pullup(i2c2_sda);
    pullup(i2c3_scl);
    pullup(i2c3_sda);

    // I2C eeprom-style slave on bus 0
    i2c_eeprom_model #(
        .SLAVE_ADDR (7'h50)
    ) u_eeprom (
        .clk (clk),
        .scl (i2c0_scl),
        .sda (i2c0_sda)
    );

    // ------------------------------------------------------------------
    // Host AXI-Lite tasks
    // ------------------------------------------------------------------
    task axil_write(input [31:0] addr, input [31:0] data, input [3:0] strb);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= strb;
            s_axil_wvalid  <= 1;
            s_axil_bready  <= 1;
            // the interconnect may assert AW and W ready in different cycles
            while (!s_axil_awready)
                @(posedge clk);
            while (!s_axil_wready)
                @(posedge clk);
            @(posedge clk);
            s_axil_awvalid <= 0;
            s_axil_wvalid  <= 0;
            while (!s_axil_bvalid)
                @(posedge clk);
            @(posedge clk);
            s_axil_bready  <= 0;
        end
    endtask

    task axil_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1;
            s_axil_rready  <= 1;
            while (!s_axil_arready)
                @(posedge clk);
            @(posedge clk);
            s_axil_arvalid <= 0;
            while (!s_axil_rvalid)
                @(posedge clk);
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready <= 0;
        end
    endtask

    // ------------------------------------------------------------------
    // Main sequence: reset -> download -> release CPU -> wait result
    // ------------------------------------------------------------------
    reg [31:0] fw_mem [0:16383];
    reg        result_done;
    integer    nwords, i;
    reg [31:0] rd;

    initial begin
        nwords = 0;
        result_done = 0;

        rst_n = 0;
        repeat (25) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        // load firmware image
        $readmemh("fw.hex", fw_mem);
        // number of words to download is passed by the run script
        // (readmemh zero-fills, so the image end cannot be detected by x)
        if (!$value$plusargs("FW_WORDS=%d", nwords))
            nwords = 16384;
        $display("[host] fw.hex loaded: %0d words (%0d bytes)", nwords, nwords*4);

        // download into RAM through the interconnect
        for (i = 0; i < nwords; i = i + 1) begin
            if ((i % 256) == 0)
                $display("[host] downloading word %0d/%0d", i, nwords);
            axil_write(32'h00000000 + (i << 2), fw_mem[i], 4'hF);
        end
        $display("[host] downloaded %0d words to RAM", nwords);

        // verify read-back of first and last word
        axil_read(32'h00000000, rd);
        $display("[host] ram[0]  = 0x%08x", rd);
        axil_read(32'h00000000 + ((nwords-1) << 2), rd);
        $display("[host] ram[%0d] = 0x%08x", nwords-1, rd);

        // release CPU reset via boot_ctrl CTRL register
        axil_write(32'h10000000, 32'h00000001, 4'hF);
        $display("[host] cpu reset released (boot_ctrl=1)");

        // wait for CPU trap or result marker
        i = 0;
        while (!(cpu_trap || result_done) && i < (TIMEOUT_NS / CLK_PERIOD)) begin
            @(posedge clk);
            i = i + 1;
        end

        if (cpu_trap)
            $display("[host] CPU trapped.");
        if (!result_done && !cpu_trap)
            $display("=== TEST RESULT: TIMEOUT ===");
`ifdef ENABLE_DBG
        #100;
        $display("== SUMMARY ==");
        $display("summary cpu_release_t_ns = %0d", cpu_release_t);
        $display("summary first_fetch_t_ns  = %0d", first_fetch_t);
        $display("summary result_t_ns       = %0d", result_t);
        $display("summary ram_ar_count      = %0d", ram_ar_count);
        $display("summary ram_aw_count      = %0d", ram_aw_count);
        $display("summary host_aw_count     = %0d", host_aw_cnt);
        $display("summary host_aw_first_ns  = %0d", host_aw_first);
        $display("summary host_aw_last_ns   = %0d", host_aw_last);
        $display("summary boot_release_t_ns = %0d", boot_release_t);
        $display("summary ic_trans_count    = %0d", ic_trans_count);
        $display("summary irq_edge_count    = %0d", irq_edge_count);
        $display("summary i2c0_scl_fall_cnt = %0d", i2c0_scl_fall_cnt);
        $display("summary irq0_latency_ns   = %0d", irq0_latency_ns);
        $display("summary irq6_latency_ns   = %0d", irq6_latency_ns);
        $display("summary last_timer_cnt    = 0x%08x", last_timer_cnt);
`endif
        #1000;
        $finish;
    end

    // ------------------------------------------------------------------
    // DEBUG monitors (enable with +define+ENABLE_DBG)
    // ------------------------------------------------------------------
`ifdef ENABLE_DBG
    reg cpu_rstn_d;
    reg [2:0] ic_state_d;
    reg i2c0_scl_d;
    reg irq_out_d;
    reg cpu_first_fetch_done;
    integer cpu_release_t = -1;
    integer first_fetch_t  = -1;
    integer result_t       = -1;
    integer ram_ar_count   = 0;
    integer ic_trans_count = 0;
    integer irq_edge_count = 0;
    integer i2c0_scl_fall_cnt = 0;
    integer apb0_rd_cnt = 0;
    integer apb0_wr_cnt = 0;
    integer apb1_rd_cnt = 0;
    integer apb1_wr_cnt = 0;
    reg [31:0] last_timer_cnt = 0;
    integer last_irq_rise_t = -1;
    integer irq0_latency_ns = -1;
    integer irq6_latency_ns = -1;
    reg irq0_seen = 0;
    reg irq6_seen = 0;
    integer ram_aw_count = 0;
    integer host_aw_cnt = 0;
    integer host_ar_cnt = 0;
    integer host_aw_first = -1;
    integer host_aw_last = -1;
    integer boot_release_t = -1;
    always @(posedge clk) begin
        cpu_rstn_d <= cpu_resetn;
        if (cpu_resetn && !cpu_rstn_d && cpu_release_t < 0) begin
            cpu_release_t = $time;
            $display("[dbg] t=%0t cpu_resetn HIGH (CPU released)", $time);
        end
        if (!cpu_resetn && cpu_rstn_d)
            $display("[dbg] t=%0t cpu_resetn LOW", $time);

        if (dut.u_ram.s_axil_arvalid && dut.u_ram.s_axil_arready) begin
            ram_ar_count = ram_ar_count + 1;
            if (cpu_release_t > 0 && !cpu_first_fetch_done) begin
                cpu_first_fetch_done = 1;
                first_fetch_t = $time;
                $display("[dbg] t=%0t CPU first instr fetch addr=0x%08x", $time, dut.u_ram.s_axil_araddr);
            end
        end
        if (dut.u_ram.s_axil_awvalid && dut.u_ram.s_axil_awready)
            ram_aw_count = ram_aw_count + 1;

        if (s_axil_awvalid && s_axil_awready) begin
            host_aw_cnt = host_aw_cnt + 1;
            if (host_aw_first < 0) host_aw_first = $time;
            host_aw_last = $time;
        end
        if (s_axil_arvalid && s_axil_arready)
            host_ar_cnt = host_ar_cnt + 1;
        if (dut.u_boot.s_axil_awvalid && dut.u_boot.s_axil_awready &&
            dut.u_boot.s_axil_awaddr == 4'h0)
            boot_release_t = $time;

        if (dut.cpu_inst.trap)
            $display("[dbg] t=%0t CPU trap asserted", $time);

        ic_state_d <= dut.u_ic.state_reg;
        if (dut.u_ic.state_reg != ic_state_d)
            ic_trans_count = ic_trans_count + 1;

        if (dut.u_irq.s_axil_arvalid && dut.u_irq.s_axil_arready)
            $display("[dbg] t=%0t IRQ AR addr=0x%0x", $time, dut.u_irq.s_axil_araddr);
        if (dut.u_irq.s_axil_rvalid)
            $display("[dbg] t=%0t IRQ RVALID addr=0x%0x data=0x%08x", $time, dut.u_irq.s_axil_araddr, dut.u_irq.s_axil_rdata);
        if (dut.u_irq.s_axil_awvalid && dut.u_irq.s_axil_awready)
            $display("[dbg] t=%0t IRQ AW addr=0x%0x data=0x%08x", $time, dut.u_irq.s_axil_awaddr, dut.u_irq.s_axil_wdata);

        // interrupt response: IRQ_OUT assert -> CPU reads IPR with that bit
        if (dut.u_irq.s_axil_rvalid && dut.u_irq.s_axil_araddr == 4'h4) begin
            if (!irq0_seen && (dut.u_irq.s_axil_rdata & 32'h10)) begin
                irq0_seen = 1;
                if (last_irq_rise_t > 0)
                    irq0_latency_ns = $time - last_irq_rise_t;
            end
            if (!irq6_seen && (dut.u_irq.s_axil_rdata & 32'h40)) begin
                irq6_seen = 1;
                if (last_irq_rise_t > 0)
                    irq6_latency_ns = $time - last_irq_rise_t;
            end
        end

        if (dut.u_apb0_bridge.s_axil_arvalid && dut.u_apb0_bridge.s_axil_arready) begin
            apb0_rd_cnt = apb0_rd_cnt + 1;
            $display("[dbg] t=%0t APB0 AR#%0d addr=0x%04x", $time, apb0_rd_cnt, dut.u_apb0_bridge.s_axil_araddr);
        end
        if (dut.u_apb0_bridge.s_axil_rvalid)
            $display("[dbg] t=%0t APB0 RVALID#%0d data=0x%08x", $time, apb0_rd_cnt, dut.u_apb0_bridge.s_axil_rdata);
        if (dut.u_apb0_bridge.s_axil_awvalid && dut.u_apb0_bridge.s_axil_awready) begin
            apb0_wr_cnt = apb0_wr_cnt + 1;
            $display("[dbg] t=%0t APB0 AW#%0d addr=0x%04x data=0x%08x", $time, apb0_wr_cnt, dut.u_apb0_bridge.s_axil_awaddr, dut.u_apb0_bridge.s_axil_wdata);
        end
        if (dut.u_apb0_bridge.s_axil_bvalid)
            $display("[dbg] t=%0t APB0 BVALID#%0d", $time, apb0_wr_cnt);

        if (dut.u_apb1_bridge.s_axil_arvalid && dut.u_apb1_bridge.s_axil_arready) begin
            apb1_rd_cnt = apb1_rd_cnt + 1;
            $display("[dbg] t=%0t APB1 AR#%0d addr=0x%04x", $time, apb1_rd_cnt, dut.u_apb1_bridge.s_axil_araddr);
        end
        if (dut.u_apb1_bridge.s_axil_rvalid)
            $display("[dbg] t=%0t APB1 RVALID#%0d data=0x%08x", $time, apb1_rd_cnt, dut.u_apb1_bridge.s_axil_rdata);
        if (dut.u_apb1_bridge.s_axil_awvalid && dut.u_apb1_bridge.s_axil_awready) begin
            apb1_wr_cnt = apb1_wr_cnt + 1;
            $display("[dbg] t=%0t APB1 AW#%0d addr=0x%04x data=0x%08x", $time, apb1_wr_cnt, dut.u_apb1_bridge.s_axil_awaddr, dut.u_apb1_bridge.s_axil_wdata);
        end
        if (dut.u_apb1_bridge.s_axil_bvalid)
            $display("[dbg] t=%0t APB1 BVALID#%0d", $time, apb1_wr_cnt);

        // sample timer0 count (APB bridge readback path already shows it, keep one per cycle)
        last_timer_cnt = dut.u_timer0.count_reg;

        i2c0_scl_d <= i2c0_scl;
        if (i2c0_scl_d && !i2c0_scl)
            i2c0_scl_fall_cnt = i2c0_scl_fall_cnt + 1;

        irq_out_d <= irq_out;
        if (irq_out && !irq_out_d) begin
            irq_edge_count = irq_edge_count + 1;
            last_irq_rise_t = $time;
            $display("[dbg] t=%0t IRQ_OUT rising #%0d", $time, irq_edge_count);
        end
        if (!irq_out && irq_out_d)
            $display("[dbg] t=%0t IRQ_OUT falling", $time);

        if (cpu_resetn && ctrl1 == 32'h0000BEEF && result_t < 0)
            result_t = $time;
    end
`endif

    // result watchdog (also armed as a global timeout)
    always @(posedge clk) begin
        if (cpu_resetn && ctrl1 == 32'h0000BEEF && !result_done) begin
            $display("=== TEST RESULT: PASS (ctrl1=0x%08x) ===", ctrl1);
            result_done = 1;
        end else if (cpu_resetn && ctrl1 == 32'h0000DEAD && !result_done) begin
            $display("=== TEST RESULT: FAIL (ctrl1=0x%08x) ===", ctrl1);
            result_done = 1;
        end
    end

    // ------------------------------------------------------------------
    // UART0 TX monitor (decodes the stream and prints)
    // ------------------------------------------------------------------
    reg        u0_active;
    reg [31:0] u0_tick;
    reg [ 3:0] u0_bit;
    reg [ 7:0] u0_data;
    reg        u0_char_ready;
    reg [ 7:0] u0_out;
    reg [ 7:0] u0_last7 [0:6];
    reg        u0_rx_go;

    always @(posedge clk) begin
        if (!rst_n) begin
            u0_active  <= 0;
            u0_tick    <= 0;
            u0_bit     <= 0;
            u0_data    <= 0;
            u0_char_ready <= 0;
            u0_rx_go   <= 0;
        end else begin
            u0_char_ready <= 0;
            if (!u0_active) begin
                if (!uart0_txd) begin
                    u0_active <= 1;
                    u0_tick   <= 0;
                    u0_bit    <= 0;
                end
            end else begin
                if (u0_tick == (UART_BIT_CYCLES >> 1) - 1) begin
                    if (u0_bit == 0) begin
                        u0_bit <= 1;                       // start bit
                    end else if (u0_bit <= 8) begin
                        u0_data <= {uart0_txd, u0_data[7:1]};
                        u0_bit  <= u0_bit + 1;
                    end else begin
                        u0_out       <= u0_data;           // stop bit -> char
                        u0_char_ready <= 1;
                        u0_active    <= 0;
                    end
                end
                if (u0_tick == UART_BIT_CYCLES - 1)
                    u0_tick <= 0;                          // wrap at full bit period
                else
                    u0_tick <= u0_tick + 1;
            end

            // marker detection for UART0 RX trigger: "RXREADY"
            if (u0_char_ready) begin
                u0_last7[6] <= u0_last7[5];
                u0_last7[5] <= u0_last7[4];
                u0_last7[4] <= u0_last7[3];
                u0_last7[3] <= u0_last7[2];
                u0_last7[2] <= u0_last7[1];
                u0_last7[1] <= u0_last7[0];
                u0_last7[0] <= u0_out;
                if (u0_last7[5] == "R" && u0_last7[4] == "X" &&
                    u0_last7[3] == "R" && u0_last7[2] == "E" &&
                    u0_last7[1] == "A" && u0_last7[0] == "D" &&
                    u0_out       == "Y")
                    u0_rx_go <= 1;
            end
        end
    end

    // UART0 RX driver: on marker, send 'A'
    initial begin
        uart0_rxd = 1;
        while (!u0_rx_go) @(posedge clk);
        #(CLK_PERIOD * 2);
        $display("[uart0] RX driver: sending 'A'");
        uart0_rx_send_byte(8'h41);
    end

    task uart0_rx_send_byte(input [7:0] d);
        integer j;
        begin
            uart0_rxd = 0;                                   // start
            repeat (UART_BIT_CYCLES) @(posedge clk);
            for (j = 0; j < 8; j = j + 1) begin
                uart0_rxd = d[j];
                repeat (UART_BIT_CYCLES) @(posedge clk);
            end
            uart0_rxd = 1;                                   // stop
            repeat (UART_BIT_CYCLES) @(posedge clk);
        end
    endtask

    // print decoded UART0 chars as buffered lines
    reg [7:0] u0_buf [0:79];
    reg [6:0] u0_buflen;
    integer u0_bi;
    initial begin
        u0_buflen = 0;
        forever begin
            @(posedge clk);
            if (u0_char_ready) begin
                if (u0_out == "\n") begin
                    $write("UART0: ");
                    for (u0_bi = 0; u0_bi < u0_buflen; u0_bi = u0_bi + 1)
                        $write("%c", u0_buf[u0_bi]);
                    $display("");
                    u0_buflen = 0;
                end else if (u0_buflen < 80) begin
                    u0_buf[u0_buflen] = u0_out;
                    u0_buflen = u0_buflen + 1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // UART1 TX monitor (decodes and prints)
    // ------------------------------------------------------------------
    reg        u1_active;
    reg [31:0] u1_tick;
    reg [ 3:0] u1_bit;
    reg [ 7:0] u1_data;
    reg        u1_char_ready;
    reg [ 7:0] u1_out;

    always @(posedge clk) begin
        if (!rst_n) begin
            u1_active  <= 0;
            u1_tick    <= 0;
            u1_bit     <= 0;
            u1_data    <= 0;
            u1_char_ready <= 0;
        end else begin
            u1_char_ready <= 0;
            if (!u1_active) begin
                if (!uart1_txd) begin
                    u1_active <= 1;
                    u1_tick   <= 0;
                    u1_bit    <= 0;
                end
            end else begin
                if (u1_tick == (UART_BIT_CYCLES >> 1) - 1) begin
                    if (u1_bit == 0)
                        u1_bit <= 1;
                    else if (u1_bit <= 8) begin
                        u1_data <= {uart1_txd, u1_data[7:1]};
                        u1_bit  <= u1_bit + 1;
                    end else begin
                        u1_out       <= u1_data;
                        u1_char_ready <= 1;
                        u1_active    <= 0;
                    end
                end
                if (u1_tick == UART_BIT_CYCLES - 1)
                    u1_tick <= 0;
                else
                    u1_tick <= u1_tick + 1;
            end
        end
    end

    // print decoded UART1 chars as buffered lines
    reg [7:0] u1_buf [0:79];
    reg [6:0] u1_buflen;
    integer u1_bi;
    initial begin
        u1_buflen = 0;
        forever begin
            @(posedge clk);
            if (u1_char_ready) begin
                if (u1_out == "\n") begin
                    $write("UART1: ");
                    for (u1_bi = 0; u1_bi < u1_buflen; u1_bi = u1_bi + 1)
                        $write("%c", u1_buf[u1_bi]);
                    $display("");
                    u1_buflen = 0;
                end else if (u1_buflen < 80) begin
                    u1_buf[u1_buflen] = u1_out;
                    u1_buflen = u1_buflen + 1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // GPIO IRQ trigger: toggle gpio_in[0] on the "GPIOIRQ" marker
    // ------------------------------------------------------------------
    reg [7:0] g_last7 [0:6];
    reg       g_go;

    always @(posedge clk) begin
        if (!rst_n) begin
            g_go <= 0;
        end else begin
            if (u0_char_ready) begin
                g_last7[6] <= g_last7[5];
                g_last7[5] <= g_last7[4];
                g_last7[4] <= g_last7[3];
                g_last7[3] <= g_last7[2];
                g_last7[2] <= g_last7[1];
                g_last7[1] <= g_last7[0];
                g_last7[0] <= u0_out;
                if (g_last7[5] == "G" && g_last7[4] == "P" &&
                    g_last7[3] == "I" && g_last7[2] == "O" &&
                    g_last7[1] == "I" && g_last7[0] == "R" &&
                    u0_out       == "Q")
                    g_go <= 1;
            end
        end
    end

    initial begin
        while (!g_go) @(posedge clk);
        #(CLK_PERIOD * 2);
        $display("[gpio] toggling gpio_in[0] 0->1");
        gpio_in[0] = 1;
    end

endmodule

// ======================================================================
// i2c_eeprom_model - simple I2C EEPROM-style slave
//  Protocol:
//   write: START, addr|W, ACK, [byte0 = internal pointer, bytes1.. = data], ACK each
//   read:  START, addr|R, ACK, byte=mem[ptr++], ... (repeated starts), NACK+STOP
// ======================================================================
module i2c_eeprom_model #(
    parameter [6:0] SLAVE_ADDR = 7'h50
) (
    input  wire clk,
    input  wire scl,
    inout  wire sda
);

    reg [7:0] mem [0:255];
    reg [7:0] ptr;
    reg [7:0] sh;
    reg [3:0] bit_cnt;
    reg       started;
    reg       got_addr;
    reg       rw;
    reg       first_data;
    reg       ack_oe;
    reg       data_oe;
    reg       sda_out;

    // synchronized SCL/SDA samples (SDA not sampled while we drive it)
    reg scl_s, scl_d;
    reg sda_s, sda_d;
    integer k;

    wire scl_rise = scl_s && !scl_d;
    wire scl_fall = !scl_s && scl_d;
    wire start_bit = scl_s && !sda_s && sda_d;   // SDA falls while SCL high
    wire stop_bit  = scl_s &&  sda_s && !sda_d;  // SDA rises while SCL high

    assign sda = (ack_oe || data_oe) ? (data_oe ? sda_out : 1'b0) : 1'bz;

    initial begin
        for (k = 0; k < 256; k = k + 1) mem[k] = 8'h00;
        ptr = 0; sh = 0; bit_cnt = 0;
        started = 0; got_addr = 0; rw = 0; first_data = 0;
        ack_oe = 0; data_oe = 0; sda_out = 1;
        scl_s = 1; scl_d = 1; sda_s = 1; sda_d = 1;
    end

    // sample SCL always; freeze SDA sampling while driving the bus
    always @(posedge clk) begin
        scl_d <= scl_s;
        scl_s <= scl;
        sda_d <= sda_s;
        if (!ack_oe && !data_oe)
            sda_s <= sda;
    end

    // edge / start-stop detection (all synchronous to clk)
    always @(posedge clk) begin
        if (start_bit) begin
            started    <= 1;
            bit_cnt    <= 0;
            got_addr   <= 0;
            rw         <= 0;
            first_data <= 1;
            ack_oe     <= 0;
            data_oe    <= 0;
            sh         <= 0;
        end else if (stop_bit) begin
            started <= 0;
            ack_oe  <= 0;
            data_oe <= 0;
        end
    end

    // process on SCL rising edge: address / write-data sampling
    always @(posedge clk) begin
        if (started && scl_rise) begin
            if (!got_addr) begin
                sh <= {sh[6:0], sda_s};
                if (bit_cnt == 8) begin
                    got_addr  <= 1;
                    rw        <= sh[0];
                    bit_cnt   <= 0;
                    if (sh[7:1] == SLAVE_ADDR)
                        ack_oe <= 1;
                end else
                    bit_cnt <= bit_cnt + 1;
            end else if (!rw) begin
                sh <= {sh[6:0], sda_s};
                if (bit_cnt == 8) begin
                    bit_cnt <= 0;
                    if (first_data) begin
                        ptr        <= sh;
                        first_data <= 0;
                    end else begin
                        mem[ptr] <= sh;
                        ptr      <= ptr + 1;
                    end
                    ack_oe <= 1;
                end else
                    bit_cnt <= bit_cnt + 1;
            end
        end
    end

    // on SCL falling edge: drive read data, release ack/data lines
    always @(posedge clk) begin
        if (scl_fall && started) begin
            if (got_addr && rw) begin
                if (bit_cnt == 0) begin
                    data_oe <= 1;
                    sda_out <= mem[ptr][7];
                    sh      <= {mem[ptr][6:0], 1'b0};
                    ptr     <= ptr + 1;
                    bit_cnt <= 1;
                end else if (bit_cnt < 8) begin
                    sda_out <= sh[7];
                    sh      <= {sh[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    data_oe <= 0;              // release for master ack/nack
                    bit_cnt <= 0;
                end
            end
            ack_oe <= 0;
        end
    end

endmodule
