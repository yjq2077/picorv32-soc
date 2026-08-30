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
    localparam TIMEOUT_NS       = 120000000;   // global watchdog (extended: UART IRQ latency ~16us/char)

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

    reg  [35:0] last_trace;
    reg  [31:0] last_pc;
    reg         ever_retired = 0;
    reg  [31:0] retire_cnt   = 0;
    reg  [31:0] quiet_cnt    = 0;   // cycles since last retired instruction
    reg  [31:0] pc_hist[0:15];
    integer     pc_hist_i = 0;
    reg  [ 8:0] ram_snap[0:31];
    integer     ram_snap_i = 0;
    // per-cycle history of the interconnect write path to RAM (for stall debug)
    reg  [47:0] w_hist[0:31];   // {ic_st[2:0], ram_st[2:0], awv,awr,wv,wr,bv,br,arv,arr,rv,rr, cpu_bv, awaddr[11:0]}
    integer     w_hist_i = 0;
    reg  [31:0] ram_b_cnt   = 0;
    reg  [31:0] ram_wr_cnt  = 0;
    reg  [31:0] mem_b_cnt   = 0;
    reg  [31:0] cpu_wr_issue = 0;
    reg  [31:0] cpu_wr_resp  = 0;
    reg  [31:0] cpu_rd_issue = 0;
    reg  [31:0] cpu_rd_resp  = 0;
    // interrupt behaviour counters
    reg         irq_out_d2 = 0;
    reg  [31:0] irq_rise_cnt   = 0;   // rising edges of combined interrupt to CPU
    reg  [31:0] irq_high_cyc   = 0;   // cycles irq line high
    reg  [31:0] u0_txd_write   = 0;   // AXI writes to UART0 TXDATA
    reg  [31:0] u0_rxd_read    = 0;   // AXI reads  of UART0 RXDATA
    reg  [31:0] u0_tx_pend_hi  = 0;   // cycles uart0 tx_pending high
    reg  [31:0] u0_int_tx_hi   = 0;   // cycles uart0 int_tx high
    reg  [31:0] u0_ier_hi      = 0;   // cycles IER[1] (UART0 TX) set
    reg  [31:0] cpu_irq_taken  = 0;   // cycles cpu reg_irq_pending set (interrupt in progress)
    reg  [31:0] timer0_irq_hi  = 0;   // cycles timer0 irq high
    // cycle accounting by firmware code region (fw.elf addresses)
    reg  [31:0] total_cyc      = 0;
    reg  [31:0] cyc_irq_vec    = 0;   // irq_vec 0x10..0x200 (32-reg save/restore)
    reg  [31:0] cyc_irq_fn     = 0;   // irq()    0xf54..0x1068
    reg  [31:0] cyc_rt_sched   = 0;   // rt_schedule 0x3c10..0x3d6c
    reg  [31:0] cyc_ctx_asw    = 0;   // context_gcc.S 0x214c..0x2314
    reg  [31:0] cyc_tick       = 0;   // rt_tick_increase 0x2354..0x23e0
    reg  [31:0] cyc_sem        = 0;   // rt_sem_take/release 0x2658..0x284c
    // memory-stall accounting (CPU stalled awaiting a fetch/data response)
    reg  [31:0] stall_total  = 0;    // all cycles mem_valid && !mem_ready
    reg  [31:0] stall_irqvec = 0;    // those while PC in irq_vec 0x10..0x200

    always @(posedge clk) begin
        if (dut.ram_bvalid && dut.ram_bready) ram_b_cnt <= ram_b_cnt + 1;
        if (dut.ram_awvalid && dut.ram_awready && dut.ram_wvalid && dut.ram_wready)
            ram_wr_cnt <= ram_wr_cnt + 1;
        if (dut.mem_axi_bvalid && dut.mem_axi_bready) mem_b_cnt <= mem_b_cnt + 1;
        if (dut.mem_axi_awvalid && dut.mem_axi_awready &&
            dut.mem_axi_wvalid  && dut.mem_axi_wready)  cpu_wr_issue <= cpu_wr_issue + 1;
        if (dut.mem_axi_arvalid && dut.mem_axi_arready) cpu_rd_issue <= cpu_rd_issue + 1;
        if (dut.mem_axi_rvalid  && dut.mem_axi_rready)  cpu_rd_resp  <= cpu_rd_resp  + 1;
        irq_out_d2 <= irq_out;
        if (irq_out && !irq_out_d2) irq_rise_cnt <= irq_rise_cnt + 1;
        if (irq_out)               irq_high_cyc <= irq_high_cyc + 1;
        if (dut.u_uart0.s_axil_awvalid && dut.u_uart0.s_axil_awready &&
            dut.u_uart0.s_axil_awaddr == 4'h0) u0_txd_write <= u0_txd_write + 1;
        if (dut.u_uart0.s_axil_arvalid && dut.u_uart0.s_axil_arready &&
            dut.u_uart0.s_axil_araddr == 4'h4) u0_rxd_read  <= u0_rxd_read + 1;
        if (dut.u_uart0.tx_pending)  u0_tx_pend_hi <= u0_tx_pend_hi + 1;
        if (dut.uart0_int_tx)        u0_int_tx_hi  <= u0_int_tx_hi + 1;
        if (dut.u_irq.ier[1])        u0_ier_hi     <= u0_ier_hi + 1;
        if (dut.cpu_inst.picorv32_core.irq_pending) cpu_irq_taken <= cpu_irq_taken + 1;
        if (dut.timer0_irq)          timer0_irq_hi <= timer0_irq_hi + 1;
        total_cyc <= total_cyc + 1;
        if (dut.cpu_inst.picorv32_core.mem_valid && !dut.cpu_inst.picorv32_core.mem_ready)
            stall_total <= stall_total + 1;
        if (dut.cpu_inst.picorv32_core.reg_pc[15:0] >= 16'h0010 &&
            dut.cpu_inst.picorv32_core.reg_pc[15:0] <  16'h0200) begin
            if (dut.cpu_inst.picorv32_core.mem_valid && !dut.cpu_inst.picorv32_core.mem_ready)
                stall_irqvec <= stall_irqvec + 1;
        end
        if (dut.cpu_inst.picorv32_core.reg_pc[15:0] >= 16'h0010 &&
            dut.cpu_inst.picorv32_core.reg_pc[15:0] <  16'h0200)
            cyc_irq_vec  <= cyc_irq_vec  + 1;
        else if (dut.cpu_inst.picorv32_core.reg_pc[15:0] >= 16'h0f54 &&
                 dut.cpu_inst.picorv32_core.reg_pc[15:0] <  16'h1068)
            cyc_irq_fn   <= cyc_irq_fn   + 1;
        else if (dut.cpu_inst.picorv32_core.reg_pc[15:0] >= 16'h3c10 &&
                 dut.cpu_inst.picorv32_core.reg_pc[15:0] <  16'h3d6c)
            cyc_rt_sched <= cyc_rt_sched + 1;
        else if (dut.cpu_inst.picorv32_core.reg_pc[15:0] >= 16'h214c &&
                 dut.cpu_inst.picorv32_core.reg_pc[15:0] <  16'h2314)
            cyc_ctx_asw  <= cyc_ctx_asw  + 1;
        else if (dut.cpu_inst.picorv32_core.reg_pc[15:0] >= 16'h2354 &&
                 dut.cpu_inst.picorv32_core.reg_pc[15:0] <  16'h23e0)
            cyc_tick     <= cyc_tick     + 1;
        else if (dut.cpu_inst.picorv32_core.reg_pc[15:0] >= 16'h2658 &&
                 dut.cpu_inst.picorv32_core.reg_pc[15:0] <  16'h284c)
            cyc_sem      <= cyc_sem      + 1;
        ram_snap[ram_snap_i] <= {dut.ram_bvalid, dut.ram_wvalid, dut.ram_awvalid,
                                 dut.ram_wready, dut.ram_awready, dut.u_ram.state};
        ram_snap_i <= (ram_snap_i + 1) & 31;
        w_hist[w_hist_i] <= {dut.u_ic.state_reg, dut.u_ram.state,
                             dut.ram_awvalid, dut.ram_awready,
                             dut.ram_wvalid, dut.ram_wready,
                             dut.ram_bvalid, dut.ram_bready,
                             dut.ram_arvalid, dut.ram_arready,
                             dut.ram_rvalid, dut.ram_rready,
                             dut.mem_axi_bvalid, dut.ram_awaddr[11:0]};
        w_hist_i <= (w_hist_i + 1) & 31;
        if (dut.cpu_inst.trace_valid) begin
            ever_retired <= 1;
            retire_cnt   <= retire_cnt + 1;
            quiet_cnt    <= 0;
            last_trace   <= dut.cpu_inst.trace_data;
            if (dut.cpu_inst.trace_data[32]) begin  // TRACE_BRANCH -> instr PC in [31:1]
                last_pc        <= {dut.cpu_inst.trace_data[31:1], 1'b0};
                pc_hist[pc_hist_i] <= {dut.cpu_inst.trace_data[31:1], 1'b0};
                pc_hist_i      <= (pc_hist_i + 1) & 15;
            end
        end else if (ever_retired) begin
            quiet_cnt <= quiet_cnt + 1;
        end
    end

    // UART0 TX interrupt-flow trace (change-triggered, always on)
    reg d_u0_ier1 = 0;
    reg d_irq     = 0;
    always @(posedge clk) begin
        if (dut.u_uart0.s_axil_awvalid && dut.u_uart0.s_axil_awready &&
            dut.u_uart0.s_axil_awaddr == 4'h0)
            $display("[dbg] t=%0t U0 TXD write wdata=0x%08x '%c' (tx_pend=%b)",
                     $time, dut.u_uart0.s_axil_wdata, dut.u_uart0.s_axil_wdata[7:0],
                     dut.u_uart0.tx_pending);
        if (dut.u_uart0.s_axil_arvalid && dut.u_uart0.s_axil_arready &&
            dut.u_uart0.s_axil_araddr == 4'h8)
            $display("[dbg] t=%0t U0 STATUS read (tx_pend=%b rx_avail=%b)",
                     $time, dut.u_uart0.tx_pending, dut.u_uart0.rx_avail);
        if (dut.u_uart0.tx_pending && dut.u_uart0.s_axis_tready)
            $display("[dbg] t=%0t U0 TX byte accepted by uart core", $time);
        if (dut.u_irq.ier[1] != d_u0_ier1) begin
            $display("[dbg] t=%0t U0 IER[1] -> %b", $time, dut.u_irq.ier[1]);
            d_u0_ier1 <= dut.u_irq.ier[1];
        end
        if (irq_out != d_irq) begin
            $display("[dbg] t=%0t irq_out -> %b (int_tx=%b ier1=%b)", $time, irq_out,
                     dut.uart0_int_tx, dut.u_irq.ier[1]);
            d_irq <= irq_out;
        end
    end

    // CPU state while the combined IRQ line stays asserted (why so slow?)
    reg [31:0] irq_assert_cnt = 0;
    always @(posedge clk) begin
        if (irq_out) begin
            irq_assert_cnt <= irq_assert_cnt + 1;
            if (irq_assert_cnt == 0 || (irq_assert_cnt % 32'h1F4) == 0)  // every 500 cyc = 5us
                $display("[dbg] t=%0t irq_hi=%0d cpu_st=0x%02x irq_mask=%08x pc=%08x",
                         $time, irq_assert_cnt, dut.cpu_inst.picorv32_core.cpu_state,
                         dut.cpu_inst.picorv32_core.irq_mask,
                         dut.cpu_inst.picorv32_core.reg_pc);
        end else
            irq_assert_cnt <= 0;
    end

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

        if ($test$plusargs("TRACE")) begin
            $dumpfile("soc_tb.vcd");
            $dumpvars(0, dut);
        end

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
        axil_write(32'h00010000, 32'h00000001, 4'hF);   // boot_ctrl: release CPU reset
        $display("[host] cpu reset released (boot_ctrl=1)");

        // wait for CPU trap or result marker (or a sustained CPU stall)
        i = 0;
        while (!(cpu_trap || result_done) && i < (TIMEOUT_NS / CLK_PERIOD)
               && quiet_cnt < 5000) begin
            @(posedge clk);
            i = i + 1;
        end

        if (cpu_trap)
            $display("[host] CPU trapped.");
        if (!result_done && !cpu_trap) begin
            $display("=== TEST RESULT: TIMEOUT (quiet_cnt=%0d) ===", quiet_cnt);
            $display("[dbg] stall PC = 0x%08x (ever_retired=%b, retire_cnt=%0d, trace_valid=%b)",
                     last_pc, ever_retired, retire_cnt, dut.cpu_inst.trace_valid);
            $write("[dbg] pc_hist:");
            for (i = 0; i < 16; i = i + 1)
                $write(" %08x", pc_hist[i]);
            $display("");
            $display("[dbg] ram aw=%b/%b w=%b/%b b=%b/%b ar=%b/%b r=%b/%b state=%0d awaddr=%08x araddr=%08x",
                     dut.ram_awvalid, dut.ram_awready, dut.ram_wvalid, dut.ram_wready,
                     dut.ram_bvalid,  dut.ram_bready,  dut.ram_arvalid, dut.ram_arready,
                     dut.ram_rvalid,  dut.ram_rready,  dut.u_ram.state,
                     dut.ram_awaddr,  dut.ram_araddr);
            $display("[dbg] mem aw=%b/%b w=%b/%b b=%b/%b ar=%b/%b r=%b/%b",
                     dut.mem_axi_awvalid, dut.mem_axi_awready, dut.mem_axi_wvalid, dut.mem_axi_wready,
                     dut.mem_axi_bvalid,  dut.mem_axi_bready,  dut.mem_axi_arvalid, dut.mem_axi_arready,
                     dut.mem_axi_rvalid,  dut.mem_axi_rready);
            $write("[dbg] ram_snap({b,w,aw,wr,ar,st}):");
            for (i = 0; i < 32; i = i + 1)
                $write(" %08b", ram_snap[i]);
            $display("");
            $write("[dbg] w_hist(ic_st|ram_st|awv/awr|wv/wr|bv/br|arv/arr|rv/rr|cpu_bv|awaddr):");
            for (i = 0; i < 32; i = i + 1)
                $write(" %x%x%x%x%x%x%x%x%x%x%x%x%x%03x", w_hist[i][47:45], w_hist[i][44:42],
                       w_hist[i][41], w_hist[i][40], w_hist[i][39], w_hist[i][38],
                       w_hist[i][37], w_hist[i][36], w_hist[i][35], w_hist[i][34],
                       w_hist[i][33], w_hist[i][32], w_hist[i][31], w_hist[i][11:0]);
            $display("");
            $display("[dbg] ram writes accepted=%0d bvalid-pulses=%0d mem_bvalid-pulses=%0d",
                     ram_wr_cnt, ram_b_cnt, mem_b_cnt);
            $display("[dbg] cpu wr issue=%0d resp=%0d | rd issue=%0d resp=%0d",
                     cpu_wr_issue, cpu_wr_resp, cpu_rd_issue, cpu_rd_resp);
            $display("[dbg] irq rise=%0d high=%0d cyc cpu_irq_taken=%0d timer0_irq_hi=%0d",
                     irq_rise_cnt, irq_high_cyc, cpu_irq_taken, timer0_irq_hi);
            $display("[dbg] cyc total=%0d irq_vec=%0d irq_fn=%0d rt_sched=%0d ctx_asw=%0d tick=%0d sem=%0d",
                     total_cyc, cyc_irq_vec, cyc_irq_fn, cyc_rt_sched, cyc_ctx_asw, cyc_tick, cyc_sem);
            $display("[dbg] uart0 txd_write=%0d rxd_read=%0d tx_pend_hi=%0d int_tx_hi=%0d ier1_hi=%0d",
                     u0_txd_write, u0_rxd_read, u0_tx_pend_hi, u0_int_tx_hi, u0_ier_hi);
            $display("[dbg] ic state=%0d s_select=%0d m_select=%0d grant_valid=%b grant=%02x enc=%05b",
                     dut.u_ic.state_reg, dut.u_ic.s_select, dut.u_ic.m_select_reg,
                     dut.u_ic.arb_inst.grant_valid, dut.u_ic.arb_inst.grant,
                     dut.u_ic.grant_encoded);
            $display("[dbg] ic s: awv=%b awr=%b wv=%b wr=%b bv=%b br=%b arv=%b arr=%b rv=%b rr=%b",
                     dut.u_ic.s_axil_awvalid[0], dut.u_ic.s_axil_awready_reg[0],
                     dut.u_ic.s_axil_wvalid[0], dut.u_ic.s_axil_wready_reg[0],
                     dut.u_ic.s_axil_bvalid_reg[0], dut.u_ic.s_axil_bready[0],
                     dut.u_ic.s_axil_arvalid[0], dut.u_ic.s_axil_arready_reg[0],
                     dut.u_ic.s_axil_rvalid_reg[0], dut.u_ic.s_axil_rready[0]);
            $display("[dbg] ic m: awv=%b awr=%b wv=%b wr=%b bv=%b br=%b arv=%b arr=%b rv=%b rr=%b",
                     dut.u_ic.m_axil_awvalid_reg[0], dut.u_ic.m_axil_awready[0],
                     dut.u_ic.m_axil_wvalid_reg[0], dut.u_ic.m_axil_wready[0],
                     dut.u_ic.m_axil_bvalid[0], dut.u_ic.m_axil_bready_reg[0],
                     dut.u_ic.m_axil_arvalid_reg[0], dut.u_ic.m_axil_arready[0],
                     dut.u_ic.m_axil_rvalid[0], dut.u_ic.m_axil_rready_reg[0]);
        end
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

        if (dut.cpu_inst.trap) begin
            $display("[dbg] t=%0t CPU trap asserted, reg_pc=0x%08x last_pc=0x%08x retire_cnt=%0d",
                     $time, dut.cpu_inst.picorv32_core.reg_pc, last_pc, retire_cnt);
            $display("[dbg]   cpu_state=0x%02x next_insn_opcode=0x%08x dbg_insn_opcode=0x%08x",
                     dut.cpu_inst.picorv32_core.cpu_state,
                     dut.cpu_inst.picorv32_core.next_insn_opcode,
                     dut.cpu_inst.picorv32_core.dbg_insn_opcode);
            $display("[dbg]   ram[0x124A]=0x%08x ram[0x124B]=0x%08x ram[0x12D]=0x%08x",
                     dut.u_ram.mem[32'h124A], dut.u_ram.mem[32'h124B], dut.u_ram.mem[32'h12D]);
            $write("[dbg] trap pc_hist:");
            for (i = 0; i < 16; i = i + 1)
                $write(" %08x", pc_hist[(pc_hist_i + i) & 15]);
            $display("");
        end

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
            $display("[dbg] uart0 txd_write=%0d rxd_read=%0d tx_pend_hi=%0d int_tx_hi=%0d ier1_hi=%0d",
                     u0_txd_write, u0_rxd_read, u0_tx_pend_hi, u0_int_tx_hi, u0_ier_hi);
            $display("[dbg] irq rise=%0d high=%0d cyc cpu_irq_taken=%0d timer0_irq_hi=%0d",
                     irq_rise_cnt, irq_high_cyc, cpu_irq_taken, timer0_irq_hi);
            $display("[dbg] cyc total=%0d irq_vec=%0d irq_fn=%0d rt_sched=%0d ctx_asw=%0d tick=%0d sem=%0d",
                     total_cyc, cyc_irq_vec, cyc_irq_fn, cyc_rt_sched, cyc_ctx_asw, cyc_tick, cyc_sem);
            $display("[dbg] stall total=%0d irqvec=%0d (irqvec stall %0d%%)",
                     stall_total, stall_irqvec, 100 * stall_irqvec / (cyc_irq_vec ? cyc_irq_vec : 1));
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
