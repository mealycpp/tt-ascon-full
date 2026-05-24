/*
 * ASCON-Hash256 controller — streaming I/O, locked architecture.
 *
 * Input:  64-bit word handshake (in_word_valid / in_word_ready)
 * Output: 64-bit word handshake (out_block / out_valid)
 * Metadata: msg_total_bytes (scalar, from UART0 command frame)
 *
 * No msg_data[255:0] buffer. No result_data[255:0] buffer.
 * Words consumed on handshake as they arrive from upstream RX FIFO.
 * Blocks emitted on handshake as they are squeezed into downstream TX FIFO.
 *
 * IV (verified): x0 = 0x0000_0801_00CC_0002
 */
`default_nettype none

module hash_controller (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         reset_engine,

    // Scalar metadata
    input  wire [15:0]  msg_total_bytes,

    // Streaming input (64-bit words from upstream RX FIFO/packer)
    input  wire [63:0]  in_word,
    input  wire [3:0]   in_word_bytes,   // 1..8 valid bytes in this word
    input  wire         in_word_last,    // last word of message
    input  wire         in_word_valid,
    output reg          in_word_ready,

    // Streaming output (64-bit blocks to downstream TX FIFO)
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
    output reg  [319:0] perm_state_in,
    input  wire [319:0] perm_state_out,
    input  wire         perm_busy,
    input  wire         perm_done
);

    localparam [63:0] HASH256_IV = 64'h0000_0801_00CC_0002;
    localparam [15:0] OUT_LEN    = 16'd32;

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

    localparam S_IDLE       = 4'd0;
    localparam S_INIT_KICK  = 4'd1;
    localparam S_INIT_WAIT  = 4'd2;
    localparam S_MSG_PULL   = 4'd3;   // wait for in_word_valid
    localparam S_MSG_ABSORB = 4'd4;   // launch perm with absorbed word
    localparam S_MSG_WAIT   = 4'd5;   // wait perm done
    localparam S_SQ_EMIT    = 4'd6;
    localparam S_SQ_PERM    = 4'd7;
    localparam S_SQ_WAIT    = 4'd8;

    reg [3:0]   state;
    reg [319:0] hash_state;
    reg [15:0]  out_remaining;
    reg         last_word_seen;       // captured from in_word_last when consumed
    reg [3:0]   last_word_bytes;      // captured for pad_val
    reg [63:0]  pending_word;         // captured input word for absorb

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            out_remaining   <= 16'd0;
            last_word_seen  <= 1'b0;
            last_word_bytes <= 4'd0;
            in_word_ready   <= 1'b0;
            out_valid       <= 1'b0;
            out_last        <= 1'b0;
            out_byte_count  <= 4'd0;
            busy            <= 1'b0;
            done            <= 1'b0;
            perm_start      <= 1'b0;
            perm_rounds     <= 4'd12;
        end else if (reset_engine) begin
            state           <= S_IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            out_valid       <= 1'b0;
            out_last        <= 1'b0;
            in_word_ready   <= 1'b0;
            perm_start      <= 1'b0;
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
                        out_remaining   <= OUT_LEN;
                        last_word_seen  <= 1'b0;
                        last_word_bytes <= 4'd0;
                        busy            <= 1'b1;
                        state           <= S_INIT_KICK;
                    end
                end

                S_INIT_KICK: begin
                    perm_state_in <= {256'd0, HASH256_IV};
                    perm_rounds   <= 4'd12;
                    perm_start    <= 1'b1;
                    state         <= S_INIT_WAIT;
                end
                S_INIT_WAIT: begin
                    if (perm_done) begin
                        hash_state    <= perm_state_out;
                        // Special case: empty message — go straight to padded-empty absorb
                        if (msg_total_bytes == 16'd0) begin
                            // Absorb just the pad byte 0x01
                            perm_state_in <= {perm_state_out[319:64],
                                              perm_state_out[63:0] ^ pad_val(4'd0)};
                            state         <= S_MSG_ABSORB;
                            last_word_seen  <= 1'b1;
                            last_word_bytes <= 4'd0;
                        end else begin
                            in_word_ready <= 1'b1;
                            state         <= S_MSG_PULL;
                        end
                    end
                end

                S_MSG_PULL: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        pending_word    <= in_word;
                        last_word_seen  <= in_word_last;
                        last_word_bytes <= in_word_bytes;
                        in_word_ready   <= 1'b0;
                        // Build perm input for this word: full or partial+pad
                        if (in_word_last) begin
                            perm_state_in <= {hash_state[319:64],
                                              hash_state[63:0]
                                              ^ (in_word & mask_n(in_word_bytes))
                                              ^ pad_val(in_word_bytes)};
                        end else begin
                            perm_state_in <= {hash_state[319:64],
                                              hash_state[63:0] ^ in_word};
                        end
                        state <= S_MSG_ABSORB;
                    end
                end

                S_MSG_ABSORB: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_MSG_WAIT;
                end
                S_MSG_WAIT: begin
                    if (perm_done) begin
                        hash_state <= perm_state_out;
                        if (last_word_seen) begin
                            state <= S_SQ_EMIT;
                        end else begin
                            in_word_ready <= 1'b1;
                            state         <= S_MSG_PULL;
                        end
                    end
                end

                S_SQ_EMIT: begin
                    out_block <= hash_state[63:0];
                    out_valid <= 1'b1;
                    if (out_remaining <= 16'd8) begin
                        out_last       <= 1'b1;
                        out_byte_count <= out_remaining[3:0];
                        busy           <= 1'b0;
                        done           <= 1'b1;
                        state          <= S_IDLE;
                    end else begin
                        out_byte_count <= 4'd8;
                        out_remaining  <= out_remaining - 16'd8;
                        state          <= S_SQ_PERM;
                    end
                end

                S_SQ_PERM: begin
                    perm_state_in <= hash_state;
                    perm_rounds   <= 4'd12;
                    perm_start    <= 1'b1;
                    state         <= S_SQ_WAIT;
                end
                S_SQ_WAIT: begin
                    if (perm_done) begin
                        hash_state <= perm_state_out;
                        state      <= S_SQ_EMIT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
