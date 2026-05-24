/*
 * ASCON-XOF128 controller — streaming I/O + chain mode.
 *
 * Adds chain mode to XOF using same architecture as CXOF chain:
 *   - chain_fifo[0:3] : 4 x 64-bit internal feedback FIFO
 *   - Intermediate iterations produce 32 bytes (fed back via chain_fifo)
 *   - Final iteration produces out_length bytes (streamed externally)
 *   - chain_debug: 0 = only final streams externally, 1 = all iterations stream
 *
 * No customization phase (XOF has no CS, unlike CXOF).
 *
 * IV: x0 = 0x0000_0800_00CC_0003
 */
`default_nettype none

module xof_controller (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         reset_engine,

    input  wire [15:0]  msg_total_bytes,
    input  wire [15:0]  out_length,
    input  wire         chain_enable,
    input  wire [15:0]  chain_count,
    input  wire         chain_debug,

    input  wire [63:0]  in_word,
    input  wire [3:0]   in_word_bytes,
    input  wire         in_word_last,
    input  wire         in_word_valid,
    output reg          in_word_ready,

    output reg  [63:0]  out_block,
    output reg          out_valid,
    output reg          out_last,
    output reg  [3:0]   out_byte_count,

    output reg          busy,
    output reg          done,

    output reg          perm_start,
    output reg  [3:0]   perm_rounds,
    output reg  [319:0] perm_state_in,
    input  wire [319:0] perm_state_out,
    input  wire         perm_busy,
    input  wire         perm_done
);

    localparam [63:0] XOF128_IV = 64'h0000_0800_00CC_0003;

    wire _unused = &{perm_busy, msg_total_bytes, 1'b0};

    function [63:0] pad_val;
        input [3:0] i;
        begin
            case (i[2:0])
                3'd0: pad_val = 64'h0000_0000_0000_0001;
                3'd1: pad_val = 64'h0000_0000_0000_0100;
                3'd2: pad_val = 64'h0000_0000_0001_0000;
                3'd3: pad_val = 64'h0000_0000_0100_0000;
                3'd4: pad_val = 64'h0000_0001_0000_0000;
                3'd5: pad_val = 64'h0000_0100_0000_0000;
                3'd6: pad_val = 64'h0001_0000_0000_0000;
                3'd7: pad_val = 64'h0100_0000_0000_0000;
                default: pad_val = 64'h0;
            endcase
        end
    endfunction

    function [63:0] mask_n;
        input [3:0] n;
        begin
            case (n[2:0])
                3'd0: mask_n = 64'h0000_0000_0000_0000;
                3'd1: mask_n = 64'h0000_0000_0000_00FF;
                3'd2: mask_n = 64'h0000_0000_0000_FFFF;
                3'd3: mask_n = 64'h0000_0000_00FF_FFFF;
                3'd4: mask_n = 64'h0000_0000_FFFF_FFFF;
                3'd5: mask_n = 64'h0000_00FF_FFFF_FFFF;
                3'd6: mask_n = 64'h0000_FFFF_FFFF_FFFF;
                3'd7: mask_n = 64'h00FF_FFFF_FFFF_FFFF;
                default: mask_n = 64'h0;
            endcase
        end
    endfunction

    localparam S_IDLE         = 4'd0;
    localparam S_INIT_KICK    = 4'd1;
    localparam S_INIT_WAIT    = 4'd2;
    localparam S_MSG_PULL     = 4'd3;
    localparam S_MSG_ABSORB   = 4'd4;
    localparam S_MSG_WAIT     = 4'd5;
    localparam S_CHAIN_FETCH  = 4'd6;
    localparam S_SQ_EMIT      = 4'd7;
    localparam S_SQ_PERM      = 4'd8;
    localparam S_SQ_WAIT      = 4'd9;

    reg [3:0]   state;
    reg [319:0] xof_state;
    reg [15:0]  out_remaining;
    reg [15:0]  passes_left;
    reg [1:0]   chain_fifo_wr_idx;
    reg [1:0]   chain_fifo_rd_idx;
    reg         is_final_iteration;
    reg         is_chained_iteration;
    reg         msg_last_seen;

    reg [63:0]  chain_fifo [0:3];

    wire [15:0] requested_passes =
        (chain_enable && (chain_count != 16'd0)) ? chain_count : 16'd1;

    // Per-pass output length:
    //   intermediate chain pass: 32 bytes always (4 rate blocks for feedback)
    //   final pass:              out_length (variable, capped at 64 for safety)
    wire [15:0] effective_out_length =
        (out_length > 16'd64) ? 16'd64 : out_length;

    wire [15:0] pass_out_length =
        (chain_enable && !is_final_iteration) ? 16'd32 : effective_out_length;

    // External emit gate: chain_debug=1 emits every iteration,
    // chain_debug=0 emits only final iteration. Non-chain mode always emits.
    wire emit_external = chain_debug || (!chain_enable) || is_final_iteration;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= S_IDLE;
            out_remaining        <= 16'd0;
            passes_left          <= 16'd0;
            chain_fifo_wr_idx    <= 2'd0;
            chain_fifo_rd_idx    <= 2'd0;
            is_final_iteration   <= 1'b0;
            is_chained_iteration <= 1'b0;
            msg_last_seen        <= 1'b0;
            in_word_ready        <= 1'b0;
            out_valid            <= 1'b0;
            out_last             <= 1'b0;
            out_byte_count       <= 4'd0;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            perm_start           <= 1'b0;
            perm_rounds          <= 4'd12;
        end else if (reset_engine) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            in_word_ready <= 1'b0;
            passes_left   <= 16'd0;
            perm_start    <= 1'b0;
        end else begin
            perm_start    <= 1'b0;
            done          <= 1'b0;
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            in_word_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        out_remaining        <= pass_out_length;
                        passes_left          <= requested_passes;
                        is_final_iteration   <= (requested_passes == 16'd1);
                        is_chained_iteration <= 1'b0;
                        chain_fifo_wr_idx    <= 2'd0;
                        chain_fifo_rd_idx    <= 2'd0;
                        msg_last_seen        <= 1'b0;
                        busy                 <= 1'b1;
                        state                <= S_INIT_KICK;
                    end
                end

                S_INIT_KICK: begin
                    perm_state_in <= {256'd0, XOF128_IV};
                    perm_rounds   <= 4'd12;
                    perm_start    <= 1'b1;
                    state         <= S_INIT_WAIT;
                end
                S_INIT_WAIT: begin
                    if (perm_done) begin
                        xof_state <= perm_state_out;
                        if (is_chained_iteration) begin
                            // Chain mode: pull MSG from chain_fifo
                            chain_fifo_rd_idx <= 2'd0;
                            msg_last_seen     <= 1'b0;
                            state             <= S_CHAIN_FETCH;
                        end else if (msg_total_bytes == 16'd0) begin
                            // Empty message: pad-only absorb
                            perm_state_in <= {perm_state_out[319:64],
                                              perm_state_out[63:0] ^ pad_val(4'd0)};
                            msg_last_seen <= 1'b1;
                            state         <= S_MSG_ABSORB;
                        end else begin
                            in_word_ready <= 1'b1;
                            state         <= S_MSG_PULL;
                        end
                    end
                end

                S_MSG_PULL: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        msg_last_seen <= in_word_last;
                        in_word_ready <= 1'b0;
                        if (in_word_last) begin
                            perm_state_in <= {xof_state[319:64],
                                              xof_state[63:0]
                                              ^ (in_word & mask_n(in_word_bytes))
                                              ^ pad_val(in_word_bytes)};
                        end else begin
                            perm_state_in <= {xof_state[319:64],
                                              xof_state[63:0] ^ in_word};
                        end
                        state <= S_MSG_ABSORB;
                    end
                end

                // Chain mode: fetch next 64-bit MSG word from chain_fifo
                S_CHAIN_FETCH: begin
                    if (chain_fifo_rd_idx == 2'd3) begin
                        // Absorb chain_fifo[3] as a full block; next state
                        // will be padded-empty absorb (same as CXOF chain).
                        perm_state_in <= {xof_state[319:64],
                                          xof_state[63:0] ^ chain_fifo[chain_fifo_rd_idx]};
                        msg_last_seen     <= 1'b0;
                        chain_fifo_rd_idx <= 2'd0;  // sentinel for "do padded-empty next"
                        state             <= S_MSG_ABSORB;
                    end else begin
                        perm_state_in <= {xof_state[319:64],
                                          xof_state[63:0] ^ chain_fifo[chain_fifo_rd_idx]};
                        chain_fifo_rd_idx <= chain_fifo_rd_idx + 2'd1;
                        msg_last_seen     <= 1'b0;
                        state             <= S_MSG_ABSORB;
                    end
                end

                S_MSG_ABSORB: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_MSG_WAIT;
                end
                S_MSG_WAIT: begin
                    if (perm_done) begin
                        xof_state <= perm_state_out;
                        if (msg_last_seen) begin
                            chain_fifo_wr_idx <= 2'd0;
                            state             <= S_SQ_EMIT;
                        end else if (is_chained_iteration) begin
                            if (chain_fifo_rd_idx == 2'd0) begin
                                // Finished absorbing chain_fifo[3]; do final padded-empty
                                perm_state_in <= {perm_state_out[319:64],
                                                  perm_state_out[63:0] ^ pad_val(4'd0)};
                                msg_last_seen <= 1'b1;
                                state         <= S_MSG_ABSORB;
                            end else begin
                                state <= S_CHAIN_FETCH;
                            end
                        end else begin
                            in_word_ready <= 1'b1;
                            state         <= S_MSG_PULL;
                        end
                    end
                end

                S_SQ_EMIT: begin
                    if (chain_enable) begin
                        chain_fifo[chain_fifo_wr_idx] <= xof_state[63:0];
                        chain_fifo_wr_idx             <= chain_fifo_wr_idx + 2'd1;
                    end
                    if (emit_external) begin
                        out_block <= xof_state[63:0];
                        out_valid <= 1'b1;
                        if (out_remaining <= 16'd8) begin
                            out_last       <= 1'b1;
                            out_byte_count <= out_remaining[3:0];
                        end else begin
                            out_byte_count <= 4'd8;
                        end
                    end
                    if (out_remaining > 16'd8) begin
                        out_remaining <= out_remaining - 16'd8;
                        state         <= S_SQ_PERM;
                    end else begin
                        if (passes_left > 16'd1) begin
                            passes_left          <= passes_left - 16'd1;
                            is_final_iteration   <= (passes_left == 16'd2);
                            is_chained_iteration <= 1'b1;
                            // Next pass: 32 bytes if intermediate, out_length if final
                            out_remaining        <= (passes_left == 16'd2)
                                                    ? effective_out_length
                                                    : 16'd32;
                            chain_fifo_wr_idx    <= 2'd0;
                            msg_last_seen        <= 1'b0;
                            state                <= S_INIT_KICK;
                        end else begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end
                    end
                end

                S_SQ_PERM: begin
                    perm_state_in <= xof_state;
                    perm_rounds   <= 4'd12;
                    perm_start    <= 1'b1;
                    state         <= S_SQ_WAIT;
                end
                S_SQ_WAIT: begin
                    if (perm_done) begin
                        xof_state <= perm_state_out;
                        state     <= S_SQ_EMIT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
