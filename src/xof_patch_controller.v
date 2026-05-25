/*
 * xof_patch_controller.v -- ASCON-XOF128 controller for patch-fed sponge core.
 *
 * Rule:
 *   - This controller never builds a 320-bit permutation input.
 *   - It only sends 64-bit patches to x0 and starts permutations.
 *   - Supports XOF chain mode using the existing 4x64 feedback FIFO behavior.
 */

`default_nettype none

module xof_patch_controller (
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

    output reg          patch_valid,
    input  wire         patch_ready,
    output reg  [1:0]   patch_op,
    output reg  [2:0]   patch_lane,
    output reg  [63:0]  patch_data,

    output reg          perm_start,
    output reg  [3:0]   perm_rounds,
    input  wire         perm_busy,
    input  wire         perm_done,

    input  wire [63:0]  core_x0
);

    localparam [63:0] XOF128_IV = 64'h0000_0800_00CC_0003;

    localparam PATCH_LOAD  = 2'd0;
    localparam PATCH_XOR   = 2'd1;
    localparam PATCH_CLEAR = 2'd2;

    localparam LANE_X0 = 3'd0;

    localparam S_IDLE        = 4'd0;
    localparam S_CLEAR       = 4'd1;
    localparam S_LOAD_IV     = 4'd2;
    localparam S_INIT_KICK   = 4'd3;
    localparam S_INIT_WAIT   = 4'd4;
    localparam S_MSG_PULL    = 4'd5;
    localparam S_CHAIN_FETCH = 4'd6;
    localparam S_WORD_PREP   = 4'd7;
    localparam S_MSG_PATCH   = 4'd8;
    localparam S_MSG_PERM    = 4'd9;
    localparam S_MSG_WAIT    = 4'd10;
    localparam S_SQ_EMIT     = 4'd11;
    localparam S_SQ_PERM     = 4'd12;
    localparam S_SQ_WAIT     = 4'd13;

    reg [3:0]   state;
    reg [15:0]  out_remaining;
    reg [15:0]  passes_left;
    reg [1:0]   chain_fifo_wr_idx;
    reg [1:0]   chain_fifo_rd_idx;
    reg         is_final_iteration;
    reg         is_chained_iteration;
    reg         msg_last_seen;

    reg [63:0]  chain_fifo [0:3];

    reg [63:0]  perm_word;
    reg [3:0]   perm_bytes;
    reg         perm_last;
    reg         perm_is_chain;
    reg [1:0]   perm_chain_idx;
    reg [63:0]  absorb_word_r;

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

    wire [15:0] requested_passes =
        (chain_enable && (chain_count != 16'd0)) ? chain_count : 16'd1;

    wire [15:0] effective_out_length =
        (out_length > 16'd64) ? 16'd64 : out_length;

    wire emit_external =
        chain_debug || (!chain_enable) || is_final_iteration;

    wire [63:0] prepared_absorb_word =
        perm_is_chain ? chain_fifo[perm_chain_idx] :
        (perm_last ? ((perm_word & mask_n(perm_bytes)) ^ pad_val(perm_bytes))
                   : perm_word);

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
            out_block            <= 64'd0;
            out_valid            <= 1'b0;
            out_last             <= 1'b0;
            out_byte_count       <= 4'd0;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            patch_valid          <= 1'b0;
            patch_op             <= PATCH_CLEAR;
            patch_lane           <= LANE_X0;
            patch_data           <= 64'd0;
            perm_start           <= 1'b0;
            perm_rounds          <= 4'd12;
            perm_word            <= 64'd0;
            perm_bytes           <= 4'd0;
            perm_last            <= 1'b0;
            perm_is_chain        <= 1'b0;
            perm_chain_idx       <= 2'd0;
            absorb_word_r        <= 64'd0;
        end else if (reset_engine) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            in_word_ready <= 1'b0;
            passes_left   <= 16'd0;
            patch_valid   <= 1'b0;
            perm_start    <= 1'b0;
        end else begin
            patch_valid   <= 1'b0;
            perm_start    <= 1'b0;
            done          <= 1'b0;
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            in_word_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        passes_left          <= requested_passes;
                        is_final_iteration   <= (requested_passes == 16'd1);
                        is_chained_iteration <= 1'b0;
                        out_remaining        <= (chain_enable && (requested_passes != 16'd1))
                                                ? 16'd32
                                                : effective_out_length;
                        chain_fifo_wr_idx    <= 2'd0;
                        chain_fifo_rd_idx    <= 2'd0;
                        msg_last_seen        <= 1'b0;
                        busy                 <= 1'b1;
                        state                <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_CLEAR;
                        patch_lane  <= LANE_X0;
                        patch_data  <= 64'd0;
                        state       <= S_LOAD_IV;
                    end
                end

                S_LOAD_IV: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_LOAD;
                        patch_lane  <= LANE_X0;
                        patch_data  <= XOF128_IV;
                        state       <= S_INIT_KICK;
                    end
                end

                S_INIT_KICK: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_INIT_WAIT;
                end

                S_INIT_WAIT: begin
                    if (perm_done) begin
                        if (is_chained_iteration) begin
                            chain_fifo_rd_idx <= 2'd0;
                            msg_last_seen     <= 1'b0;
                            state             <= S_CHAIN_FETCH;
                        end else if (msg_total_bytes == 16'd0) begin
                            absorb_word_r  <= pad_val(4'd0);
                            msg_last_seen  <= 1'b1;
                            perm_is_chain  <= 1'b0;
                            state          <= S_MSG_PATCH;
                        end else begin
                            state <= S_MSG_PULL;
                        end
                    end
                end

                S_MSG_PULL: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        msg_last_seen <= in_word_last;
                        in_word_ready <= 1'b0;
                        perm_word     <= in_word;
                        perm_bytes    <= in_word_bytes;
                        perm_last     <= in_word_last;
                        perm_is_chain <= 1'b0;
                        state         <= S_WORD_PREP;
                    end
                end

                S_CHAIN_FETCH: begin
                    perm_is_chain <= 1'b1;
                    perm_chain_idx <= chain_fifo_rd_idx;
                    msg_last_seen <= 1'b0;

                    if (chain_fifo_rd_idx == 2'd3) begin
                        chain_fifo_rd_idx <= 2'd0;
                    end else begin
                        chain_fifo_rd_idx <= chain_fifo_rd_idx + 2'd1;
                    end

                    state <= S_WORD_PREP;
                end

                S_WORD_PREP: begin
                    absorb_word_r <= prepared_absorb_word;
                    state         <= S_MSG_PATCH;
                end

                S_MSG_PATCH: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X0;
                        patch_data  <= absorb_word_r;
                        state       <= S_MSG_PERM;
                    end
                end

                S_MSG_PERM: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_MSG_WAIT;
                end

                S_MSG_WAIT: begin
                    if (perm_done) begin
                        if (msg_last_seen) begin
                            chain_fifo_wr_idx <= 2'd0;
                            state             <= S_SQ_EMIT;
                        end else if (is_chained_iteration) begin
                            if (chain_fifo_rd_idx == 2'd0) begin
                                absorb_word_r <= pad_val(4'd0);
                                msg_last_seen <= 1'b1;
                                perm_is_chain <= 1'b0;
                                state         <= S_MSG_PATCH;
                            end else begin
                                state <= S_CHAIN_FETCH;
                            end
                        end else begin
                            state <= S_MSG_PULL;
                        end
                    end
                end

                S_SQ_EMIT: begin
                    if (chain_enable) begin
                        chain_fifo[chain_fifo_wr_idx] <= core_x0;
                        chain_fifo_wr_idx             <= chain_fifo_wr_idx + 2'd1;
                    end

                    if (emit_external) begin
                        out_block <= core_x0;
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
                            out_remaining        <= (passes_left == 16'd2)
                                                    ? effective_out_length
                                                    : 16'd32;
                            chain_fifo_wr_idx    <= 2'd0;
                            msg_last_seen        <= 1'b0;
                            state                <= S_CLEAR;
                        end else begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end
                    end
                end

                S_SQ_PERM: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_SQ_WAIT;
                end

                S_SQ_WAIT: begin
                    if (perm_done) begin
                        state <= S_SQ_EMIT;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
