/*
 * ASCON permutation engine.
 *
 * Implements ASCON-p[r] using the correct round-constant window:
 *   p12: f0 e1 d2 c3 b4 a5 96 87 78 69 5a 4b
 *   p8:              b4 a5 96 87 78 69 5a 4b
 *
 * External interface stays simple:
 *   start pulses for one cycle.
 *   busy is high while rounds execute.
 *   done pulses for one cycle when state_out is valid.
 */

`default_nettype none

module ascon_permutation (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    input  wire [3:0]   num_rounds,
    input  wire [319:0] state_in,

    output reg  [319:0] state_out,
    output reg          busy,
    output reg          done
);

    function [7:0] round_constant;
        input [3:0] r;
        begin
            case (r)
                4'd0:  round_constant = 8'hf0;
                4'd1:  round_constant = 8'he1;
                4'd2:  round_constant = 8'hd2;
                4'd3:  round_constant = 8'hc3;
                4'd4:  round_constant = 8'hb4;
                4'd5:  round_constant = 8'ha5;
                4'd6:  round_constant = 8'h96;
                4'd7:  round_constant = 8'h87;
                4'd8:  round_constant = 8'h78;
                4'd9:  round_constant = 8'h69;
                4'd10: round_constant = 8'h5a;
                4'd11: round_constant = 8'h4b;
                default: round_constant = 8'h00;
            endcase
        end
    endfunction

    function [3:0] round_start_index;
        input [3:0] r;
        begin
            if (r == 4'd0) begin
                round_start_index = 4'd0;       // invalid 0 -> p12
            end else if (r >= 4'd12) begin
                round_start_index = 4'd0;       // clamp >=12 -> p12
            end else begin
                round_start_index = 4'd12 - r;  // p8 starts at 4
            end
        end
    endfunction

    reg [319:0] state_reg;
    reg [3:0]   round_idx;

    wire [319:0] state_next;

    ascon_round u_round (
        .state_in    (state_reg),
        .round_const (round_constant(round_idx)),
        .state_out   (state_next)
    );

    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            state_reg <= 320'd0;
            state_out <= 320'd0;
            round_idx <= 4'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        state_reg <= state_in;
                        round_idx <= round_start_index(num_rounds);
                        busy      <= 1'b1;
                        state     <= S_RUN;
                    end
                end

                S_RUN: begin
                    state_reg <= state_next;

                    if (round_idx == 4'd11) begin
                        state <= S_DONE;
                    end else begin
                        round_idx <= round_idx + 4'd1;
                    end
                end

                S_DONE: begin
                    state_out <= state_reg;
                    done      <= 1'b1;
                    busy      <= 1'b0;
                    state     <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
