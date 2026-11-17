`timescale 1ns / 1ps

module tb_awg_dds_top;

    localparam real FS_HZ = 200_000_000.0;
    localparam real CLK_PERIOD_NS = 5.0; // 200 MHz

    reg clk = 1'b0;
    always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

    reg rst_n = 1'b0;
    reg ext_sync_trig = 1'b0;

    // AXI4-Lite signals
    reg  [15:0] s_axil_awaddr  = 16'd0;
    reg         s_axil_awvalid = 1'b0;
    wire        s_axil_awready;
    reg  [31:0] s_axil_wdata   = 32'd0;
    reg  [3:0]  s_axil_wstrb   = 4'hF;
    reg         s_axil_wvalid  = 1'b0;
    wire        s_axil_wready;
    wire [1:0]  s_axil_bresp;
    wire        s_axil_bvalid;
    reg         s_axil_bready  = 1'b1;
    reg  [15:0] s_axil_araddr  = 16'd0;
    reg         s_axil_arvalid = 1'b0;
    wire        s_axil_arready;
    wire [31:0] s_axil_rdata;
    wire [1:0]  s_axil_rresp;
    wire        s_axil_rvalid;
    reg         s_axil_rready  = 1'b1;

    // AXI4-Stream AWG input
    reg         s_axis_awg_tvalid = 1'b0;
    wire        s_axis_awg_tready;
    reg  [63:0] s_axis_awg_tdata  = 64'd0;
    reg         s_axis_awg_tlast  = 1'b0;

    // AXI4-Stream Capture output
    wire        m_axis_cap_tvalid;
    reg         m_axis_cap_tready = 1'b1;
    wire [63:0] m_axis_cap_tdata;
    wire        m_axis_cap_tlast;

    // DAC outputs
    wire        dac_valid;
    wire [15:0] dac_ch0_data, dac_ch1_data, dac_ch2_data, dac_ch3_data;
    wire [2:0]  status_led;

    awg_dds_top dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .ext_sync_trig     (ext_sync_trig),
        .s_axil_awaddr     (s_axil_awaddr),
        .s_axil_awvalid    (s_axil_awvalid),
        .s_axil_awready    (s_axil_awready),
        .s_axil_wdata      (s_axil_wdata),
        .s_axil_wstrb      (s_axil_wstrb),
        .s_axil_wvalid     (s_axil_wvalid),
        .s_axil_wready     (s_axil_wready),
        .s_axil_bresp      (s_axil_bresp),
        .s_axil_bvalid     (s_axil_bvalid),
        .s_axil_bready     (s_axil_bready),
        .s_axil_araddr     (s_axil_araddr),
        .s_axil_arvalid    (s_axil_arvalid),
        .s_axil_arready    (s_axil_arready),
        .s_axil_rdata      (s_axil_rdata),
        .s_axil_rresp      (s_axil_rresp),
        .s_axil_rvalid     (s_axil_rvalid),
        .s_axil_rready     (s_axil_rready),
        .s_axis_awg_tvalid (s_axis_awg_tvalid),
        .s_axis_awg_tready (s_axis_awg_tready),
        .s_axis_awg_tdata  (s_axis_awg_tdata),
        .s_axis_awg_tlast  (s_axis_awg_tlast),
        .m_axis_cap_tvalid (m_axis_cap_tvalid),
        .m_axis_cap_tready (m_axis_cap_tready),
        .m_axis_cap_tdata  (m_axis_cap_tdata),
        .m_axis_cap_tlast  (m_axis_cap_tlast),
        .dac_valid         (dac_valid),
        .dac_ch0_data      (dac_ch0_data),
        .dac_ch1_data      (dac_ch1_data),
        .dac_ch2_data      (dac_ch2_data),
        .dac_ch3_data      (dac_ch3_data),
        .status_led        (status_led)
    );

    integer err_cnt = 0;

    // -------------------------------------------------------------------------
    // AXI4-Lite BFM Tasks
    // -------------------------------------------------------------------------
    task automatic axil_write(input [15:0] addr, input [31:0] data, input [3:0] strb = 4'hF);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= strb;
            s_axil_wvalid  <= 1'b1;
            s_axil_bready  <= 1'b1;

            fork
                begin
                    wait (s_axil_awvalid && s_axil_awready);
                    @(posedge clk);
                    s_axil_awvalid <= 1'b0;
                end
                begin
                    wait (s_axil_wvalid && s_axil_wready);
                    @(posedge clk);
                    s_axil_wvalid <= 1'b0;
                end
            join
            wait (s_axil_bvalid);
            @(posedge clk);
        end
    endtask

    task automatic axil_write_decoupled(input [15:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;
            wait (s_axil_awvalid && s_axil_awready);
            @(posedge clk);
            s_axil_awvalid <= 1'b0;
            repeat (2) @(posedge clk);
            s_axil_wdata   <= data;
            s_axil_wstrb   <= 4'hF;
            s_axil_wvalid  <= 1'b1;
            wait (s_axil_wvalid && s_axil_wready);
            @(posedge clk);
            s_axil_wvalid  <= 1'b0;
            wait (s_axil_bvalid);
            @(posedge clk);
        end
    endtask

    task automatic axil_read(input [15:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;
            wait (s_axil_arvalid && s_axil_arready);
            @(posedge clk);
            s_axil_arvalid <= 1'b0;
            wait (s_axil_rvalid);
            data = s_axil_rdata;
            @(posedge clk);
        end
    endtask

    function automatic [47:0] calc_ftw48(input real fout_hz);
        real ratio, hi_r, lo_r;
        integer hi24, lo24;
        begin
            ratio = (fout_hz / FS_HZ) * 281474976710656.0; // 2^48
            hi_r  = $floor(ratio / 16777216.0);            // / 2^24
            lo_r  = ratio - (hi_r * 16777216.0);
            hi24  = $rtoi(hi_r);
            lo24  = $rtoi(lo_r);
            calc_ftw48 = {hi24[23:0], lo24[23:0]};
        end
    endfunction

    function automatic [31:0] calc_ftw32(input real fout_hz);
        real ratio, hi_r, lo_r;
        integer hi16, lo16;
        begin
            ratio = (fout_hz / FS_HZ) * 4294967296.0; // 2^32
            hi_r  = $floor(ratio / 65536.0);          // / 2^16
            lo_r  = ratio - (hi_r * 65536.0);
            hi16  = $rtoi(hi_r);
            lo16  = $rtoi(lo_r);
            calc_ftw32 = {hi16[15:0], lo16[15:0]};
        end
    endfunction

    // Helper: write 48-bit FTW / POFF
    task automatic set_ch_ftw(input int ch, input [47:0] ftw);
        reg [15:0] base;
        begin
            base = (ch + 1) * 16'h0100;
            axil_write(base + 16'h04, ftw[31:0]);
            axil_write(base + 16'h08, {16'd0, ftw[47:32]});
        end
    endtask

    task automatic set_ch_poff(input int ch, input [47:0] poff);
        reg [15:0] base;
        begin
            base = (ch + 1) * 16'h0100;
            axil_write(base + 16'h0C, poff[31:0]);
            axil_write(base + 16'h10, {16'd0, poff[47:32]});
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    integer fd_sine, fd_awg, fd_mod;
    integer k, tlast_cnt;
    reg [31:0] rd_val;
    reg [47:0] ftw_tmp;
    reg signed [15:0] s_even, s_odd;
    reg signed [15:0] ch0_s, ch1_s, ch2_s, ch3_s;
    real pi_val;
    real theta, env, gauss;
    reg [63:0] cap_hold_data;
    reg        cap_hold_last;
    integer    quad_dot_sum;

    initial begin
        $dumpfile("awg_dds_wave.vcd");
        $dumpvars(1, tb_awg_dds_top);

        pi_val = 3.14159265358979323846;

        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 1: AXI4-Lite Version & Decoupled Write Check
        // ---------------------------------------------------------------------
        $display("[TEST 1] AXI4-Lite version and register R/W...");
        axil_read(16'h0000, rd_val);
        if (rd_val !== 32'h4444_5301) begin
            $display("FAIL: Version mismatch: got 0x%08x", rd_val);
            err_cnt++;
        end

        axil_write_decoupled(16'h0010, 32'd255); // CAP_PKT_LEN = 256 samples
        axil_read(16'h0010, rd_val);
        if (rd_val !== 32'd255) begin
            $display("FAIL: Decoupled write readback mismatch: got %0d", rd_val);
            err_cnt++;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Multi-channel CW Sine + Quadrature 90-deg + SFDR Dump
        // ---------------------------------------------------------------------
        $display("[TEST 2] 4-channel CW Sine + Quadrature Sync + SFDR capture...");
        // Ch0: 7.123456 MHz (non-coherent to expose any spurious harmonics in FFT)
        // Ch1: 7.123456 MHz + 90 deg phase offset (2^46)
        // Ch2: 12.5 MHz
        // Ch3: 25.0 MHz
        ftw_tmp = calc_ftw48(7_123_456.0);
        set_ch_ftw(0, ftw_tmp);
        set_ch_ftw(1, ftw_tmp);
        set_ch_poff(1, 48'h4000_0000_0000); // +90 degrees
        set_ch_ftw(2, calc_ftw48(12_500_000.0));
        set_ch_ftw(3, calc_ftw48(25_000_000.0));

        for (k = 0; k < 4; k++) begin
            axil_write((k + 1) * 16'h0100 + 16'h00, 32'h0000_0040); // sine, awg_interp=1
            axil_write((k + 1) * 16'h0100 + 16'h14, 32'h0000_8000); // gain=1.0, offset=0
        end

        // Enable global + all 4 channels + soft phase sync
        axil_write(16'h0004, 32'h0000_00F3);
        repeat (16) @(posedge clk);

        // Verify Ch0 (sin) and Ch1 (cos) orthogonality & peak amplitude
        quad_dot_sum = 0;
        fd_sine = $fopen("sim_sine_ch0.csv", "w");
        $fwrite(fd_sine, "idx,ch0,ch1,ch2,ch3\n");
        for (k = 0; k < 4096; k++) begin
            @(posedge clk);
            if (!dac_valid) begin
                $display("FAIL: dac_valid dropped during CW test at k=%0d", k);
                err_cnt++;
            end
            ch0_s = $signed(dac_ch0_data);
            ch1_s = $signed(dac_ch1_data);
            ch2_s = $signed(dac_ch2_data);
            ch3_s = $signed(dac_ch3_data);
            quad_dot_sum += (ch0_s * ch1_s) >>> 15;
            $fwrite(fd_sine, "%0d,%0d,%0d,%0d,%0d\n", k, ch0_s, ch1_s, ch2_s, ch3_s);
        end
        $fclose(fd_sine);
        $display("  Quadrature dot product sum (expect ~0): %0d", quad_dot_sum);
        if (quad_dot_sum > 200000 || quad_dot_sum < -200000) begin
            $display("FAIL: Ch0/Ch1 quadrature orthogonality failed!");
            err_cnt++;
        end

        // ---------------------------------------------------------------------
        // TEST 3: Linear Chirp Sweep + AM / FM / PM Modulation
        // ---------------------------------------------------------------------
        $display("[TEST 3] Chirp Sweep + AM/FM/PM Modulation...");
        // Ch0: Triangle Chirp 2 MHz -> 20 MHz
        axil_write(16'h0128, calc_ftw48(200_000.0) & 32'hFFFF_FFFF);
        axil_write(16'h012C, calc_ftw48(200_000.0) >> 32);
        axil_write(16'h0130, calc_ftw48(2_000_000.0) & 32'hFFFF_FFFF);
        axil_write(16'h0134, calc_ftw48(2_000_000.0) >> 32);
        axil_write(16'h0138, calc_ftw48(20_000_000.0) & 32'hFFFF_FFFF);
        axil_write(16'h013C, calc_ftw48(20_000_000.0) >> 32);
        axil_write(16'h0140, 32'd4); // dwell 5 cycles
        axil_write(16'h0100, 32'h0000_0340); // sweep_en=1, sweep_mode=1 (tri)

        // Ch1: AM 10 MHz carrier modulated by 500 kHz internal NCO (gain=0.5 so no clip)
        set_ch_ftw(1, calc_ftw48(10_000_000.0));
        set_ch_poff(1, 48'd0);
        axil_write(16'h0214, 32'h0000_4000); // gain = 0.5
        axil_write(16'h021C, calc_ftw32(500_000.0));
        axil_write(16'h0220, 32'h0000_8000); // am_depth = 100%
        axil_write(16'h0200, 32'h0000_0048); // mod_mode = AM (01)

        // Ch2: FM 10 MHz carrier modulated by 500 kHz internal NCO
        set_ch_ftw(2, calc_ftw48(10_000_000.0));
        axil_write(16'h031C, calc_ftw32(500_000.0));
        axil_write(16'h0320, 32'h0400_0000); // fm_dev = 0x0400
        axil_write(16'h0300, 32'h0000_0050); // mod_mode = FM (10)

        // Ch3: PM 10 MHz carrier modulated by Ch2 (cross-channel mod_src_sel=1)
        set_ch_ftw(3, calc_ftw48(10_000_000.0));
        axil_write(16'h0424, 32'h0000_4000); // pm_dev = 0x4000 (+/-45 deg)
        axil_write(16'h0400, 32'h0000_0078); // mod_mode = PM (11), mod_src_sel=1

        axil_write(16'h0004, 32'h0000_00F3); // phase sync
        repeat (16) @(posedge clk);

        fd_mod = $fopen("sim_mod_sweep.csv", "w");
        $fwrite(fd_mod, "idx,chirp,am,fm,pm\n");
        for (k = 0; k < 1024; k++) begin
            @(posedge clk);
            $fwrite(fd_mod, "%0d,%0d,%0d,%0d,%0d\n", k,
                    $signed(dac_ch0_data), $signed(dac_ch1_data),
                    $signed(dac_ch2_data), $signed(dac_ch3_data));
        end
        $fclose(fd_mod);

        // ---------------------------------------------------------------------
        // TEST 4: Geometric Waves, Saturation Clamping, Offset Binary
        // ---------------------------------------------------------------------
        $display("[TEST 4] Geometric waveforms, saturation clamp, offset binary...");
        axil_write(16'h0100, 32'h0000_0041); // Ch0 Square
        axil_write(16'h0118, 32'h0000_4000); // 25% duty
        set_ch_ftw(0, calc_ftw48(5_000_000.0));

        axil_write(16'h0200, 32'h0000_0042); // Ch1 Triangle
        axil_write(16'h0214, 32'h0000_8000);
        set_ch_ftw(1, calc_ftw48(5_000_000.0));

        axil_write(16'h0300, 32'h0000_0043); // Ch2 Sawtooth + large +DC offset (+20000) to test clamping
        axil_write(16'h0314, 32'h4E20_8000); // dc_offset = +20000, gain = 1.0
        set_ch_ftw(2, calc_ftw48(5_000_000.0));

        axil_write(16'h0400, 32'h0000_0045); // Ch3 PRBS noise
        axil_write(16'h0414, 32'h0000_8000);

        repeat (100) @(posedge clk);
        // Toggle offset binary output on DAC pins
        axil_write(16'h0004, 32'h0000_01F1); // dac_offset_bin=1
        repeat (10) @(posedge clk);
        axil_write(16'h0004, 32'h0000_00F1); // back to signed

        // ---------------------------------------------------------------------
        // TEST 5: AWG BRAM Load via AXI4-Lite + Playback (Interpolated & Step)
        // ---------------------------------------------------------------------
        $display("[TEST 5] Loading 4096-sample Gaussian pulse into Ch0 AWG BRAM...");
        for (k = 0; k < 2048; k++) begin
            // Sample 2*k
            theta  = 2.0 * pi_val * 12.0 * (2.0 * k) / 4096.0;
            gauss  = ((2.0 * k) - 2048.0) / 512.0;
            env    = $exp(-0.5 * gauss * gauss);
            s_even = $rtoi(30000.0 * env * $cos(theta));
            // Sample 2*k + 1
            theta  = 2.0 * pi_val * 12.0 * (2.0 * k + 1.0) / 4096.0;
            gauss  = ((2.0 * k + 1.0) - 2048.0) / 512.0;
            env    = $exp(-0.5 * gauss * gauss);
            s_odd  = $rtoi(30000.0 * env * $cos(theta));

            axil_write(16'h8000 + (k * 4), {s_odd, s_even});
        end

        // Play back Ch0 AWG via phase accumulator (interpolated)
        set_ch_ftw(0, calc_ftw48(250_000.0)); // 800 cycles per AWG period
        axil_write(16'h0114, 32'h0000_8000);  // gain = 1.0, offset = 0
        axil_write(16'h0100, 32'h0000_0044);  // wave_mode=AWG(4), awg_interp_en=1
        axil_write(16'h0004, 32'h0000_00F3);  // phase sync
        repeat (16) @(posedge clk);

        fd_awg = $fopen("sim_awg_ch0.csv", "w");
        $fwrite(fd_awg, "idx,awg_interp\n");
        for (k = 0; k < 850; k++) begin
            @(posedge clk);
            $fwrite(fd_awg, "%0d,%0d\n", k, $signed(dac_ch0_data));
        end
        $fclose(fd_awg);

        // ---------------------------------------------------------------------
        // TEST 6: Deep DDR3/XDMA AXI4-Stream Playback + M_AXIS_CAP Backpressure
        // ---------------------------------------------------------------------
        $display("[TEST 6] Deep AXI4-Stream AWG FIFO & M_AXIS_CAP backpressure...");
        // Pre-fill FIFO with 64 known words
        for (k = 0; k < 64; k++) begin
            @(posedge clk);
            s_axis_awg_tvalid <= 1'b1;
            s_axis_awg_tdata  <= {16'(k + 3000), 16'(k + 2000), 16'(k + 1000), 16'(k)};
            s_axis_awg_tlast  <= (k == 63);
            wait (s_axis_awg_tready);
        end
        @(posedge clk);
        s_axis_awg_tvalid <= 1'b0;
        s_axis_awg_tlast  <= 1'b0;

        // Enable stream_ddr_awg_en=1 and cap_axis_en=1 (pkt len = 16 -> cap_pkt_len_m1 = 15)
        axil_write(16'h0010, 32'd15);
        axil_write(16'h0004, 32'h0000_02FD); // clr_underflow=1, cap_axis_en=1, stream_ddr_awg_en=1, global_en=1

        // Check M_AXIS_CAP stability under backpressure
        tlast_cnt = 0;
        for (k = 0; k < 60; k++) begin
            @(posedge clk);
            if (k == 10) begin
                wait (m_axis_cap_tvalid);
                m_axis_cap_tready <= 1'b0;
                @(posedge clk);
                #1;
                cap_hold_data = m_axis_cap_tdata;
                cap_hold_last = m_axis_cap_tlast;
                repeat (4) begin
                    @(posedge clk);
                    #1;
                    if (!m_axis_cap_tvalid || m_axis_cap_tdata !== cap_hold_data || m_axis_cap_tlast !== cap_hold_last) begin
                        $display("FAIL: M_AXIS_CAP violated AXI-Stream stability under !tready!");
                        err_cnt++;
                    end
                end
                m_axis_cap_tready <= 1'b1;
            end
            if (m_axis_cap_tvalid && m_axis_cap_tready && m_axis_cap_tlast) begin
                tlast_cnt++;
            end
        end

        if (tlast_cnt < 2) begin
            $display("FAIL: Expected >=2 TLAST frames on M_AXIS_CAP, got %0d", tlast_cnt);
            err_cnt++;
        end

        if (err_cnt == 0) begin
            $display("=== ALL TESTS PASSED (0 errors) ===");
        end else begin
            $display("=== TESTBENCH FAILED (%0d errors) ===", err_cnt);
            $fatal(1, "Simulation failed");
        end
        $finish;
    end

endmodule
