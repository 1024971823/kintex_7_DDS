`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Module: awg_stream_fifo
// Description:
//   Synchronous 512 x 64-bit AXI4-Stream FIFO for deep DDR3/XDMA AWG playback.
//   Packs 4 channels x 16-bit samples per 64-bit word: {ch3, ch2, ch1, ch0}.
// -----------------------------------------------------------------------------
module awg_stream_fifo #(
    parameter ADDR_W = 9 // 512 entries
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        stream_en,
    input  wire        clr_underflow,

    // AXI4-Stream Slave (from XDMA H2C or DDR3 DMA)
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    // Output to DAC mux
    output reg         out_valid,
    output reg  [63:0] out_data,
    output wire [ADDR_W:0] fill_level,
    output reg         underflow_sticky
);
    localparam DEPTH = (1 << ADDR_W);

    (* ram_style = "block" *)
    reg [63:0] mem [0:DEPTH-1];

    reg [ADDR_W:0] wr_ptr;
    reg [ADDR_W:0] rd_ptr;

    wire [ADDR_W:0] count = wr_ptr - rd_ptr;
    wire full  = (count == DEPTH);
    wire empty = (count == 0);

    assign s_axis_tready = !full;
    assign fill_level    = count;

    wire do_wr = s_axis_tvalid && s_axis_tready;
    wire do_rd = stream_en && !empty;

    always @(posedge clk) begin
        if (do_wr)
            mem[wr_ptr[ADDR_W-1:0]] <= s_axis_tdata;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr           <= {(ADDR_W+1){1'b0}};
            rd_ptr           <= {(ADDR_W+1){1'b0}};
            out_data         <= 64'd0;
            out_valid        <= 1'b0;
            underflow_sticky <= 1'b0;
        end else begin
            if (do_wr)
                wr_ptr <= wr_ptr + {{ADDR_W{1'b0}}, 1'b1};

            if (do_rd) begin
                out_data  <= mem[rd_ptr[ADDR_W-1:0]];
                out_valid <= 1'b1;
                rd_ptr    <= rd_ptr + {{ADDR_W{1'b0}}, 1'b1};
            end else begin
                out_valid <= 1'b0;
            end

            if (clr_underflow)
                underflow_sticky <= 1'b0;
            else if (stream_en && empty)
                underflow_sticky <= 1'b1;
        end
    end

endmodule
