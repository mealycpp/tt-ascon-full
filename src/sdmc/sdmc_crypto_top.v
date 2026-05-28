`default_nettype none

`include "sdmc_modes.vh"
`include "sdmc_stream_defs.vh"

module sdmc_crypto_top #(
    parameter FIFO_DEPTH = 8,
    parameter FIFO_AW    = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        start,

    input  wire        cfg_wr_en,
    input  wire [3:0]  cfg_wr_addr,
    input  wire [63:0] cfg_wr_data,

    input  wire [7:0]  in_byte,
    input  wire [3:0]  in_kind,
    input  wire        in_last,
    input  wire        in_valid,
    output wire        in_ready,

    output wire [7:0]  out_byte,
    output wire [3:0]  out_kind,
    output wire        out_last,
    output wire        out_valid,
    input  wire        out_ready,

    output wire        busy,
    output wire        done,
    output wire        error,
    output wire        auth_ok,

    output wire [3:0]  host_mode,
    output wire [3:0]  program_id,

    output wire [15:0] in_count,
    output wire [15:0] out_count
);

    wire use_cxof;
    wire is_decrypt;

    wire [15:0] chain_count;
    wire [15:0] msg_len;
    wire [15:0] cs_len;
    wire [15:0] ad_len;
    wire [15:0] out_len;

    sdmc_config_regs u_cfg (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),
        .cfg_wr_en   (cfg_wr_en),
        .cfg_wr_addr (cfg_wr_addr),
        .cfg_wr_data (cfg_wr_data),
        .host_mode   (host_mode),
        .program_id  (program_id),
        .use_cxof    (use_cxof),
        .is_decrypt  (is_decrypt),
        .chain_count (chain_count),
        .msg_len     (msg_len),
        .cs_len      (cs_len),
        .ad_len      (ad_len),
        .out_len     (out_len)
    );

    wire [`SDMC_TOKEN_W-1:0] core_in_token;
    wire                     core_in_empty;
    wire                     core_in_pop;

    wire [`SDMC_TOKEN_W-1:0] core_out_token;
    wire                     core_out_push;
    wire                     core_out_full;

    wire [FIFO_AW:0] in_count_w;
    wire [FIFO_AW:0] out_count_w;

    assign in_count  = {{(16-(FIFO_AW+1)){1'b0}}, in_count_w};
    assign out_count = {{(16-(FIFO_AW+1)){1'b0}}, out_count_w};

    sdmc_stream_shell #(
        .FIFO_DEPTH (FIFO_DEPTH),
        .FIFO_AW    (FIFO_AW)
    ) u_stream (
        .clk            (clk),
        .rst_n          (rst_n),
        .clear          (clear),

        .in_byte        (in_byte),
        .in_kind        (in_kind),
        .in_last        (in_last),
        .in_valid       (in_valid),
        .in_ready       (in_ready),

        .core_in_token  (core_in_token),
        .core_in_empty  (core_in_empty),
        .core_in_pop    (core_in_pop),

        .core_out_token (core_out_token),
        .core_out_push  (core_out_push),
        .core_out_full  (core_out_full),

        .out_byte       (out_byte),
        .out_kind       (out_kind),
        .out_last       (out_last),
        .out_valid      (out_valid),
        .out_ready      (out_ready),

        .in_count       (in_count_w),
        .out_count      (out_count_w)
    );

    wire sel_aead = (program_id == `SDMC_PROG_AEAD_FAMILY);
    wire aead_start = start & sel_aead;

    wire [`SDMC_TOKEN_W-1:0] aead_out_token;
    wire                     aead_out_push;
    wire                     aead_out_full;
    wire                     aead_in_pop;
    wire                     aead_busy;
    wire                     aead_done;
    wire                     aead_error;
    wire                     aead_auth_ok;

    sdmc_aead128_core u_aead (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (clear),
        .start      (aead_start),
        .is_decrypt (is_decrypt),
        .ad_len     (ad_len),
        .data_len   (msg_len),
        .in_token   (core_in_token),
        .in_empty   (core_in_empty),
        .in_pop     (aead_in_pop),
        .out_token  (aead_out_token),
        .out_push   (aead_out_push),
        .out_full   (aead_out_full),
        .busy       (aead_busy),
        .done       (aead_done),
        .error      (aead_error),
        .auth_ok    (aead_auth_ok)
    );

    assign core_in_pop    = sel_aead ? aead_in_pop : 1'b0;
    assign core_out_token = sel_aead ? aead_out_token : {`SDMC_TOKEN_W{1'b0}};
    assign core_out_push  = sel_aead ? aead_out_push : 1'b0;
    assign aead_out_full  = sel_aead ? core_out_full : 1'b1;

    assign busy    = aead_busy;
    assign done    = sel_aead & aead_done;
    assign error   = (start & !sel_aead) | aead_error;
    assign auth_ok = sel_aead ? aead_auth_ok : 1'b0;

    wire _unused_cfg = &{
        use_cxof,
        chain_count[0],
        cs_len[0],
        out_len[0],
        1'b0
    };

endmodule

`default_nettype wire
