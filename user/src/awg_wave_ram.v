`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Module: awg_wave_ram
// Description:
//   4096 x 16-bit arbitrary waveform dual-bank BRAM (even/odd split).
//   Allows AXI4-Lite writes on port A and simultaneous 1-cycle fetch of
//   adjacent samples (s0 = RAM[rd_addr], s1 = RAM[rd_addr_next]) on port B
//   when rd_addr and rd_addr_next have opposite parity (e.g. power-of-2 wrap).
// -----------------------------------------------------------------------------
module awg_wave_ram (
    input  wire        clk,
    // Write port (AXI4-Lite domain, 2 samples per 32-bit word)
    input  wire        wr_even_en,
    input  wire        wr_odd_en,
    input  wire [10:0] wr_word_addr,
    input  wire [15:0] wr_even_data,
    input  wire [15:0] wr_odd_data,
    // Read port (DDS/AWG domain)
    input  wire [11:0] rd_addr,
    input  wire [11:0] rd_addr_next,
    output reg  [15:0] s0_out,
    output reg  [15:0] s1_out
);
    (* ram_style = "block" *)
    reg [15:0] ram_even [0:2047];
    (* ram_style = "block" *)
    reg [15:0] ram_odd  [0:2047];

    integer idx;
    initial begin
        for (idx = 0; idx < 2048; idx = idx + 1) begin
            ram_even[idx] = 16'd0;
            ram_odd[idx]  = 16'd0;
        end
    end

    // Port A write (even and odd banks are independent BRAMs)
    always @(posedge clk) begin
        if (wr_even_en)
            ram_even[wr_word_addr] <= wr_even_data;
        if (wr_odd_en)
            ram_odd[wr_word_addr]  <= wr_odd_data;
    end

    // Port B dual read (even/odd bank routing)
    wire [10:0] addr_even = rd_addr[0] ? rd_addr_next[11:1] : rd_addr[11:1];
    wire [10:0] addr_odd  = rd_addr[0] ? rd_addr[11:1]      : rd_addr_next[11:1];

    reg [15:0] dout_even;
    reg [15:0] dout_odd;
    reg        rd_parity_d1;

    always @(posedge clk) begin
        dout_even    <= ram_even[addr_even];
        dout_odd     <= ram_odd[addr_odd];
        rd_parity_d1 <= rd_addr[0];
    end

    always @(*) begin
        if (rd_parity_d1 == 1'b0) begin
            s0_out = dout_even;
            s1_out = dout_odd;
        end else begin
            s0_out = dout_odd;
            s1_out = dout_even;
        end
    end

endmodule
