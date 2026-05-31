`default_nettype none

`include "src/sdmc/sdmc_stream_defs.vh"

module sdmc_stream_shell #(
    parameter FIFO_DEPTH = 4,
    parameter FIFO_AW    = 2
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire [7:0]               in_byte,
    input  wire [3:0]               in_kind,
    input  wire                     in_last,
    input  wire                     in_valid,
    output wire                     in_ready,

    output wire [`SDMC_TOKEN_W-1:0] core_in_token,
    output wire                     core_in_empty,
    input  wire                     core_in_pop,

    input  wire [`SDMC_TOKEN_W-1:0] core_out_token,
    input  wire                     core_out_push,
    output wire                     core_out_full,

    output wire [7:0]               out_byte,
    output wire [3:0]               out_kind,
    output wire                     out_last,
    output wire                     out_valid,
    input  wire                     out_ready,

    output wire [FIFO_AW:0]         in_count,
    output wire [FIFO_AW:0]         out_count
);

    wire ingress_push;
    wire [`SDMC_TOKEN_W-1:0] ingress_token;
    wire in_fifo_full;

    sdmc_stream_ingress u_ingress (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (clear),

        .in_byte   (in_byte),
        .in_kind   (in_kind),
        .in_last   (in_last),
        .in_valid  (in_valid),
        .in_ready  (in_ready),

        .tok_push  (ingress_push),
        .tok_din   (ingress_token),
        .tok_full  (in_fifo_full)
    );

    sdmc_token_fifo #(
        .DEPTH(FIFO_DEPTH),
        .AW(FIFO_AW)
    ) u_in_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .clear  (clear),

        .push   (ingress_push),
        .din    (ingress_token),
        .full   (in_fifo_full),

        .pop    (core_in_pop),
        .dout   (core_in_token),
        .empty  (core_in_empty),

        .count  (in_count)
    );

    wire [`SDMC_TOKEN_W-1:0] out_fifo_token;
    wire out_fifo_empty;
    wire out_fifo_pop;

    sdmc_token_fifo #(
        .DEPTH(FIFO_DEPTH),
        .AW(FIFO_AW)
    ) u_out_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .clear  (clear),

        .push   (core_out_push),
        .din    (core_out_token),
        .full   (core_out_full),

        .pop    (out_fifo_pop),
        .dout   (out_fifo_token),
        .empty  (out_fifo_empty),

        .count  (out_count)
    );

    sdmc_stream_egress u_egress (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (clear),

        .tok_dout  (out_fifo_token),
        .tok_empty (out_fifo_empty),
        .tok_pop   (out_fifo_pop),

        .out_byte  (out_byte),
        .out_kind  (out_kind),
        .out_last  (out_last),
        .out_valid (out_valid),
        .out_ready (out_ready)
    );

endmodule

`default_nettype wire
