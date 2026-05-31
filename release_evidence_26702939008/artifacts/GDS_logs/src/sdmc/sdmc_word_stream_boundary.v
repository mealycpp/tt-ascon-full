`default_nettype none

module sdmc_word_stream_boundary #(
    parameter FIFO_DEPTH = 4,
    parameter FIFO_AW    = 2
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,

    input  wire [7:0] byte_in,
    input  wire       byte_in_valid,
    output wire       byte_in_ready,
    input  wire       byte_in_flush,

    output wire [7:0] byte_out,
    output wire       byte_out_valid,
    input  wire       byte_out_ready,

    output wire       word_fifo_full,
    output wire       word_fifo_empty,
    output wire [FIFO_AW:0] word_fifo_count
);

    wire [63:0] pack_word;
    wire [3:0]  pack_count;
    wire        pack_valid;
    wire        pack_ready;

    sdmc_byte_to_word u_pack (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (clear),
        .in_byte   (byte_in),
        .in_valid  (byte_in_valid),
        .in_ready  (byte_in_ready),
        .flush     (byte_in_flush),
        .out_word  (pack_word),
        .out_count (pack_count),
        .out_valid (pack_valid),
        .out_ready (pack_ready)
    );

    wire [67:0] fifo_din  = {pack_count, pack_word};
    wire [67:0] fifo_dout;
    wire        fifo_push = pack_valid && pack_ready;
    wire        fifo_pop;
    wire        unpack_ready;

    assign pack_ready = !word_fifo_full;
    assign fifo_pop   = (!word_fifo_empty) && unpack_ready;

    sdmc_fifo #(
        .WIDTH (68),
        .DEPTH (FIFO_DEPTH),
        .AW    (FIFO_AW)
    ) u_word_fifo (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (clear),
        .push  (fifo_push),
        .din   (fifo_din),
        .full  (word_fifo_full),
        .pop   (fifo_pop),
        .dout  (fifo_dout),
        .empty (word_fifo_empty),
        .count (word_fifo_count)
    );

    sdmc_word_to_byte u_unpack (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (clear),
        .in_word   (fifo_dout[63:0]),
        .in_count  (fifo_dout[67:64]),
        .in_valid  (!word_fifo_empty),
        .in_ready  (unpack_ready),
        .out_byte  (byte_out),
        .out_valid (byte_out_valid),
        .out_ready (byte_out_ready)
    );

endmodule

`default_nettype wire
