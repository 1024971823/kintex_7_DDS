`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Module: dds_mod_nco
// Description:
//   Lightweight 32-bit NCO for internal AM/FM/PM modulation.
//   Uses a 64-entry quarter-wave sine table with 8-bit linear interpolation
//   (0 BRAM blocks) to produce a clean 16-bit signed modulation signal.
// -----------------------------------------------------------------------------
module dds_mod_nco (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               en,
    input  wire               sync,
    input  wire [31:0]        mod_ftw,
    output reg  signed [15:0] mod_out
);
    reg [31:0] phase_acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 32'd0;
        end else if (sync || !en) begin
            phase_acc <= 32'd0;
        end else begin
            phase_acc <= phase_acc + mod_ftw;
        end
    end

    // Quarter-wave 64-entry table (15-bit unsigned 0..32767)
    function [14:0] qtr_sin_lut;
        input [6:0] idx;
        begin
            case (idx)
                7'd0 : qtr_sin_lut = 15'd0;
                7'd1 : qtr_sin_lut = 15'd804;
                7'd2 : qtr_sin_lut = 15'd1608;
                7'd3 : qtr_sin_lut = 15'd2410;
                7'd4 : qtr_sin_lut = 15'd3212;
                7'd5 : qtr_sin_lut = 15'd4011;
                7'd6 : qtr_sin_lut = 15'd4808;
                7'd7 : qtr_sin_lut = 15'd5602;
                7'd8 : qtr_sin_lut = 15'd6393;
                7'd9 : qtr_sin_lut = 15'd7179;
                7'd10: qtr_sin_lut = 15'd7962;
                7'd11: qtr_sin_lut = 15'd8739;
                7'd12: qtr_sin_lut = 15'd9512;
                7'd13: qtr_sin_lut = 15'd10278;
                7'd14: qtr_sin_lut = 15'd11039;
                7'd15: qtr_sin_lut = 15'd11793;
                7'd16: qtr_sin_lut = 15'd12539;
                7'd17: qtr_sin_lut = 15'd13279;
                7'd18: qtr_sin_lut = 15'd14010;
                7'd19: qtr_sin_lut = 15'd14732;
                7'd20: qtr_sin_lut = 15'd15446;
                7'd21: qtr_sin_lut = 15'd16151;
                7'd22: qtr_sin_lut = 15'd16846;
                7'd23: qtr_sin_lut = 15'd17530;
                7'd24: qtr_sin_lut = 15'd18204;
                7'd25: qtr_sin_lut = 15'd18868;
                7'd26: qtr_sin_lut = 15'd19519;
                7'd27: qtr_sin_lut = 15'd20159;
                7'd28: qtr_sin_lut = 15'd20787;
                7'd29: qtr_sin_lut = 15'd21403;
                7'd30: qtr_sin_lut = 15'd22005;
                7'd31: qtr_sin_lut = 15'd22594;
                7'd32: qtr_sin_lut = 15'd23170;
                7'd33: qtr_sin_lut = 15'd23731;
                7'd34: qtr_sin_lut = 15'd24279;
                7'd35: qtr_sin_lut = 15'd24811;
                7'd36: qtr_sin_lut = 15'd25329;
                7'd37: qtr_sin_lut = 15'd25832;
                7'd38: qtr_sin_lut = 15'd26319;
                7'd39: qtr_sin_lut = 15'd26790;
                7'd40: qtr_sin_lut = 15'd27245;
                7'd41: qtr_sin_lut = 15'd27683;
                7'd42: qtr_sin_lut = 15'd28105;
                7'd43: qtr_sin_lut = 15'd28510;
                7'd44: qtr_sin_lut = 15'd28898;
                7'd45: qtr_sin_lut = 15'd29268;
                7'd46: qtr_sin_lut = 15'd29621;
                7'd47: qtr_sin_lut = 15'd29956;
                7'd48: qtr_sin_lut = 15'd30273;
                7'd49: qtr_sin_lut = 15'd30571;
                7'd50: qtr_sin_lut = 15'd30852;
                7'd51: qtr_sin_lut = 15'd31113;
                7'd52: qtr_sin_lut = 15'd31356;
                7'd53: qtr_sin_lut = 15'd31580;
                7'd54: qtr_sin_lut = 15'd31785;
                7'd55: qtr_sin_lut = 15'd31971;
                7'd56: qtr_sin_lut = 15'd32137;
                7'd57: qtr_sin_lut = 15'd32285;
                7'd58: qtr_sin_lut = 15'd32412;
                7'd59: qtr_sin_lut = 15'd32521;
                7'd60: qtr_sin_lut = 15'd32609;
                7'd61: qtr_sin_lut = 15'd32678;
                7'd62: qtr_sin_lut = 15'd32728;
                7'd63: qtr_sin_lut = 15'd32757;
                default: qtr_sin_lut = 15'd32767;
            endcase
        end
    endfunction

    wire [1:0]  quad = phase_acc[31:30];
    wire [29:0] sub  = quad[0] ? ~phase_acc[29:0] : phase_acc[29:0];
    wire [5:0]  idx  = sub[29:24];
    wire [7:0]  frac = sub[23:16];

    reg [14:0] y0_r, y1_r;
    reg [7:0]  frac_r;
    reg        sign_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y0_r   <= 15'd0;
            y1_r   <= 15'd0;
            frac_r <= 8'd0;
            sign_r <= 1'b0;
        end else begin
            y0_r   <= qtr_sin_lut({1'b0, idx});
            y1_r   <= qtr_sin_lut({1'b0, idx} + 7'd1);
            frac_r <= frac;
            sign_r <= quad[1];
        end
    end

    wire [14:0] diff_w = y1_r - y0_r;
    wire [22:0] prod_w = diff_w * frac_r;
    wire [14:0] mag_w  = y0_r + prod_w[22:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mod_out <= 16'sd0;
        end else if (!en) begin
            mod_out <= 16'sd0;
        end else begin
            mod_out <= sign_r ? -$signed({1'b0, mag_w}) : $signed({1'b0, mag_w});
        end
    end

endmodule
