`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Module: dds_channel
// Description:
//   Single high-precision DDS + AWG waveform generator channel.
//   Features:
//     - 48-bit phase accumulator + 48-bit phase offset + coherent phase_sync
//     - Linear frequency sweep (Chirp: sawtooth or triangle bounce)
//     - AM, FM, PM modulation (internal 32-bit NCO or external/cross-channel)
//     - 6 waveform modes:
//         0: High-SFDR Sine (quarter-wave LUT + linear interpolation)
//         1: Square / Programmable-duty PWM
//         2: Triangle
//         3: Sawtooth
//         4: AWG 4096x16 BRAM (phase-accum interpolated or direct index step)
//         5: PRBS32 Noise
//     - Programmable Gain (Q1.15) & signed DC offset with saturation clamping
// -----------------------------------------------------------------------------
module dds_channel (
    input  wire               clk,
    input  wire               rst_n,

    // Global & sync controls
    input  wire               ch_enable,
    input  wire               phase_sync,

    // Channel configuration
    input  wire [2:0]         cfg_wave_mode,
    input  wire [1:0]         cfg_mod_mode,      // 0:none, 1:AM, 2:FM, 3:PM
    input  wire               cfg_mod_src_sel,   // 0:internal NCO, 1:mod_ext_in
    input  wire               cfg_awg_interp_en,
    input  wire               cfg_awg_step_mode, // 0:phase-acc, 1:direct counter
    input  wire               cfg_sweep_en,
    input  wire               cfg_sweep_mode,    // 0:sawtooth, 1:triangle
    input  wire               cfg_ch_rst,

    input  wire [47:0]        cfg_ftw,
    input  wire [47:0]        cfg_poff,
    input  wire [15:0]        cfg_gain,          // unsigned Q1.15 (0x8000 = 1.0x)
    input  wire signed [15:0] cfg_dc_offset,
    input  wire [15:0]        cfg_duty_cycle,    // 0x8000 = 50%

    // Modulation config
    input  wire [31:0]        cfg_mod_ftw,
    input  wire [15:0]        cfg_am_depth,      // 0x8000 = 100% AM
    input  wire [15:0]        cfg_fm_dev,        // scaled by 2^14
    input  wire [15:0]        cfg_pm_dev,        // 0xFFFF = +/- 180 deg

    // Sweep (Chirp) config
    input  wire [47:0]        cfg_sweep_step,
    input  wire [47:0]        cfg_sweep_min_ftw,
    input  wire [47:0]        cfg_sweep_max_ftw,
    input  wire [31:0]        cfg_sweep_dwell,

    // Direct-step AWG config
    input  wire [11:0]        cfg_awg_last_idx,
    input  wire [31:0]        cfg_awg_dwell,

    // AWG BRAM write interface (2 samples/word)
    input  wire               awg_wr_even_en,
    input  wire               awg_wr_odd_en,
    input  wire [10:0]        awg_wr_word_addr,
    input  wire [15:0]        awg_wr_even_data,
    input  wire [15:0]        awg_wr_odd_data,

    // Cross-channel modulation input
    input  wire signed [15:0] mod_ext_in,

    // Output sample (signed 16-bit)
    output reg                valid_out,
    output reg  signed [15:0] sample_out
);
    localparam [2:0]
        WAVE_SINE = 3'd0,
        WAVE_SQR  = 3'd1,
        WAVE_TRI  = 3'd2,
        WAVE_SAW  = 3'd3,
        WAVE_AWG  = 3'd4,
        WAVE_PRBS = 3'd5;

    localparam [1:0]
        MOD_NONE = 2'd0,
        MOD_AM   = 2'd1,
        MOD_FM   = 2'd2,
        MOD_PM   = 2'd3;

    wire active = ch_enable && !cfg_ch_rst;

    // -------------------------------------------------------------------------
    // 1. Internal Modulation NCO & Source Mux
    // -------------------------------------------------------------------------
    wire signed [15:0] mod_nco_out;
    dds_mod_nco u_mod_nco (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (active && (cfg_mod_mode != MOD_NONE)),
        .sync    (phase_sync),
        .mod_ftw (cfg_mod_ftw),
        .mod_out (mod_nco_out)
    );

    reg signed [15:0] mod_val_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mod_val_r <= 16'sd0;
        else
            mod_val_r <= cfg_mod_src_sel ? mod_ext_in : mod_nco_out;
    end

    // -------------------------------------------------------------------------
    // 2. Linear Frequency Sweep (Chirp) Engine
    // -------------------------------------------------------------------------
    reg [47:0] sweep_ftw;
    reg        sweep_dir; // 0: up, 1: down
    reg [31:0] sweep_dwell_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sweep_ftw       <= 48'd0;
            sweep_dir       <= 1'b0;
            sweep_dwell_cnt <= 32'd0;
        end else if (!active || !cfg_sweep_en || phase_sync) begin
            sweep_ftw       <= cfg_sweep_min_ftw;
            sweep_dir       <= 1'b0;
            sweep_dwell_cnt <= 32'd0;
        end else begin
            if (sweep_dwell_cnt >= cfg_sweep_dwell) begin
                sweep_dwell_cnt <= 32'd0;
                if (sweep_dir == 1'b0) begin
                    if (sweep_ftw + cfg_sweep_step >= cfg_sweep_max_ftw) begin
                        if (cfg_sweep_mode) begin
                            sweep_ftw <= cfg_sweep_max_ftw;
                            sweep_dir <= 1'b1;
                        end else begin
                            sweep_ftw <= cfg_sweep_min_ftw;
                        end
                    end else begin
                        sweep_ftw <= sweep_ftw + cfg_sweep_step;
                    end
                end else begin
                    if (sweep_ftw <= cfg_sweep_min_ftw + cfg_sweep_step) begin
                        sweep_ftw <= cfg_sweep_min_ftw;
                        sweep_dir <= 1'b0;
                    end else begin
                        sweep_ftw <= sweep_ftw - cfg_sweep_step;
                    end
                end
            end else begin
                sweep_dwell_cnt <= sweep_dwell_cnt + 32'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. Phase Accumulator + FM / PM
    // -------------------------------------------------------------------------
    wire [47:0] base_ftw = cfg_sweep_en ? sweep_ftw : cfg_ftw;

    wire signed [32:0] fm_prod = $signed(mod_val_r) * $signed({1'b0, cfg_fm_dev});
    wire signed [47:0] fm_delta = (cfg_mod_mode == MOD_FM) ? ({{15{fm_prod[32]}}, fm_prod} <<< 14) : 48'sd0;
    wire [47:0]        ftw_eff  = base_ftw + fm_delta;

    reg [47:0] phase_acc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 48'd0;
        end else if (!active || phase_sync) begin
            phase_acc <= 48'd0;
        end else begin
            phase_acc <= phase_acc + ftw_eff;
        end
    end

    wire signed [32:0] pm_prod = $signed(mod_val_r) * $signed({1'b0, cfg_pm_dev});
    wire signed [47:0] pm_delta = (cfg_mod_mode == MOD_PM) ? ({{15{pm_prod[32]}}, pm_prod} <<< 16) : 48'sd0;
    wire [47:0]        phase_eff = phase_acc + cfg_poff + pm_delta;

    // Direct-step AWG counter (optional)
    reg [11:0] awg_step_cnt;
    reg [31:0] awg_dwell_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awg_step_cnt  <= 12'd0;
            awg_dwell_cnt <= 32'd0;
        end else if (!active || phase_sync || !cfg_awg_step_mode) begin
            awg_step_cnt  <= 12'd0;
            awg_dwell_cnt <= 32'd0;
        end else begin
            if (awg_dwell_cnt >= cfg_awg_dwell) begin
                awg_dwell_cnt <= 32'd0;
                awg_step_cnt  <= (awg_step_cnt >= cfg_awg_last_idx) ? 12'd0 : (awg_step_cnt + 12'd1);
            end else begin
                awg_dwell_cnt <= awg_dwell_cnt + 32'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Waveform Generators (Aligned to 4-cycle latency)
    // -------------------------------------------------------------------------
    // 4a. High-SFDR Sine LUT (4-cycle pipeline)
    wire               sine_valid;
    wire signed [15:0] sine_wave;
    dds_sin_lut u_sin_lut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (active),
        .phase_in  (phase_eff[47:24]),
        .valid_out (sine_valid),
        .sine_out  (sine_wave)
    );

    // 4b. AWG BRAM + 4-cycle linear interpolation pipeline
    wire [11:0] awg_rd_addr      = cfg_awg_step_mode ? awg_step_cnt : phase_eff[47:36];
    wire [11:0] awg_rd_addr_next = cfg_awg_step_mode ? awg_step_cnt : (phase_eff[47:36] + 12'd1);
    wire [10:0] awg_frac_w       = (cfg_awg_interp_en && !cfg_awg_step_mode) ? phase_eff[35:25] : 11'd0;

    wire [15:0] awg_s0_w;
    wire [15:0] awg_s1_w;
    awg_wave_ram u_awg_ram (
        .clk          (clk),
        .wr_even_en   (awg_wr_even_en),
        .wr_odd_en    (awg_wr_odd_en),
        .wr_word_addr (awg_wr_word_addr),
        .wr_even_data (awg_wr_even_data),
        .wr_odd_data  (awg_wr_odd_data),
        .rd_addr      (awg_rd_addr),
        .rd_addr_next (awg_rd_addr_next),
        .s0_out       (awg_s0_w),
        .s1_out       (awg_s1_w)
    );

    reg [10:0]        awg_frac_d1, awg_frac_d2;
    reg signed [15:0] awg_s0_d2;
    reg signed [16:0] awg_sdiff_d2;
    reg signed [27:0] awg_interp_d3;
    reg signed [15:0] awg_wave_d4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awg_frac_d1   <= 11'd0;
            awg_frac_d2   <= 11'd0;
            awg_s0_d2     <= 16'sd0;
            awg_sdiff_d2  <= 17'sd0;
            awg_interp_d3 <= 28'sd0;
            awg_wave_d4   <= 16'sd0;
        end else begin
            // Stage 1 (aligned with BRAM output)
            awg_frac_d1   <= awg_frac_w;
            // Stage 2
            awg_s0_d2     <= $signed(awg_s0_w);
            awg_sdiff_d2  <= $signed({awg_s1_w[15], awg_s1_w}) - $signed({awg_s0_w[15], awg_s0_w});
            awg_frac_d2   <= awg_frac_d1;
            // Stage 3
            awg_interp_d3 <= ($signed(awg_s0_d2) <<< 11) + ($signed(awg_sdiff_d2) * $signed({1'b0, awg_frac_d2}));
            // Stage 4
            awg_wave_d4   <= awg_interp_d3[26:11];
        end
    end

    // 4c. Geometric waveforms + PRBS32 (registered + delayed to Stage 4)
    reg [31:0] lfsr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 32'hACE1_1357;
        else if (!active)
            lfsr <= 32'hACE1_1357;
        else
            lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end

    wire signed [15:0] sqr_s0 = (phase_eff[47:32] < cfg_duty_cycle) ? 16'sd32767 : -16'sd32767;
    wire [15:0]        tri_u  = phase_eff[47] ? ~phase_eff[46:31] : phase_eff[46:31];
    wire signed [15:0] tri_s0 = $signed({~tri_u[15], tri_u[14:0]});
    wire signed [15:0] saw_s0 = $signed({~phase_eff[47], phase_eff[46:32]});
    wire signed [15:0] prb_s0 = $signed(lfsr[15:0]);

    reg signed [15:0] geom_d1, geom_d2, geom_d3, geom_d4;
    reg signed [15:0] mod_d1, mod_d2, mod_d3, mod_d4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            geom_d1 <= 16'sd0; geom_d2 <= 16'sd0; geom_d3 <= 16'sd0; geom_d4 <= 16'sd0;
            mod_d1  <= 16'sd0; mod_d2  <= 16'sd0; mod_d3  <= 16'sd0; mod_d4  <= 16'sd0;
        end else begin
            case (cfg_wave_mode)
                WAVE_SQR : geom_d1 <= sqr_s0;
                WAVE_TRI : geom_d1 <= tri_s0;
                WAVE_SAW : geom_d1 <= saw_s0;
                WAVE_PRBS: geom_d1 <= prb_s0;
                default  : geom_d1 <= 16'sd0;
            endcase
            geom_d2 <= geom_d1;
            geom_d3 <= geom_d2;
            geom_d4 <= geom_d3;

            mod_d1  <= mod_val_r;
            mod_d2  <= mod_d1;
            mod_d3  <= mod_d2;
            mod_d4  <= mod_d3;
        end
    end

    // Mux aligned Stage 4 raw waveform
    reg signed [15:0] wave_s4;
    always @(*) begin
        case (cfg_wave_mode)
            WAVE_SINE: wave_s4 = sine_wave;
            WAVE_AWG : wave_s4 = awg_wave_d4;
            default  : wave_s4 = geom_d4;
        endcase
    end

    // -------------------------------------------------------------------------
    // 5. Stage 5: AM Modulation + Programmable Gain (Q1.15)
    // -------------------------------------------------------------------------
    wire signed [32:0] am_prod = $signed(mod_d4) * $signed({1'b0, cfg_am_depth});
    wire signed [17:0] am_env_raw = 18'sd32768 + $signed(am_prod[32:15]);
    wire [15:0]        am_env_clamped = (am_env_raw < 18'sd0)     ? 16'd0 :
                                        (am_env_raw > 18'sd65535) ? 16'd65535 :
                                                                    am_env_raw[15:0];

    wire [31:0] am_gain_prod = am_env_clamped * cfg_gain;
    wire [16:0] eff_gain_w   = (cfg_mod_mode == MOD_AM) ? am_gain_prod[31:15] : {1'b0, cfg_gain};

    (* use_dsp = "yes" *)
    reg signed [33:0] scaled_d5;
    reg               valid_d5;
    reg               active_d1, active_d2, active_d3, active_d4, active_d5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scaled_d5 <= 34'sd0;
            valid_d5  <= 1'b0;
            active_d1 <= 1'b0; active_d2 <= 1'b0; active_d3 <= 1'b0;
            active_d4 <= 1'b0; active_d5 <= 1'b0;
        end else begin
            active_d1 <= active;
            active_d2 <= active_d1;
            active_d3 <= active_d2;
            active_d4 <= active_d3;
            active_d5 <= active_d4;

            scaled_d5 <= $signed(wave_s4) * $signed({1'b0, eff_gain_w});
            valid_d5  <= sine_valid;
        end
    end

    // -------------------------------------------------------------------------
    // 6. Stage 6: Rounding, DC Offset, Signed Saturation Clamping
    // -------------------------------------------------------------------------
    wire signed [33:0] scaled_rounded = scaled_d5 + 34'sd16384;
    wire signed [18:0] scaled_16_ext  = scaled_rounded[33:15];
    wire signed [18:0] offset_sum     = scaled_16_ext + $signed({{3{cfg_dc_offset[15]}}, cfg_dc_offset});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_out <= 16'sd0;
            valid_out  <= 1'b0;
        end else begin
            valid_out <= valid_d5;
            if (!active_d5) begin
                sample_out <= 16'sd0;
            end else if (offset_sum > 19'sd32767) begin
                sample_out <= 16'sd32767;
            end else if (offset_sum < -19'sd32768) begin
                sample_out <= -16'sd32768;
            end else begin
                sample_out <= offset_sum[15:0];
            end
        end
    end

endmodule
