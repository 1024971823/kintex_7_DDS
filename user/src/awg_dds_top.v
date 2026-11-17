`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Module: awg_dds_top
// Description:
//   Top-level 4-channel 16-bit High-Precision DDS + AWG Signal Generator.
//   Interfaces:
//     - AXI4-Lite Slave (s_axil_*): Config registers + 4x 4096x16 AWG BRAM
//     - AXI4-Stream Slave (s_axis_awg_*): 64-bit deep DDR3/XDMA AWG streaming
//     - AXI4-Stream Master (m_axis_cap_*): 64-bit host capture / loopback
//     - Parallel DAC outputs (dac_ch0..3_data, dac_valid)
//     - Hardware sync trigger & status LEDs
// -----------------------------------------------------------------------------
module awg_dds_top #(
    parameter integer NUM_CH = 4
) (
    input  wire        clk,
    input  wire        rst_n,

    // External hardware phase sync trigger (active high pulse)
    input  wire        ext_sync_trig,

    // AXI4-Lite Slave Control & AWG BRAM Load
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWADDR" *)
    input  wire [15:0] s_axil_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWVALID" *)
    input  wire        s_axil_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWREADY" *)
    output wire        s_axil_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WDATA" *)
    input  wire [31:0] s_axil_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WSTRB" *)
    input  wire [3:0]  s_axil_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WVALID" *)
    input  wire        s_axil_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WREADY" *)
    output wire        s_axil_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BRESP" *)
    output wire [1:0]  s_axil_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BVALID" *)
    output wire        s_axil_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BREADY" *)
    input  wire        s_axil_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARADDR" *)
    input  wire [15:0] s_axil_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARVALID" *)
    input  wire        s_axil_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARREADY" *)
    output wire        s_axil_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RDATA" *)
    output wire [31:0] s_axil_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RRESP" *)
    output wire [1:0]  s_axil_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RVALID" *)
    output wire        s_axil_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RREADY" *)
    input  wire        s_axil_rready,

    // AXI4-Stream Slave (Deep AWG playback from DDR3/XDMA: {ch3, ch2, ch1, ch0})
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_AWG TVALID" *)
    input  wire        s_axis_awg_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_AWG TREADY" *)
    output wire        s_axis_awg_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_AWG TDATA" *)
    input  wire [63:0] s_axis_awg_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_AWG TLAST" *)
    input  wire        s_axis_awg_tlast,

    // AXI4-Stream Master (Sample capture to XDMA C2H / ILA: {ch3, ch2, ch1, ch0})
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CAP TVALID" *)
    output reg         m_axis_cap_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CAP TREADY" *)
    input  wire        m_axis_cap_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CAP TDATA" *)
    output reg  [63:0] m_axis_cap_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_CAP TLAST" *)
    output reg         m_axis_cap_tlast,

    // Parallel DAC Outputs (16-bit per channel)
    output reg         dac_valid,
    output reg  [15:0] dac_ch0_data,
    output reg  [15:0] dac_ch1_data,
    output reg  [15:0] dac_ch2_data,
    output reg  [15:0] dac_ch3_data,

    // Status LEDs [2:0] -> matches board R24, T21, T20
    output wire [2:0]  status_led
);
    // Synchronize external trigger
    reg ext_sync_d1, ext_sync_d2, ext_sync_d3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ext_sync_d1 <= 1'b0;
            ext_sync_d2 <= 1'b0;
            ext_sync_d3 <= 1'b0;
        end else begin
            ext_sync_d1 <= ext_sync_trig;
            ext_sync_d2 <= ext_sync_d1;
            ext_sync_d3 <= ext_sync_d2;
        end
    end
    wire ext_sync_pulse = ext_sync_d2 && !ext_sync_d3;

    // Control signals from AXI4-Lite register file
    wire               global_enable;
    wire               soft_phase_sync;
    wire               stream_ddr_awg_en;
    wire               cap_axis_en;
    wire [NUM_CH-1:0]  ch_enable_mask;
    wire               dac_offset_bin;
    wire               clr_fifo_underflow;
    wire [31:0]        cap_pkt_len_m1;

    wire [NUM_CH*3-1:0]  cfg_wave_mode_flat;
    wire [NUM_CH*2-1:0]  cfg_mod_mode_flat;
    wire [NUM_CH-1:0]    cfg_mod_src_sel_flat;
    wire [NUM_CH-1:0]    cfg_awg_interp_en_flat;
    wire [NUM_CH-1:0]    cfg_awg_step_mode_flat;
    wire [NUM_CH-1:0]    cfg_sweep_en_flat;
    wire [NUM_CH-1:0]    cfg_sweep_mode_flat;
    wire [NUM_CH-1:0]    cfg_ch_rst_flat;
    wire [NUM_CH*48-1:0] cfg_ftw_flat;
    wire [NUM_CH*48-1:0] cfg_poff_flat;
    wire [NUM_CH*16-1:0] cfg_gain_flat;
    wire [NUM_CH*16-1:0] cfg_dc_offset_flat;
    wire [NUM_CH*16-1:0] cfg_duty_cycle_flat;
    wire [NUM_CH*32-1:0] cfg_mod_ftw_flat;
    wire [NUM_CH*16-1:0] cfg_am_depth_flat;
    wire [NUM_CH*16-1:0] cfg_fm_dev_flat;
    wire [NUM_CH*16-1:0] cfg_pm_dev_flat;
    wire [NUM_CH*48-1:0] cfg_sweep_step_flat;
    wire [NUM_CH*48-1:0] cfg_sweep_min_ftw_flat;
    wire [NUM_CH*48-1:0] cfg_sweep_max_ftw_flat;
    wire [NUM_CH*32-1:0] cfg_sweep_dwell_flat;
    wire [NUM_CH*12-1:0] cfg_awg_last_idx_flat;
    wire [NUM_CH*32-1:0] cfg_awg_dwell_flat;

    wire [NUM_CH-1:0]  awg_wr_even_en;
    wire [NUM_CH-1:0]  awg_wr_odd_en;
    wire [10:0]        awg_wr_word_addr;
    wire [15:0]        awg_wr_even_data;
    wire [15:0]        awg_wr_odd_data;

    wire [NUM_CH-1:0]  ch_valid_vec;
    wire               fifo_underflow_sticky;
    wire [9:0]         fifo_fill_level;

    awg_dds_axi_lite #(.NUM_CH(NUM_CH)) u_axil (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .s_axil_awaddr         (s_axil_awaddr),
        .s_axil_awvalid        (s_axil_awvalid),
        .s_axil_awready        (s_axil_awready),
        .s_axil_wdata          (s_axil_wdata),
        .s_axil_wstrb          (s_axil_wstrb),
        .s_axil_wvalid         (s_axil_wvalid),
        .s_axil_wready         (s_axil_wready),
        .s_axil_bresp          (s_axil_bresp),
        .s_axil_bvalid         (s_axil_bvalid),
        .s_axil_bready         (s_axil_bready),
        .s_axil_araddr         (s_axil_araddr),
        .s_axil_arvalid        (s_axil_arvalid),
        .s_axil_arready        (s_axil_arready),
        .s_axil_rdata          (s_axil_rdata),
        .s_axil_rresp          (s_axil_rresp),
        .s_axil_rvalid         (s_axil_rvalid),
        .s_axil_rready         (s_axil_rready),
        .st_ch_valid           (ch_valid_vec),
        .st_fifo_underflow     (fifo_underflow_sticky),
        .st_fifo_fill_level    (fifo_fill_level),
        .global_enable         (global_enable),
        .soft_phase_sync       (soft_phase_sync),
        .stream_ddr_awg_en     (stream_ddr_awg_en),
        .cap_axis_en           (cap_axis_en),
        .ch_enable_mask        (ch_enable_mask),
        .dac_offset_bin        (dac_offset_bin),
        .clr_fifo_underflow    (clr_fifo_underflow),
        .cap_pkt_len_m1        (cap_pkt_len_m1),
        .cfg_wave_mode_flat    (cfg_wave_mode_flat),
        .cfg_mod_mode_flat     (cfg_mod_mode_flat),
        .cfg_mod_src_sel_flat  (cfg_mod_src_sel_flat),
        .cfg_awg_interp_en_flat(cfg_awg_interp_en_flat),
        .cfg_awg_step_mode_flat(cfg_awg_step_mode_flat),
        .cfg_sweep_en_flat     (cfg_sweep_en_flat),
        .cfg_sweep_mode_flat   (cfg_sweep_mode_flat),
        .cfg_ch_rst_flat       (cfg_ch_rst_flat),
        .cfg_ftw_flat          (cfg_ftw_flat),
        .cfg_poff_flat         (cfg_poff_flat),
        .cfg_gain_flat         (cfg_gain_flat),
        .cfg_dc_offset_flat    (cfg_dc_offset_flat),
        .cfg_duty_cycle_flat   (cfg_duty_cycle_flat),
        .cfg_mod_ftw_flat      (cfg_mod_ftw_flat),
        .cfg_am_depth_flat     (cfg_am_depth_flat),
        .cfg_fm_dev_flat       (cfg_fm_dev_flat),
        .cfg_pm_dev_flat       (cfg_pm_dev_flat),
        .cfg_sweep_step_flat   (cfg_sweep_step_flat),
        .cfg_sweep_min_ftw_flat(cfg_sweep_min_ftw_flat),
        .cfg_sweep_max_ftw_flat(cfg_sweep_max_ftw_flat),
        .cfg_sweep_dwell_flat  (cfg_sweep_dwell_flat),
        .cfg_awg_last_idx_flat (cfg_awg_last_idx_flat),
        .cfg_awg_dwell_flat    (cfg_awg_dwell_flat),
        .awg_wr_even_en        (awg_wr_even_en),
        .awg_wr_odd_en         (awg_wr_odd_en),
        .awg_wr_word_addr      (awg_wr_word_addr),
        .awg_wr_even_data      (awg_wr_even_data),
        .awg_wr_odd_data       (awg_wr_odd_data)
    );

    // 4x DDS/AWG Channels
    wire signed [15:0] ch_sample [0:NUM_CH-1];
    wire               phase_sync_pulse = soft_phase_sync || ext_sync_pulse;

    genvar ch;
    generate
        for (ch = 0; ch < NUM_CH; ch = ch + 1) begin : gen_ch
            wire signed [15:0] mod_partner = ch_sample[(ch ^ 1)];

            dds_channel u_ch (
                .clk               (clk),
                .rst_n             (rst_n),
                .ch_enable         (global_enable && !stream_ddr_awg_en && ch_enable_mask[ch]),
                .phase_sync        (phase_sync_pulse),
                .cfg_wave_mode     (cfg_wave_mode_flat[ch*3 +: 3]),
                .cfg_mod_mode      (cfg_mod_mode_flat[ch*2 +: 2]),
                .cfg_mod_src_sel   (cfg_mod_src_sel_flat[ch]),
                .cfg_awg_interp_en (cfg_awg_interp_en_flat[ch]),
                .cfg_awg_step_mode (cfg_awg_step_mode_flat[ch]),
                .cfg_sweep_en      (cfg_sweep_en_flat[ch]),
                .cfg_sweep_mode    (cfg_sweep_mode_flat[ch]),
                .cfg_ch_rst        (cfg_ch_rst_flat[ch]),
                .cfg_ftw           (cfg_ftw_flat[ch*48 +: 48]),
                .cfg_poff          (cfg_poff_flat[ch*48 +: 48]),
                .cfg_gain          (cfg_gain_flat[ch*16 +: 16]),
                .cfg_dc_offset     ($signed(cfg_dc_offset_flat[ch*16 +: 16])),
                .cfg_duty_cycle    (cfg_duty_cycle_flat[ch*16 +: 16]),
                .cfg_mod_ftw       (cfg_mod_ftw_flat[ch*32 +: 32]),
                .cfg_am_depth      (cfg_am_depth_flat[ch*16 +: 16]),
                .cfg_fm_dev        (cfg_fm_dev_flat[ch*16 +: 16]),
                .cfg_pm_dev        (cfg_pm_dev_flat[ch*16 +: 16]),
                .cfg_sweep_step    (cfg_sweep_step_flat[ch*48 +: 48]),
                .cfg_sweep_min_ftw (cfg_sweep_min_ftw_flat[ch*48 +: 48]),
                .cfg_sweep_max_ftw (cfg_sweep_max_ftw_flat[ch*48 +: 48]),
                .cfg_sweep_dwell   (cfg_sweep_dwell_flat[ch*32 +: 32]),
                .cfg_awg_last_idx  (cfg_awg_last_idx_flat[ch*12 +: 12]),
                .cfg_awg_dwell     (cfg_awg_dwell_flat[ch*32 +: 32]),
                .awg_wr_even_en    (awg_wr_even_en[ch]),
                .awg_wr_odd_en     (awg_wr_odd_en[ch]),
                .awg_wr_word_addr  (awg_wr_word_addr),
                .awg_wr_even_data  (awg_wr_even_data),
                .awg_wr_odd_data   (awg_wr_odd_data),
                .mod_ext_in        (mod_partner),
                .valid_out         (ch_valid_vec[ch]),
                .sample_out        (ch_sample[ch])
            );
        end
    endgenerate

    // Deep DDR3 / XDMA Streaming AWG FIFO
    wire        stream_valid;
    wire [63:0] stream_data;
    awg_stream_fifo #(.ADDR_W(9)) u_stream_fifo (
        .clk              (clk),
        .rst_n            (rst_n),
        .stream_en        (global_enable && stream_ddr_awg_en),
        .clr_underflow    (clr_fifo_underflow),
        .s_axis_tvalid    (s_axis_awg_tvalid),
        .s_axis_tready    (s_axis_awg_tready),
        .s_axis_tdata     (s_axis_awg_tdata),
        .s_axis_tlast     (s_axis_awg_tlast),
        .out_valid        (stream_valid),
        .out_data         (stream_data),
        .fill_level       (fifo_fill_level),
        .underflow_sticky (fifo_underflow_sticky)
    );

    // Output Mux (DDS/BRAM-AWG vs Deep AXI-Stream AWG)
    wire        mux_valid = stream_ddr_awg_en ? stream_valid : (|ch_valid_vec);
    wire [15:0] mux_ch0   = stream_ddr_awg_en ? stream_data[15:0]  : ch_sample[0];
    wire [15:0] mux_ch1   = stream_ddr_awg_en ? stream_data[31:16] : ch_sample[1];
    wire [15:0] mux_ch2   = stream_ddr_awg_en ? stream_data[47:32] : ch_sample[2];
    wire [15:0] mux_ch3   = stream_ddr_awg_en ? stream_data[63:48] : ch_sample[3];

    wire [15:0] fmt_mask  = dac_offset_bin ? 16'h8000 : 16'h0000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dac_valid    <= 1'b0;
            dac_ch0_data <= 16'd0;
            dac_ch1_data <= 16'd0;
            dac_ch2_data <= 16'd0;
            dac_ch3_data <= 16'd0;
        end else begin
            dac_valid    <= mux_valid;
            dac_ch0_data <= mux_ch0 ^ fmt_mask;
            dac_ch1_data <= mux_ch1 ^ fmt_mask;
            dac_ch2_data <= mux_ch2 ^ fmt_mask;
            dac_ch3_data <= mux_ch3 ^ fmt_mask;
        end
    end

    // AXI4-Stream Master Capture Output (strict tvalid/tready stability)
    reg [31:0] cap_pkt_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_cap_tvalid <= 1'b0;
            m_axis_cap_tdata  <= 64'd0;
            m_axis_cap_tlast  <= 1'b0;
            cap_pkt_cnt       <= 32'd0;
        end else if (!m_axis_cap_tvalid || m_axis_cap_tready) begin
            if (cap_axis_en && mux_valid) begin
                m_axis_cap_tvalid <= 1'b1;
                m_axis_cap_tdata  <= {mux_ch3, mux_ch2, mux_ch1, mux_ch0};
                if (cap_pkt_cnt >= cap_pkt_len_m1) begin
                    m_axis_cap_tlast <= 1'b1;
                    cap_pkt_cnt      <= 32'd0;
                end else begin
                    m_axis_cap_tlast <= 1'b0;
                    cap_pkt_cnt      <= cap_pkt_cnt + 32'd1;
                end
            end else begin
                m_axis_cap_tvalid <= 1'b0;
                m_axis_cap_tlast  <= 1'b0;
                if (!cap_axis_en)
                    cap_pkt_cnt <= 32'd0;
            end
        end
    end

    // Status LEDs (active-high or board-dependent)
    reg [25:0] blink_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            blink_cnt <= 26'd0;
        else
            blink_cnt <= blink_cnt + 26'd1;
    end

    assign status_led[0] = blink_cnt[25];         // Heartbeat
    assign status_led[1] = global_enable;         // Output enabled
    assign status_led[2] = fifo_underflow_sticky; // Stream underflow alarm

endmodule
