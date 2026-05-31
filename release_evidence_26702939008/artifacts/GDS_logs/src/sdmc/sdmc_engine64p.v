`default_nettype none

`include "sdmc_modes.vh"

module sdmc_engine64p (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        start,

    input  wire        cfg_wr_en,
    input  wire [3:0]  cfg_wr_addr,
    input  wire [63:0] cfg_wr_data,

    input  wire        host_wr_en,
    input  wire [3:0]  host_wr_addr,
    input  wire [63:0] host_wr_data,
    output wire        host_ready,

    output wire        busy,
    output wire        done,

    output wire [3:0]  host_mode,
    output wire [3:0]  program_id,

    output wire        use_cxof,
    output wire        is_decrypt,

    output wire [15:0] chain_count,
    output wire [15:0] msg_len,
    output wire [15:0] cs_len,
    output wire [15:0] ad_len,
    output wire [15:0] out_len,

    output wire [63:0] result,

    output wire [63:0] r0,
    output wire [63:0] r1,
    output wire [63:0] r2,
    output wire [63:0] r3,
    output wire [63:0] r4,

    output wire [63:0] p0,
    output wire [63:0] p1,
    output wire [63:0] p2,
    output wire [63:0] p3,
    output wire [63:0] p4
);

    wire       seq_cmd_valid;
    wire       seq_cmd_ready;
    wire [1:0] seq_cmd_type;
    wire [3:0] seq_cmd_op;
    wire [3:0] seq_cmd_dst;
    wire [3:0] seq_cmd_src_a;
    wire [3:0] seq_cmd_src_b;
    wire [3:0] seq_cmd_n;
    wire       seq_cmd_writeback;
    wire [2:0] seq_cmd_perm_lane;
    wire [3:0] seq_cmd_rounds;

    wire seq_busy;
    wire seq_done;

    wire exec_busy;
    wire exec_done;
    wire exec_host_ready;

    assign busy       = seq_busy | exec_busy;
    assign done       = seq_done;
    assign host_ready = (!seq_busy) & exec_host_ready;

    sdmc_config_regs u_cfg (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),

        .cfg_wr_en   (cfg_wr_en & host_ready),
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

    sdmc_uop_sequencer64p u_seq (
        .clk            (clk),
        .rst_n          (rst_n),
        .clear          (clear),

        .start          (start),
        .program_id     (program_id),

        .cmd_valid      (seq_cmd_valid),
        .cmd_ready      (seq_cmd_ready),
        .cmd_type       (seq_cmd_type),
        .cmd_op         (seq_cmd_op),
        .cmd_dst        (seq_cmd_dst),
        .cmd_src_a      (seq_cmd_src_a),
        .cmd_src_b      (seq_cmd_src_b),
        .cmd_n          (seq_cmd_n),
        .cmd_writeback  (seq_cmd_writeback),
        .cmd_perm_lane  (seq_cmd_perm_lane),
        .cmd_rounds     (seq_cmd_rounds),

        .exec_done      (exec_done),

        .busy           (seq_busy),
        .done           (seq_done)
    );

    sdmc_uop_exec64p u_exec (
        .clk            (clk),
        .rst_n          (rst_n),
        .clear          (clear),

        .host_wr_en     (host_wr_en & host_ready),
        .host_wr_addr   (host_wr_addr),
        .host_wr_data   (host_wr_data),
        .host_ready     (exec_host_ready),

        .cmd_valid      (seq_cmd_valid),
        .cmd_ready      (seq_cmd_ready),
        .cmd_type       (seq_cmd_type),
        .cmd_op         (seq_cmd_op),
        .cmd_dst        (seq_cmd_dst),
        .cmd_src_a      (seq_cmd_src_a),
        .cmd_src_b      (seq_cmd_src_b),
        .cmd_n          (seq_cmd_n),
        .cmd_writeback  (seq_cmd_writeback),
        .cmd_perm_lane  (seq_cmd_perm_lane),
        .cmd_rounds     (seq_cmd_rounds),

        .busy           (exec_busy),
        .done           (exec_done),
        .result         (result),

        .r0             (r0),
        .r1             (r1),
        .r2             (r2),
        .r3             (r3),
        .r4             (r4),

        .p0             (p0),
        .p1             (p1),
        .p2             (p2),
        .p3             (p3),
        .p4             (p4)
    );

endmodule

`default_nettype wire
