`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Module: awg_dds_axi_lite
// Description:
//   AXI4-Lite Slave register bank and dual-bank AWG waveform BRAM loader
//   for 4-channel DDS / AWG system.
//   Address Map (16-bit byte address, 64 KB aperture):
//     0x0000..0x003F : Global control & status registers
//     0x0100 + ch*0x0100 (ch=0..3): Per-channel DDS/Mod/Sweep/AWG config
//     0x8000 + ch*0x2000 (ch=0..3): 4096x16-bit AWG BRAM (2 samples / 32b word)
// -----------------------------------------------------------------------------
module awg_dds_axi_lite #(
    parameter integer NUM_CH = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // AXI4-Lite Slave Interface
    input  wire [15:0]                 s_axil_awaddr,
    input  wire                        s_axil_awvalid,
    output wire                        s_axil_awready,
    input  wire [31:0]                 s_axil_wdata,
    input  wire [3:0]                  s_axil_wstrb,
    input  wire                        s_axil_wvalid,
    output wire                        s_axil_wready,
    output wire [1:0]                  s_axil_bresp,
    output reg                         s_axil_bvalid,
    input  wire                        s_axil_bready,

    input  wire [15:0]                 s_axil_araddr,
    input  wire                        s_axil_arvalid,
    output wire                        s_axil_arready,
    output reg  [31:0]                 s_axil_rdata,
    output wire [1:0]                  s_axil_rresp,
    output reg                         s_axil_rvalid,
    input  wire                        s_axil_rready,

    // Status inputs
    input  wire [NUM_CH-1:0]           st_ch_valid,
    input  wire                        st_fifo_underflow,
    input  wire [9:0]                  st_fifo_fill_level,

    // Global controls
    output reg                         global_enable,
    output reg                         soft_phase_sync,
    output reg                         stream_ddr_awg_en,
    output reg                         cap_axis_en,
    output reg  [NUM_CH-1:0]           ch_enable_mask,
    output reg                         dac_offset_bin,
    output reg                         clr_fifo_underflow,
    output reg  [31:0]                 cap_pkt_len_m1,

    // Packed per-channel config outputs
    output wire [NUM_CH*3-1:0]         cfg_wave_mode_flat,
    output wire [NUM_CH*2-1:0]         cfg_mod_mode_flat,
    output wire [NUM_CH-1:0]           cfg_mod_src_sel_flat,
    output wire [NUM_CH-1:0]           cfg_awg_interp_en_flat,
    output wire [NUM_CH-1:0]           cfg_awg_step_mode_flat,
    output wire [NUM_CH-1:0]           cfg_sweep_en_flat,
    output wire [NUM_CH-1:0]           cfg_sweep_mode_flat,
    output wire [NUM_CH-1:0]           cfg_ch_rst_flat,
    output wire [NUM_CH*48-1:0]        cfg_ftw_flat,
    output wire [NUM_CH*48-1:0]        cfg_poff_flat,
    output wire [NUM_CH*16-1:0]        cfg_gain_flat,
    output wire [NUM_CH*16-1:0]        cfg_dc_offset_flat,
    output wire [NUM_CH*16-1:0]        cfg_duty_cycle_flat,
    output wire [NUM_CH*32-1:0]        cfg_mod_ftw_flat,
    output wire [NUM_CH*16-1:0]        cfg_am_depth_flat,
    output wire [NUM_CH*16-1:0]        cfg_fm_dev_flat,
    output wire [NUM_CH*16-1:0]        cfg_pm_dev_flat,
    output wire [NUM_CH*48-1:0]        cfg_sweep_step_flat,
    output wire [NUM_CH*48-1:0]        cfg_sweep_min_ftw_flat,
    output wire [NUM_CH*48-1:0]        cfg_sweep_max_ftw_flat,
    output wire [NUM_CH*32-1:0]        cfg_sweep_dwell_flat,
    output wire [NUM_CH*12-1:0]        cfg_awg_last_idx_flat,
    output wire [NUM_CH*32-1:0]        cfg_awg_dwell_flat,

    // AWG BRAM write interface
    output reg  [NUM_CH-1:0]           awg_wr_even_en,
    output reg  [NUM_CH-1:0]           awg_wr_odd_en,
    output reg  [10:0]                 awg_wr_word_addr,
    output reg  [15:0]                 awg_wr_even_data,
    output reg  [15:0]                 awg_wr_odd_data
);
    localparam [31:0] IP_VERSION = 32'h4444_5301; // "DDS\x01"

    assign s_axil_bresp = 2'b00;
    assign s_axil_rresp = 2'b00;

    // Global registers
    reg [31:0] reg_sample_rate;
    reg [15:0] heartbeat_cnt;

    // Per-channel register arrays
    reg [2:0]  r_wave_mode     [0:NUM_CH-1];
    reg [1:0]  r_mod_mode      [0:NUM_CH-1];
    reg        r_mod_src_sel   [0:NUM_CH-1];
    reg        r_awg_interp_en [0:NUM_CH-1];
    reg        r_awg_step_mode [0:NUM_CH-1];
    reg        r_sweep_en      [0:NUM_CH-1];
    reg        r_sweep_mode    [0:NUM_CH-1];
    reg        r_ch_rst        [0:NUM_CH-1];
    reg [47:0] r_ftw           [0:NUM_CH-1];
    reg [47:0] r_poff          [0:NUM_CH-1];
    reg [15:0] r_gain          [0:NUM_CH-1];
    reg [15:0] r_dc_offset     [0:NUM_CH-1];
    reg [15:0] r_duty_cycle    [0:NUM_CH-1];
    reg [31:0] r_mod_ftw       [0:NUM_CH-1];
    reg [15:0] r_am_depth      [0:NUM_CH-1];
    reg [15:0] r_fm_dev        [0:NUM_CH-1];
    reg [15:0] r_pm_dev        [0:NUM_CH-1];
    reg [47:0] r_sweep_step    [0:NUM_CH-1];
    reg [47:0] r_sweep_min_ftw [0:NUM_CH-1];
    reg [47:0] r_sweep_max_ftw [0:NUM_CH-1];
    reg [31:0] r_sweep_dwell   [0:NUM_CH-1];
    reg [11:0] r_awg_last_idx  [0:NUM_CH-1];
    reg [31:0] r_awg_dwell     [0:NUM_CH-1];

    genvar g;
    generate
        for (g = 0; g < NUM_CH; g = g + 1) begin : gen_pack
            assign cfg_wave_mode_flat[g*3 +: 3]       = r_wave_mode[g];
            assign cfg_mod_mode_flat[g*2 +: 2]        = r_mod_mode[g];
            assign cfg_mod_src_sel_flat[g]            = r_mod_src_sel[g];
            assign cfg_awg_interp_en_flat[g]          = r_awg_interp_en[g];
            assign cfg_awg_step_mode_flat[g]          = r_awg_step_mode[g];
            assign cfg_sweep_en_flat[g]               = r_sweep_en[g];
            assign cfg_sweep_mode_flat[g]             = r_sweep_mode[g];
            assign cfg_ch_rst_flat[g]                 = r_ch_rst[g];
            assign cfg_ftw_flat[g*48 +: 48]           = r_ftw[g];
            assign cfg_poff_flat[g*48 +: 48]          = r_poff[g];
            assign cfg_gain_flat[g*16 +: 16]          = r_gain[g];
            assign cfg_dc_offset_flat[g*16 +: 16]     = r_dc_offset[g];
            assign cfg_duty_cycle_flat[g*16 +: 16]    = r_duty_cycle[g];
            assign cfg_mod_ftw_flat[g*32 +: 32]       = r_mod_ftw[g];
            assign cfg_am_depth_flat[g*16 +: 16]      = r_am_depth[g];
            assign cfg_fm_dev_flat[g*16 +: 16]        = r_fm_dev[g];
            assign cfg_pm_dev_flat[g*16 +: 16]        = r_pm_dev[g];
            assign cfg_sweep_step_flat[g*48 +: 48]    = r_sweep_step[g];
            assign cfg_sweep_min_ftw_flat[g*48 +: 48] = r_sweep_min_ftw[g];
            assign cfg_sweep_max_ftw_flat[g*48 +: 48] = r_sweep_max_ftw[g];
            assign cfg_sweep_dwell_flat[g*32 +: 32]   = r_sweep_dwell[g];
            assign cfg_awg_last_idx_flat[g*12 +: 12]  = r_awg_last_idx[g];
            assign cfg_awg_dwell_flat[g*32 +: 32]     = r_awg_dwell[g];
        end
    endgenerate

    // AXI4-Lite write handshake (decoupled AW/W)
    reg        aw_seen;
    reg        w_seen;
    reg [15:0] awaddr_r;
    reg [31:0] wdata_r;
    reg [3:0]  wstrb_r;

    assign s_axil_awready = !aw_seen && !s_axil_bvalid;
    assign s_axil_wready  = !w_seen  && !s_axil_bvalid;
    assign s_axil_arready = !s_axil_rvalid;

    wire [31:0] wmask = {
        {8{wstrb_r[3]}}, {8{wstrb_r[2]}}, {8{wstrb_r[1]}}, {8{wstrb_r[0]}}
    };

    integer i;
    wire [1:0] wr_bram_ch = awaddr_r[14:13];
    wire [2:0] wr_reg_ch  = awaddr_r[10:8] - 3'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_seen            <= 1'b0;
            w_seen             <= 1'b0;
            awaddr_r           <= 16'd0;
            wdata_r            <= 32'd0;
            wstrb_r            <= 4'd0;
            s_axil_bvalid      <= 1'b0;

            heartbeat_cnt      <= 16'd0;
            global_enable      <= 1'b0;
            soft_phase_sync    <= 1'b0;
            stream_ddr_awg_en  <= 1'b0;
            cap_axis_en        <= 1'b0;
            ch_enable_mask     <= {NUM_CH{1'b1}};
            dac_offset_bin     <= 1'b0;
            clr_fifo_underflow <= 1'b0;
            reg_sample_rate    <= 32'd200_000_000;
            cap_pkt_len_m1     <= 32'd1023;

            awg_wr_even_en     <= {NUM_CH{1'b0}};
            awg_wr_odd_en      <= {NUM_CH{1'b0}};
            awg_wr_word_addr   <= 11'd0;
            awg_wr_even_data   <= 16'd0;
            awg_wr_odd_data    <= 16'd0;

            for (i = 0; i < NUM_CH; i = i + 1) begin
                r_wave_mode[i]     <= 3'd0;
                r_mod_mode[i]      <= 2'd0;
                r_mod_src_sel[i]   <= 1'b0;
                r_awg_interp_en[i] <= 1'b1;
                r_awg_step_mode[i] <= 1'b0;
                r_sweep_en[i]      <= 1'b0;
                r_sweep_mode[i]    <= 1'b0;
                r_ch_rst[i]        <= 1'b0;
                r_ftw[i]           <= 48'd0;
                r_poff[i]          <= 48'd0;
                r_gain[i]          <= 16'h8000; // 1.0x
                r_dc_offset[i]     <= 16'd0;
                r_duty_cycle[i]    <= 16'h8000; // 50%
                r_mod_ftw[i]       <= 32'd0;
                r_am_depth[i]      <= 16'h8000;
                r_fm_dev[i]        <= 16'd0;
                r_pm_dev[i]        <= 16'd0;
                r_sweep_step[i]    <= 48'd0;
                r_sweep_min_ftw[i] <= 48'd0;
                r_sweep_max_ftw[i] <= 48'd0;
                r_sweep_dwell[i]   <= 32'd0;
                r_awg_last_idx[i]  <= 12'd4095;
                r_awg_dwell[i]     <= 32'd0;
            end
        end else begin
            heartbeat_cnt      <= heartbeat_cnt + 16'd1;
            soft_phase_sync    <= 1'b0;
            clr_fifo_underflow <= 1'b0;
            awg_wr_even_en     <= {NUM_CH{1'b0}};
            awg_wr_odd_en      <= {NUM_CH{1'b0}};

            if (s_axil_awvalid && s_axil_awready) begin
                aw_seen  <= 1'b1;
                awaddr_r <= s_axil_awaddr;
            end
            if (s_axil_wvalid && s_axil_wready) begin
                w_seen  <= 1'b1;
                wdata_r <= s_axil_wdata;
                wstrb_r <= s_axil_wstrb;
            end
            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end

            // Commit write once both AW and W have been captured
            if (aw_seen && w_seen && !s_axil_bvalid) begin
                aw_seen       <= 1'b0;
                w_seen        <= 1'b0;
                s_axil_bvalid <= 1'b1;

                if (awaddr_r[15] == 1'b1) begin
                    // 0x8000..0xFFFF: AWG BRAM aperture (2 samples/word)
                    awg_wr_word_addr <= awaddr_r[12:2];
                    awg_wr_even_data <= wdata_r[15:0];
                    awg_wr_odd_data  <= wdata_r[31:16];
                    if (wstrb_r[1:0] == 2'b11)
                        awg_wr_even_en[wr_bram_ch] <= 1'b1;
                    if (wstrb_r[3:2] == 2'b11)
                        awg_wr_odd_en[wr_bram_ch] <= 1'b1;
                end else if (awaddr_r[15:8] == 8'h00) begin
                    // Global registers
                    case (awaddr_r[7:2])
                        6'h01: begin // 0x0004: GLOBAL_CTRL
                            if (wstrb_r[0]) begin
                                global_enable     <= wdata_r[0];
                                soft_phase_sync   <= wdata_r[1];
                                stream_ddr_awg_en <= wdata_r[2];
                                cap_axis_en       <= wdata_r[3];
                                ch_enable_mask    <= wdata_r[7:4];
                            end
                            if (wstrb_r[1]) begin
                                dac_offset_bin     <= wdata_r[8];
                                clr_fifo_underflow <= wdata_r[9];
                            end
                        end
                        6'h03: reg_sample_rate <= (reg_sample_rate & ~wmask) | (wdata_r & wmask);
                        6'h04: cap_pkt_len_m1  <= (cap_pkt_len_m1  & ~wmask) | (wdata_r & wmask);
                        default: ;
                    endcase
                end else if (awaddr_r[15:11] == 5'd0 && awaddr_r[10:8] >= 3'd1 && awaddr_r[10:8] <= NUM_CH) begin
                    // Per-channel registers (0x0100..0x04FF)
                    case (awaddr_r[7:2])
                        6'h00: begin // +0x00 CH_CTRL
                            if (wstrb_r[0]) begin
                                r_wave_mode[wr_reg_ch]     <= wdata_r[2:0];
                                r_mod_mode[wr_reg_ch]      <= wdata_r[4:3];
                                r_mod_src_sel[wr_reg_ch]   <= wdata_r[5];
                                r_awg_interp_en[wr_reg_ch] <= wdata_r[6];
                                r_awg_step_mode[wr_reg_ch] <= wdata_r[7];
                            end
                            if (wstrb_r[1]) begin
                                r_sweep_en[wr_reg_ch]   <= wdata_r[8];
                                r_sweep_mode[wr_reg_ch] <= wdata_r[9];
                                r_ch_rst[wr_reg_ch]     <= wdata_r[10];
                            end
                        end
                        6'h01: r_ftw[wr_reg_ch][31:0]  <= (r_ftw[wr_reg_ch][31:0]  & ~wmask) | (wdata_r & wmask);
                        6'h02: r_ftw[wr_reg_ch][47:32] <= (r_ftw[wr_reg_ch][47:32] & ~wmask[15:0]) | (wdata_r[15:0] & wmask[15:0]);
                        6'h03: r_poff[wr_reg_ch][31:0] <= (r_poff[wr_reg_ch][31:0] & ~wmask) | (wdata_r & wmask);
                        6'h04: r_poff[wr_reg_ch][47:32]<= (r_poff[wr_reg_ch][47:32]& ~wmask[15:0]) | (wdata_r[15:0] & wmask[15:0]);
                        6'h05: begin
                            r_gain[wr_reg_ch]      <= (r_gain[wr_reg_ch]      & ~wmask[15:0])  | (wdata_r[15:0]  & wmask[15:0]);
                            r_dc_offset[wr_reg_ch] <= (r_dc_offset[wr_reg_ch] & ~wmask[31:16]) | (wdata_r[31:16] & wmask[31:16]);
                        end
                        6'h06: r_duty_cycle[wr_reg_ch] <= (r_duty_cycle[wr_reg_ch] & ~wmask[15:0]) | (wdata_r[15:0] & wmask[15:0]);
                        6'h07: r_mod_ftw[wr_reg_ch]    <= (r_mod_ftw[wr_reg_ch]    & ~wmask)       | (wdata_r & wmask);
                        6'h08: begin
                            r_am_depth[wr_reg_ch] <= (r_am_depth[wr_reg_ch] & ~wmask[15:0])  | (wdata_r[15:0]  & wmask[15:0]);
                            r_fm_dev[wr_reg_ch]   <= (r_fm_dev[wr_reg_ch]   & ~wmask[31:16]) | (wdata_r[31:16] & wmask[31:16]);
                        end
                        6'h09: r_pm_dev[wr_reg_ch]            <= (r_pm_dev[wr_reg_ch]            & ~wmask[15:0]) | (wdata_r[15:0] & wmask[15:0]);
                        6'h0A: r_sweep_step[wr_reg_ch][31:0]  <= (r_sweep_step[wr_reg_ch][31:0]  & ~wmask)       | (wdata_r & wmask);
                        6'h0B: r_sweep_step[wr_reg_ch][47:32] <= (r_sweep_step[wr_reg_ch][47:32] & ~wmask[15:0]) | (wdata_r[15:0] & wmask[15:0]);
                        6'h0C: r_sweep_min_ftw[wr_reg_ch][31:0]  <= (r_sweep_min_ftw[wr_reg_ch][31:0]  & ~wmask)       | (wdata_r & wmask);
                        6'h0D: r_sweep_min_ftw[wr_reg_ch][47:32] <= (r_sweep_min_ftw[wr_reg_ch][47:32] & ~wmask[15:0]) | (wdata_r[15:0] & wmask[15:0]);
                        6'h0E: r_sweep_max_ftw[wr_reg_ch][31:0]  <= (r_sweep_max_ftw[wr_reg_ch][31:0]  & ~wmask)       | (wdata_r & wmask);
                        6'h0F: r_sweep_max_ftw[wr_reg_ch][47:32] <= (r_sweep_max_ftw[wr_reg_ch][47:32] & ~wmask[15:0]) | (wdata_r[15:0] & wmask[15:0]);
                        6'h10: r_sweep_dwell[wr_reg_ch]          <= (r_sweep_dwell[wr_reg_ch]          & ~wmask)       | (wdata_r & wmask);
                        6'h11: r_awg_last_idx[wr_reg_ch]         <= (r_awg_last_idx[wr_reg_ch]         & ~wmask[11:0]) | (wdata_r[11:0] & wmask[11:0]);
                        6'h12: r_awg_dwell[wr_reg_ch]            <= (r_awg_dwell[wr_reg_ch]            & ~wmask)       | (wdata_r & wmask);
                        default: ;
                    endcase
                end
            end
        end
    end

    // AXI4-Lite Read logic
    wire [2:0] rd_reg_ch = s_axil_araddr[10:8] - 3'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= 32'd0;
        end else begin
            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;

            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid <= 1'b1;
                s_axil_rdata  <= 32'd0;

                if (s_axil_araddr[15:8] == 8'h00) begin
                    case (s_axil_araddr[7:2])
                        6'h00: s_axil_rdata <= IP_VERSION;
                        6'h01: s_axil_rdata <= {23'd0, dac_offset_bin, ch_enable_mask, cap_axis_en, stream_ddr_awg_en, 1'b0, global_enable};
                        6'h02: s_axil_rdata <= {heartbeat_cnt, st_fifo_fill_level, st_fifo_underflow, 1'b0, st_ch_valid};
                        6'h03: s_axil_rdata <= reg_sample_rate;
                        6'h04: s_axil_rdata <= cap_pkt_len_m1;
                        default: s_axil_rdata <= 32'd0;
                    endcase
                end else if (s_axil_araddr[15:11] == 5'd0 && s_axil_araddr[10:8] >= 3'd1 && s_axil_araddr[10:8] <= NUM_CH) begin
                    case (s_axil_araddr[7:2])
                        6'h00: s_axil_rdata <= {21'd0, r_ch_rst[rd_reg_ch], r_sweep_mode[rd_reg_ch], r_sweep_en[rd_reg_ch],
                                                r_awg_step_mode[rd_reg_ch], r_awg_interp_en[rd_reg_ch], r_mod_src_sel[rd_reg_ch],
                                                r_mod_mode[rd_reg_ch], r_wave_mode[rd_reg_ch]};
                        6'h01: s_axil_rdata <= r_ftw[rd_reg_ch][31:0];
                        6'h02: s_axil_rdata <= {16'd0, r_ftw[rd_reg_ch][47:32]};
                        6'h03: s_axil_rdata <= r_poff[rd_reg_ch][31:0];
                        6'h04: s_axil_rdata <= {16'd0, r_poff[rd_reg_ch][47:32]};
                        6'h05: s_axil_rdata <= {r_dc_offset[rd_reg_ch], r_gain[rd_reg_ch]};
                        6'h06: s_axil_rdata <= {16'd0, r_duty_cycle[rd_reg_ch]};
                        6'h07: s_axil_rdata <= r_mod_ftw[rd_reg_ch];
                        6'h08: s_axil_rdata <= {r_fm_dev[rd_reg_ch], r_am_depth[rd_reg_ch]};
                        6'h09: s_axil_rdata <= {16'd0, r_pm_dev[rd_reg_ch]};
                        6'h0A: s_axil_rdata <= r_sweep_step[rd_reg_ch][31:0];
                        6'h0B: s_axil_rdata <= {16'd0, r_sweep_step[rd_reg_ch][47:32]};
                        6'h0C: s_axil_rdata <= r_sweep_min_ftw[rd_reg_ch][31:0];
                        6'h0D: s_axil_rdata <= {16'd0, r_sweep_min_ftw[rd_reg_ch][47:32]};
                        6'h0E: s_axil_rdata <= r_sweep_max_ftw[rd_reg_ch][31:0];
                        6'h0F: s_axil_rdata <= {16'd0, r_sweep_max_ftw[rd_reg_ch][47:32]};
                        6'h10: s_axil_rdata <= r_sweep_dwell[rd_reg_ch];
                        6'h11: s_axil_rdata <= {20'd0, r_awg_last_idx[rd_reg_ch]};
                        6'h12: s_axil_rdata <= r_awg_dwell[rd_reg_ch];
                        default: s_axil_rdata <= 32'd0;
                    endcase
                end
            end
        end
    end

endmodule
