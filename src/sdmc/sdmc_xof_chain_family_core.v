`default_nettype none

`include "src/sdmc/sdmc_stream_defs.vh"

module sdmc_xof_chain_family_core (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire                     start,
    input  wire                     use_hash,
    input  wire                     use_cxof,
    input  wire [15:0]              chain_count,
    input  wire [15:0]              msg_len,
    input  wire [15:0]              cs_len,
    input  wire [15:0]              out_len,

    input  wire [`SDMC_TOKEN_W-1:0] in_token,
    input  wire                     in_empty,
    output wire                     in_pop,

    output wire [`SDMC_TOKEN_W-1:0] out_token,
    output wire                     out_push,
    input  wire                     out_full,

    output reg                      busy,
    output reg                      done,
    output reg                      error,

    // External shared ASCON permutation interface.
    output wire                     perm_wr_en,
    output wire [2:0]               perm_wr_lane,
    output wire [63:0]              perm_wr_data,
    output wire                     perm_rd_en,
    output wire [2:0]               perm_rd_lane,
    input  wire [63:0]              perm_rd_data,
    input  wire                     perm_rd_valid,
    output wire                     perm_start,
    output wire [3:0]               perm_rounds_q,
    input  wire                     perm_ready,
    input  wire                     perm_busy,
    input  wire                     perm_done,
    input  wire [63:0]              p0,
    input  wire [63:0]              p1,
    input  wire [63:0]              p2,
    input  wire [63:0]              p3,
    input  wire [63:0]              p4
);

    localparam S_IDLE       = 3'd0;
    localparam S_START_PASS = 3'd1;
    localparam S_RUN_PASS   = 3'd2;
    localparam S_NEXT_PASS  = 3'd3;
    localparam S_DONE       = 3'd4;
    localparam S_ERR        = 3'd5;

    localparam CS_CACHE_DEPTH = 4;
    localparam CS_CACHE_AW    = 2;

    reg [2:0] state;

    reg [15:0] passes_left;
    reg        pass0_q;

    reg [63:0] digest0;
    reg [63:0] digest1;
    reg [63:0] digest2;
    reg [63:0] digest3;

    reg [1:0] capture_idx;
    reg [2:0] feed_idx;

    reg [`SDMC_TOKEN_W-1:0] cs_cache0_q;
    reg [`SDMC_TOKEN_W-1:0] cs_cache1_q;
    reg [`SDMC_TOKEN_W-1:0] cs_cache2_q;
    reg [`SDMC_TOKEN_W-1:0] cs_cache3_q;
    reg [CS_CACHE_AW:0]     cs_cache_count;
    reg [CS_CACHE_AW:0]     cs_replay_idx;
    reg                     cs_cache_hold_q;
    reg                     cs_cache_overflow;
    reg                     empty_msg_pending_q;
    reg [15:0]              cs_tokens_left_q;

    // Timing isolation for CXOF-chain customization-string caching.
    // This stages the full token, not only the 64-bit payload, so the
    // {last, kind, count, data} fields remain coherent.
    reg [`SDMC_TOKEN_W-1:0] cs_stage_token_q;
    reg [CS_CACHE_AW-1:0]   cs_stage_slot_q;
    reg                     cs_stage_valid_q;
    reg                     inner_done_hold_q;
    reg                     inner_error_hold_q;

    reg inner_start;

    wire inner_done;
    wire inner_busy;
    wire inner_error;

    wire [`SDMC_TOKEN_W-1:0] inner_in_token;
    wire inner_in_empty;
    wire inner_in_pop;

    wire [`SDMC_TOKEN_W-1:0] inner_out_token;
    wire inner_out_push;
    wire inner_out_full;

    wire final_pass = (passes_left == 16'd1);

    wire [63:0] feed_word =
        (feed_idx[1:0] == 2'd0) ? digest0 :
        (feed_idx[1:0] == 2'd1) ? digest1 :
        (feed_idx[1:0] == 2'd2) ? digest2 :
                                  digest3;

    wire [`SDMC_TOKEN_W-1:0] internal_msg_token =
        { (feed_idx == 3'd3), `SDMC_TOK_MSG, 4'd8, feed_word };

    wire [15:0] expected_cs_tokens_w =
        ((!use_hash) && use_cxof && (cs_len != 16'd0)) ?
        ((cs_len + 16'd7) >> 3) : 16'd0;

    wire feeding_cached_cs = (!pass0_q) && (!use_hash) && use_cxof && (cs_replay_idx < cs_cache_count);
    wire [`SDMC_TOKEN_W-1:0] cached_cs_token =
        (cs_replay_idx[CS_CACHE_AW-1:0] == 2'd0) ? cs_cache0_q :
        (cs_replay_idx[CS_CACHE_AW-1:0] == 2'd1) ? cs_cache1_q :
        (cs_replay_idx[CS_CACHE_AW-1:0] == 2'd2) ? cs_cache2_q :
                                                    cs_cache3_q;

    // First-pass empty-message injection.
    // Token layout is {last, kind[3:0], count[3:0], data[63:0]}.
    // For msg_len==0 the generated benches may keep in_empty=1 forever.
    // The inner XOF/HASH core still needs one LAST message token with count=0.
    wire empty_msg_fire = pass0_q && empty_msg_pending_q && (cs_tokens_left_q == 16'd0);

    wire [`SDMC_TOKEN_W-1:0] empty_msg_token =
        {1'b1, `SDMC_TOK_MSG, 4'd0, 64'd0};

    assign inner_in_token = empty_msg_fire ? empty_msg_token :
                            (pass0_q ? in_token :
                            (feeding_cached_cs ? cached_cs_token : internal_msg_token));

    assign inner_in_empty = empty_msg_fire ? 1'b0 :
                            (pass0_q ? in_empty :
                            (feeding_cached_cs ? 1'b0 : (feed_idx >= 3'd4)));

    // Synthetic empty token is internal; do not pop the external input stream.
    assign in_pop = (pass0_q && !empty_msg_fire) ? inner_in_pop : 1'b0;

    assign inner_out_full = final_pass ? out_full : 1'b0;
    assign out_token      = final_pass ? inner_out_token : {`SDMC_TOKEN_W{1'b0}};
    assign out_push       = final_pass ? inner_out_push  : 1'b0;

    sdmc_xof_family_core u_single (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),

        .start       (inner_start),
        .use_hash    (use_hash),
        .use_cxof    ((!use_hash) && use_cxof),
        .chain_count (16'd1),
        .cs_len      (use_hash ? 16'd0 : cs_len),
        .out_len     (use_hash ? 16'd32 : (final_pass ? out_len : 16'd32)),
        .msg_len     (pass0_q ? msg_len : 16'd32),

        .in_token    (inner_in_token),
        .in_empty    (inner_in_empty),
        .in_pop      (inner_in_pop),

        .out_token   (inner_out_token),
        .out_push    (inner_out_push),
        .out_full    (inner_out_full),

        .busy        (inner_busy),
        .done        (inner_done),
        .error       (inner_error),

        .perm_wr_en    (perm_wr_en),
        .perm_wr_lane  (perm_wr_lane),
        .perm_wr_data  (perm_wr_data),
        .perm_rd_en    (perm_rd_en),
        .perm_rd_lane  (perm_rd_lane),
        .perm_rd_data  (perm_rd_data),
        .perm_rd_valid (perm_rd_valid),
        .perm_start    (perm_start),
        .perm_rounds_q (perm_rounds_q),
        .perm_ready    (perm_ready),
        .perm_busy     (perm_busy),
        .perm_done     (perm_done),
        .p0            (p0),
        .p1            (p1),
        .p2            (p2),
        .p3            (p3),
        .p4            (p4)
    );

    wire _unused = &{use_cxof, cs_len[0], inner_busy, 1'b0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            passes_left <= 16'd0;
            pass0_q     <= 1'b1;
            digest0     <= 64'd0;
            digest1     <= 64'd0;
            digest2     <= 64'd0;
            digest3     <= 64'd0;
            capture_idx <= 2'd0;
            feed_idx    <= 3'd0;
            cs_cache_count    <= {CS_CACHE_AW+1{1'b0}};
            cs_replay_idx      <= {CS_CACHE_AW+1{1'b0}};
            cs_cache_hold_q    <= 1'b0;
            cs_cache_overflow  <= 1'b0;
            empty_msg_pending_q <= 1'b0;
            cs_tokens_left_q     <= 16'd0;
            cs_cache0_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_cache1_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_cache2_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_cache3_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_stage_token_q   <= {`SDMC_TOKEN_W{1'b0}};
            cs_stage_slot_q    <= {CS_CACHE_AW{1'b0}};
            cs_stage_valid_q   <= 1'b0;
            inner_done_hold_q  <= 1'b0;
            inner_error_hold_q <= 1'b0;
            inner_start    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
        end else if (clear) begin
            state       <= S_IDLE;
            passes_left <= 16'd0;
            pass0_q     <= 1'b1;
            digest0     <= 64'd0;
            digest1     <= 64'd0;
            digest2     <= 64'd0;
            digest3     <= 64'd0;
            capture_idx <= 2'd0;
            feed_idx    <= 3'd0;
            cs_cache_count    <= {CS_CACHE_AW+1{1'b0}};
            cs_replay_idx      <= {CS_CACHE_AW+1{1'b0}};
            cs_cache_hold_q    <= 1'b0;
            cs_cache_overflow  <= 1'b0;
            empty_msg_pending_q <= 1'b0;
            cs_tokens_left_q     <= 16'd0;
            cs_cache0_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_cache1_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_cache2_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_cache3_q        <= {`SDMC_TOKEN_W{1'b0}};
            cs_stage_token_q   <= {`SDMC_TOKEN_W{1'b0}};
            cs_stage_slot_q    <= {CS_CACHE_AW{1'b0}};
            cs_stage_valid_q   <= 1'b0;
            inner_done_hold_q  <= 1'b0;
            inner_error_hold_q <= 1'b0;
            inner_start    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
        end else begin
            inner_start <= 1'b0;
            done        <= 1'b0;

            if (empty_msg_fire && inner_in_pop) begin
                empty_msg_pending_q <= 1'b0;
            end

            // Drain one staged CS token into the replay cache. This breaks the
            // long path from live in_token/control decode directly into
            // cs_cache*_q.
            if (cs_stage_valid_q) begin
                case (cs_stage_slot_q)
                    2'd0: cs_cache0_q <= cs_stage_token_q;
                    2'd1: cs_cache1_q <= cs_stage_token_q;
                    2'd2: cs_cache2_q <= cs_stage_token_q;
                    default: cs_cache3_q <= cs_stage_token_q;
                endcase
                cs_cache_count  <= cs_cache_count + {{CS_CACHE_AW{1'b0}}, 1'b1};
                cs_stage_valid_q <= 1'b0;
            end

            if (pass0_q && inner_in_pop && !empty_msg_fire &&
                (cs_tokens_left_q != 16'd0) &&
                (in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB] == `SDMC_TOK_CS)) begin
                cs_tokens_left_q <= cs_tokens_left_q - 16'd1;
            end

            // Cache the first-pass CS token while it is present.
            // Do not wait for inner_in_pop here: inner_in_pop is registered by
            // the inner core, so the outer testbench may already have advanced
            // in_token by the time this parent FSM observes the pop.
            // Cache first-pass CS tokens while each token is present.
            // inner_in_pop is observed one cycle late by this parent FSM, so
            // do not wait for it to capture the CS token.
            if (pass0_q && !in_empty &&
                (in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB] == `SDMC_TOK_CS) &&
                !cs_cache_hold_q && !cs_stage_valid_q) begin
                if (cs_cache_count < CS_CACHE_DEPTH[CS_CACHE_AW:0]) begin
                    cs_stage_token_q <= in_token;
                    cs_stage_slot_q  <= cs_cache_count[CS_CACHE_AW-1:0];
                    cs_stage_valid_q <= 1'b1;
                end else begin
                    cs_cache_overflow <= 1'b1;
                end
                cs_cache_hold_q <= 1'b1;
            end

            if (pass0_q && inner_in_pop) begin
                cs_cache_hold_q <= 1'b0;
            end

            if ((!pass0_q) && inner_in_pop) begin
                if (feeding_cached_cs) begin
                    cs_replay_idx <= cs_replay_idx + {{CS_CACHE_AW{1'b0}}, 1'b1};
                end else begin
                    feed_idx <= feed_idx + 3'd1;
                end
            end

            if ((!final_pass) && inner_out_push) begin
                case (capture_idx)
                    2'd0: digest0 <= inner_out_token[63:0];
                    2'd1: digest1 <= inner_out_token[63:0];
                    2'd2: digest2 <= inner_out_token[63:0];
                    2'd3: digest3 <= inner_out_token[63:0];
                    default: ;
                endcase
                capture_idx <= capture_idx + 2'd1;
            end

            case (state)
                S_IDLE: begin
                    busy  <= 1'b0;
                    error <= 1'b0;

                    if (start) begin
                        if (out_len == 16'd0) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            busy        <= 1'b1;
                            pass0_q     <= 1'b1;
                            passes_left <= (chain_count == 16'd0) ? 16'd1 : chain_count;
                            capture_idx   <= 2'd0;
                            feed_idx      <= 3'd0;
                            cs_cache_count    <= {CS_CACHE_AW+1{1'b0}};
                            cs_replay_idx      <= {CS_CACHE_AW+1{1'b0}};
                            cs_cache_hold_q    <= 1'b0;
                            cs_cache_overflow  <= 1'b0;
                            cs_stage_token_q   <= {`SDMC_TOKEN_W{1'b0}};
                            cs_stage_slot_q    <= {CS_CACHE_AW{1'b0}};
                            cs_stage_valid_q   <= 1'b0;
                            inner_done_hold_q  <= 1'b0;
                            inner_error_hold_q <= 1'b0;
                            empty_msg_pending_q <= (msg_len == 16'd0);
                            cs_tokens_left_q     <= expected_cs_tokens_w;
                            state              <= S_START_PASS;
                        end
                    end
                end

                S_START_PASS: begin
                    inner_start        <= 1'b1;
                    inner_done_hold_q  <= 1'b0;
                    inner_error_hold_q <= 1'b0;
                    state              <= S_RUN_PASS;
                end

                S_RUN_PASS: begin
                    if (inner_done && cs_stage_valid_q) begin
                        // If the inner core finishes in the same cycle that a
                        // staged CS token still needs to be committed, remember
                        // completion and transition only after the stage drains.
                        inner_done_hold_q  <= 1'b1;
                        inner_error_hold_q <= inner_error;
                    end else if ((inner_done || inner_done_hold_q) && !cs_stage_valid_q) begin
                        inner_done_hold_q <= 1'b0;
                        if (inner_error || inner_error_hold_q || cs_cache_overflow) begin
                            error <= 1'b1;
                            state <= S_ERR;
                        end else if (passes_left == 16'd1) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_NEXT_PASS;
                        end
                    end
                end

                S_NEXT_PASS: begin
                    passes_left <= passes_left - 16'd1;
                    pass0_q     <= 1'b0;
                    feed_idx        <= 3'd0;
                    capture_idx     <= 2'd0;
                    cs_replay_idx   <= {CS_CACHE_AW+1{1'b0}};
                    state           <= S_START_PASS;
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                S_ERR: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    busy  <= 1'b0;
                    error <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
