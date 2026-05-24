/*
 * hash_controller.v -- ASCON-Hash256 streaming controller.
 *
 * Area surgery:
 *   - No private 320-bit hash_state register.
 *   - No registered 320-bit perm_state_in.
 *   - The shared ascon_permutation state_reg is the working state.
 *   - This controller is only a small sequencer plus one 64-bit word latch.
 */
`default_nettype none

module hash_controller (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    input  wire         reset_engine,

    input  wire [15:0]  msg_total_bytes,

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
    output wire [319:0] perm_state_in,
    input  wire [319:0] perm_state_out,
    input  wire         perm_busy,
    input  wire         perm_done
);

    localparam S_IDLE        = 4'd0;
    localparam S_INIT_KICK   = 4'd1;
    localparam S_INIT_WAIT   = 4'd2;
    localparam S_MSG_PULL    = 4'd3;
    localparam S_ABSORB_KICK = 4'd4;
    localparam S_ABSORB_WAIT = 4'd5;
    localparam S_SQ_OUT      = 4'd6;
    localparam S_SQ_KICK     = 4'd7;
    localparam S_SQ_WAIT     = 4'd8;
    localparam S_DONE        = 4'd9;

    localparam [63:0] HASH256_IV = 64'h0000_0801_00CC_0002;

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

    localparam PIN_INIT  = 2'd0;
    localparam PIN_WORD  = 2'd1;
    localparam PIN_STATE = 2'd2;

    reg [3:0]  state;
    reg [15:0] out_remaining;
    reg        last_word_seen;

    reg [1:0]  perm_in_sel;
    reg [63:0] perm_word;
    reg [3:0]  perm_bytes;
    reg        perm_last;

    wire [63:0] absorb_word =
        perm_last ? ((perm_word & mask_n(perm_bytes)) ^ pad_val(perm_bytes))
                  : perm_word;

    assign perm_state_in =
        (perm_in_sel == PIN_INIT)  ? {256'd0, HASH256_IV} :
        (perm_in_sel == PIN_WORD)  ? {perm_state_out[319:64],
                                      perm_state_out[63:0] ^ absorb_word} :
        (perm_in_sel == PIN_STATE) ? perm_state_out :
                                     320'd0;

    wire _unused = &{perm_busy, 1'b0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            out_remaining  <= 16'd0;
            last_word_seen <= 1'b0;
            in_word_ready  <= 1'b0;
            out_valid      <= 1'b0;
            out_last       <= 1'b0;
            out_byte_count <= 4'd0;
            busy           <= 1'b0;
            done           <= 1'b0;
            perm_start     <= 1'b0;
            perm_rounds    <= 4'd12;
            perm_in_sel    <= PIN_INIT;
            perm_word      <= 64'd0;
            perm_bytes     <= 4'd0;
            perm_last      <= 1'b0;
        end else if (reset_engine) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            out_valid      <= 1'b0;
            out_last       <= 1'b0;
            in_word_ready  <= 1'b0;
            perm_start     <= 1'b0;
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
                        busy           <= 1'b1;
                        out_remaining  <= 16'd32;
                        last_word_seen <= 1'b0;
                        state          <= S_INIT_KICK;
                    end
                end

                S_INIT_KICK: begin
                    perm_in_sel <= PIN_INIT;
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_INIT_WAIT;
                end

                S_INIT_WAIT: begin
                    if (perm_done) begin
                        if (msg_total_bytes == 16'd0) begin
                            perm_in_sel    <= PIN_WORD;
                            perm_word      <= 64'd0;
                            perm_bytes     <= 4'd0;
                            perm_last      <= 1'b1;
                            last_word_seen <= 1'b1;
                            state          <= S_ABSORB_KICK;
                        end else begin
                            state <= S_MSG_PULL;
                        end
                    end
                end

                S_MSG_PULL: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        in_word_ready  <= 1'b0;
                        perm_in_sel    <= PIN_WORD;
                        perm_word      <= in_word;
                        perm_bytes     <= in_word_bytes;
                        perm_last      <= in_word_last;
                        last_word_seen <= in_word_last;
                        state          <= S_ABSORB_KICK;
                    end
                end

                S_ABSORB_KICK: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_ABSORB_WAIT;
                end

                S_ABSORB_WAIT: begin
                    if (perm_done) begin
                        if (last_word_seen) begin
                            state <= S_SQ_OUT;
                        end else begin
                            state <= S_MSG_PULL;
                        end
                    end
                end

                S_SQ_OUT: begin
                    out_block <= perm_state_out[63:0];
                    out_valid <= 1'b1;

                    if (out_remaining > 16'd8) begin
                        out_byte_count <= 4'd8;
                        out_last       <= 1'b0;
                        out_remaining  <= out_remaining - 16'd8;
                        state          <= S_SQ_KICK;
                    end else begin
                        out_byte_count <= out_remaining[3:0];
                        out_last       <= 1'b1;
                        out_remaining  <= 16'd0;
                        state          <= S_DONE;
                    end
                end

                S_SQ_KICK: begin
                    perm_in_sel <= PIN_STATE;
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_SQ_WAIT;
                end

                S_SQ_WAIT: begin
                    if (perm_done) begin
                        state <= S_SQ_OUT;
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
