`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Module: dds_sin_lut
// Description:
//   High-SFDR quarter-wave sine generator with linear interpolation.
//   Input phase_in[23:0] represents [0, 2*pi):
//     - [23:22]: quadrant (00: 0..pi/2, 01: pi/2..pi, 10: pi..3pi/2, 11: 3pi/2..2pi)
//     - [21:11]: 11-bit quarter-wave LUT index (2048 steps)
//     - [10:0] : 11-bit fractional interpolation weight
//   Fixed pipeline latency: 4 clock cycles, 1 sample/clock throughput.
//   Output sine_out is signed 16-bit in [-32767, +32767] (zero DC bias).
// -----------------------------------------------------------------------------
module dds_sin_lut (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               valid_in,
    input  wire [23:0]        phase_in,
    output reg                valid_out,
    output reg  signed [15:0] sine_out
);
    localparam [17:0] AMP_PEAK = 18'd262136; // 32767 * 8

    // Stage 0: Quadrant folding and even/odd bank address decode
    wire [1:0]  quad      = phase_in[23:22];
    wire [21:0] sub_phase = quad[0] ? ~phase_in[21:0] : phase_in[21:0];
    wire [10:0] k_idx     = sub_phase[21:11];
    wire [10:0] frac_w    = sub_phase[10:0];
    wire        is_last_w = (k_idx == 11'd2047);

    wire [9:0]  addr_even = k_idx[0] ? (k_idx[10:1] + 10'd1) : k_idx[10:1];
    wire [9:0]  addr_odd  = k_idx[10:1];

    wire [17:0] dout_even;
    wire [17:0] dout_odd;

    dds_sin_qtr_rom u_rom (
        .clk       (clk),
        .addr_even (addr_even),
        .addr_odd  (addr_odd),
        .dout_even (dout_even),
        .dout_odd  (dout_odd)
    );

    // Stage 1 registers (aligned with ROM output)
    reg        k0_d1;
    reg        is_last_d1;
    reg [10:0] frac_d1;
    reg        sign_d1;
    reg        valid_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k0_d1      <= 1'b0;
            is_last_d1 <= 1'b0;
            frac_d1    <= 11'd0;
            sign_d1    <= 1'b0;
            valid_d1   <= 1'b0;
        end else begin
            k0_d1      <= k_idx[0];
            is_last_d1 <= is_last_w;
            frac_d1    <= frac_w;
            sign_d1    <= quad[1];
            valid_d1   <= valid_in;
        end
    end

    // Stage 2: Select y0/y1 and compute slope diff
    wire [17:0] y0_w = k0_d1 ? dout_odd : dout_even;
    wire [17:0] y1_w = is_last_d1 ? AMP_PEAK : (k0_d1 ? dout_even : dout_odd);

    reg [17:0] y0_d2;
    reg [17:0] diff_d2;
    reg [10:0] frac_d2;
    reg        sign_d2;
    reg        valid_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y0_d2    <= 18'd0;
            diff_d2  <= 18'd0;
            frac_d2  <= 11'd0;
            sign_d2  <= 1'b0;
            valid_d2 <= 1'b0;
        end else begin
            y0_d2    <= y0_w;
            diff_d2  <= y1_w - y0_w;
            frac_d2  <= frac_d1;
            sign_d2  <= sign_d1;
            valid_d2 <= valid_d1;
        end
    end

    // Stage 3: Linear interpolation y0 * 2^11 + diff * frac
    (* use_dsp = "yes" *)
    reg [28:0] mag_d3;
    reg        sign_d3;
    reg        valid_d3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mag_d3   <= 29'd0;
            sign_d3  <= 1'b0;
            valid_d3 <= 1'b0;
        end else begin
            mag_d3   <= {y0_d2, 11'd0} + (diff_d2 * frac_d2);
            sign_d3  <= sign_d2;
            valid_d3 <= valid_d2;
        end
    end

    // Stage 4: Round to 15-bit magnitude and apply quadrant sign
    wire [28:0] mag_round = mag_d3 + 29'd8192;
    wire [14:0] mag_15    = (mag_round > 29'd536862720) ? 15'd32767 : mag_round[28:14];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sine_out  <= 16'sd0;
            valid_out <= 1'b0;
        end else begin
            sine_out  <= sign_d3 ? -$signed({1'b0, mag_15}) : $signed({1'b0, mag_15});
            valid_out <= valid_d3;
        end
    end

endmodule
