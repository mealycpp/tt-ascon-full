/*
 * ASCON-CXOF128 controller — streaming I/O, locked architecture.
 *
 * Input:  64-bit word handshake, with phase bit (in_word_is_cs)
 * Output: 64-bit word handshake
 * Metadata: cs_total_bits, msg_total_bytes, out_length, chain_enable,
 *           chain_count, chain_debug
 *
 * Architecture rules:
 *   - NO cs_data[255:0] / msg_data[255:0] / result_data[255:0] anywhere
 *   - 4 x 64-bit chain_fifo for chained mode (algorithmic minimum)
 *   - Single shared permutation via external port
 *
 * Input phase protocol (per operation):
 *   1. CS phase: upstream presents CS words with in_word_is_cs=1
 *      until in_word_last
 *   2. MSG phase: upstream presents MSG words with in_word_is_cs=0
 *      until in_word_last
 *   3. Chained mode iteration 2..N: controller reads MSG from chain_fifo,
 *      does NOT pull from upstream
 *
 * IV: x0 = 0x0000_0800_00CC_0004
 */
`default_nettype none

module cxof_controller (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         reset_engine,

    // Scalar metadata
    input  wire [15:0]  cs_total_bits,    // for S_LEN_KICK length-encoding
    input  wire [15:0]  msg_total_bytes,
    input  wire [15:0]  out_length,
    input  wire         chain_enable,
    input  wire [15:0]  chain_count,
    input  wire         chain_debug,

    // Streaming input
    input  wire [63:0]  in_word,
    input  wire [3:0]   in_word_bytes,
    input  wire         in_word_last,
    input  wire         in_word_is_cs,    // 1 = CS phase, 0 = MSG phase
    input  wire         in_word_valid,
    output reg          in_word_ready,

    // Streaming output
    output reg  [63:0]  out_block,
    output reg          out_valid,
    output reg          out_last,
    output reg  [3:0]   out_byte_count,

    // Status
    output reg          busy,
    output reg          done,

    // Shared permutation interface
    output reg          perm_start,
    output reg  [3:0]   perm_rounds,
    output wire [319:0] perm_state_in,
    input  wire [319:0] perm_state_out,
    input  wire         perm_busy,
    input  wire         perm_done
);

    localparam [63:0] CXOF128_IV = 64'h0000_0800_00CC_0004;

    wire _unused = &{perm_busy, msg_total_bytes, in_word_is_cs, 1'b0};

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

    // FSM states
    localparam S_IDLE         = 5'd0;
    localparam S_INIT_KICK    = 5'd1;
    localparam S_INIT_WAIT    = 5'd2;
    localparam S_LEN_KICK     = 5'd3;
    localparam S_LEN_WAIT     = 5'd4;
    localparam S_CS_PULL      = 5'd5;
    localparam S_CS_ABSORB    = 5'd6;
    localparam S_CS_WAIT      = 5'd7;
    localparam S_MSG_PULL     = 5'd8;
    localparam S_MSG_ABSORB   = 5'd9;
    localparam S_MSG_WAIT     = 5'd10;
    localparam S_CHAIN_FETCH  = 5'd11;   // pull next word from chain_fifo internally
    localparam S_SQ_EMIT      = 5'd12;
    localparam S_SQ_PERM      = 5'd13;
    localparam S_SQ_WAIT      = 5'd14;

    reg [4:0]   state;
    reg [15:0]  out_remaining;
    reg [15:0]  passes_left;
    reg [1:0]   chain_fifo_wr_idx;
    reg [1:0]   chain_fifo_rd_idx;
    reg         is_final_iteration;
    reg         is_chained_iteration;   // 0 on first iter, 1 on subsequent
    reg         cs_last_seen;
    reg         msg_last_seen;

    reg [63:0]  chain_fifo [0:3];

    // Small selector for next permutation input. Replaces 320-bit perm_state_in FFs.
    localparam PIN_INIT     = 3'd0;
    localparam PIN_CSBITS   = 3'd1;
    localparam PIN_WORD     = 3'd2;
    localparam PIN_STATE    = 3'd3;
    localparam PIN_CHAIN    = 3'd4;

    reg [2:0]  perm_in_sel;
    reg [63:0] perm_word;
    reg [3:0]  perm_bytes;
    reg        perm_last;
    reg [1:0]  perm_chain_idx;

    wire [63:0] perm_absorb_word =
        (perm_in_sel == PIN_CHAIN) ? chain_fifo[perm_chain_idx] :
        (perm_last ? ((perm_word & mask_n(perm_bytes)) ^ pad_val(perm_bytes))
                   : perm_word);

    assign perm_state_in =
        (perm_in_sel == PIN_INIT)   ? {256'd0, CXOF128_IV} :
        (perm_in_sel == PIN_CSBITS) ? {perm_state_out[319:64],
                                       perm_state_out[63:0] ^ {48'd0, cs_total_bits}} :
        (perm_in_sel == PIN_WORD)   ? {perm_state_out[319:64],
                                       perm_state_out[63:0] ^ perm_absorb_word} :
        (perm_in_sel == PIN_CHAIN)  ? {perm_state_out[319:64],
                                       perm_state_out[63:0] ^ perm_absorb_word} :
        (perm_in_sel == PIN_STATE)  ? perm_state_out :
                                      320'd0;


    wire [15:0] requested_passes =
        (chain_enable && (chain_count != 16'd0)) ? chain_count : 16'd1;

    wire [15:0] effective_out_length =
        (out_length > 16'd32) ? 16'd32 : out_length;

    wire [15:0] chain_pass_out_length =
        chain_enable ? 16'd32 : effective_out_length;

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
            cs_last_seen         <= 1'b0;
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
                        out_remaining        <= chain_pass_out_length;
                        passes_left          <= requested_passes;
                        is_final_iteration   <= (requested_passes == 16'd1);
                        is_chained_iteration <= 1'b0;
                        chain_fifo_wr_idx    <= 2'd0;
                        chain_fifo_rd_idx    <= 2'd0;
                        cs_last_seen         <= 1'b0;
                        msg_last_seen        <= 1'b0;
                        busy                 <= 1'b1;
                        state                <= S_INIT_KICK;
                    end
                end

                S_INIT_KICK: begin
                    perm_in_sel <= PIN_INIT;
                    perm_rounds   <= 4'd12;
                    perm_start    <= 1'b1;
                    state         <= S_INIT_WAIT;
                end
                S_INIT_WAIT: begin
                    if (perm_done) begin
                        state      <= S_LEN_KICK;
                    end
                end

                S_LEN_KICK: begin
                    // XOR cs_total_bits into state[63:0] then permute
                    perm_in_sel <= PIN_CSBITS;
                    perm_rounds   <= 4'd12;
                    perm_start    <= 1'b1;
                    state         <= S_LEN_WAIT;
                end
                S_LEN_WAIT: begin
                    if (perm_done) begin
                        cs_last_seen  <= 1'b0;
                        // If CS is empty (cs_total_bits == 0), still need padded absorb
                        if (cs_total_bits == 16'd0) begin
                            // Absorb pad-only word for CS
                            perm_in_sel <= PIN_WORD;
                            perm_word   <= 64'd0;
                            perm_bytes  <= 4'd0;
                            perm_last   <= 1'b1;
                            cs_last_seen   <= 1'b1;
                            state          <= S_CS_ABSORB;
                        end else begin
                            in_word_ready <= 1'b1;
                            state         <= S_CS_PULL;
                        end
                    end
                end

                S_CS_PULL: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready && in_word_is_cs) begin
                        cs_last_seen        <= in_word_last;
                            in_word_ready       <= 1'b0;
                        if (in_word_last) begin
                            perm_in_sel <= PIN_WORD;
                            perm_word   <= in_word;
                            perm_bytes  <= in_word_bytes;
                            perm_last   <= 1'b1;
                        end else begin
                            perm_in_sel <= PIN_WORD;
                            perm_word   <= in_word;
                            perm_bytes  <= in_word_bytes;
                            perm_last   <= 1'b0;
                        end
                        state <= S_CS_ABSORB;
                    end
                end
                S_CS_ABSORB: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_CS_WAIT;
                end
                S_CS_WAIT: begin
                    if (perm_done) begin
                        if (cs_last_seen) begin
                            msg_last_seen <= 1'b0;
                            // First iteration or chained iteration?
                            if (is_chained_iteration) begin
                                // MSG comes from chain_fifo (always 32 bytes = 4 words)
                                chain_fifo_rd_idx <= 2'd0;
                                state             <= S_CHAIN_FETCH;
                            end else if (msg_total_bytes == 16'd0) begin
                                perm_in_sel <= PIN_WORD;
                                perm_word   <= 64'd0;
                                perm_bytes  <= 4'd0;
                                perm_last   <= 1'b1;
                                msg_last_seen <= 1'b1;
                                state         <= S_MSG_ABSORB;
                            end else begin
                                in_word_ready <= 1'b1;
                                state         <= S_MSG_PULL;
                            end
                        end else begin
                            in_word_ready <= 1'b1;
                            state         <= S_CS_PULL;
                        end
                    end
                end

                S_MSG_PULL: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready && !in_word_is_cs) begin
                        msg_last_seen <= in_word_last;
                        in_word_ready <= 1'b0;
                        if (in_word_last) begin
                            perm_in_sel <= PIN_WORD;
                            perm_word   <= in_word;
                            perm_bytes  <= in_word_bytes;
                            perm_last   <= 1'b1;
                        end else begin
                            perm_in_sel <= PIN_WORD;
                            perm_word   <= in_word;
                            perm_bytes  <= in_word_bytes;
                            perm_last   <= 1'b0;
                        end
                        state <= S_MSG_ABSORB;
                    end
                end

                // Chain mode: fetch next 64-bit MSG word from internal chain_fifo
                S_CHAIN_FETCH: begin
                    // chain_fifo holds 4 x 64-bit = 32 bytes, always full block
                    if (chain_fifo_rd_idx == 2'd3) begin
                        // Last word; treat as last and apply mask/pad like a full
                        // 8-byte block plus PAD. NIST CXOF treats 32-byte msg as
                        // 4 full blocks: byte_count=8 for last word means
                        // (word & mask_n(8)) ^ pad_val(8). But mask_n(8) is
                        // mask_n(0) in our table which is 0. So we need to handle
                        // the "full block then separator pad permutation" case:
                        // for a 32-byte msg (multiple of 8), we absorb 4 full
                        // blocks then do an ADDITIONAL padded-empty absorb.
                        // So: this iteration absorbs the word as a FULL block
                        // (not last), then we need one more padded-empty absorb.
                        perm_in_sel   <= PIN_CHAIN;
                        perm_chain_idx <= chain_fifo_rd_idx;
                        msg_last_seen <= 1'b0;  // we still need padded-empty absorb after
                        // Mark that next absorb should be padded-empty
                        chain_fifo_rd_idx <= 2'd0;  // sentinel: reset for next round
                        // Use a flag — overload msg_last_seen sequencing:
                        // After this absorb, go to one more padded absorb (S_MSG_FIN_PAD_KICK)
                        // To keep FSM small, set state to S_MSG_ABSORB and after wait,
                        // go to S_CHAIN_FINAL_PAD (added below).
                        state <= S_MSG_ABSORB;  // sequencing handled in S_MSG_WAIT
                    end else begin
                        perm_in_sel   <= PIN_CHAIN;
                        perm_chain_idx <= chain_fifo_rd_idx;
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
                        if (msg_last_seen) begin
                            chain_fifo_wr_idx <= 2'd0;
                            state             <= S_SQ_EMIT;
                        end else if (is_chained_iteration) begin
                            // Chain mode: fetch more words from FIFO, or do final pad-empty
                            if (chain_fifo_rd_idx == 2'd0) begin
                                // We just finished absorbing chain_fifo[3] (rd_idx reset to 0).
                                // Now do the final padded-empty absorb.
                                perm_in_sel <= PIN_WORD;
                                perm_word   <= 64'd0;
                                perm_bytes  <= 4'd0;
                                perm_last   <= 1'b1;
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
                        chain_fifo[chain_fifo_wr_idx] <= perm_state_out[63:0];
                        chain_fifo_wr_idx             <= chain_fifo_wr_idx + 2'd1;
                    end
                    if (emit_external) begin
                        out_block <= perm_state_out[63:0];
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
                        // End of pass
                        if (passes_left > 16'd1) begin
                            passes_left          <= passes_left - 16'd1;
                            is_final_iteration   <= (passes_left == 16'd2);
                            is_chained_iteration <= 1'b1;
                            out_remaining        <= 16'd32;
                            chain_fifo_wr_idx    <= 2'd0;
                            cs_last_seen         <= 1'b0;
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
                    perm_in_sel <= PIN_STATE;
                    perm_rounds   <= 4'd12;
                    perm_start    <= 1'b1;
                    state         <= S_SQ_WAIT;
                end
                S_SQ_WAIT: begin
                    if (perm_done) begin
                        state      <= S_SQ_EMIT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
