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
 *
 * This version assumes ascon_round is a sequential multi-cycle round block:
 *   start pulses for one cycle.
 *   busy is high while the round executes.
 *   done pulses for one cycle when state_out is valid.
 */

`default_nettype none

module ascon_permutation (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    input  wire [3:0]   num_rounds,
    input  wire [319:0] state_in,

    output wire [319:0] state_out,
    output wire         busy,
    output wire         done
);

    reg [319:0] state_out_r;
    reg         busy_r;
    reg         done_r;

    assign state_out = state_out_r;
    assign busy      = busy_r;
    assign done      = done_r;

    function [7:0] round_constant;
        input [3:0] r;
        begin
            // ASCON round constants:
            // r=0..11 => f0,e1,d2,c3,b4,a5,96,87,78,69,5a,4b
            round_constant = {4'hf - r, r};
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

    reg         round_start;
    wire [319:0] round_state_out;
    wire        round_busy;
    wire        round_done;

    ascon_round u_round (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (round_start),
        .state_in    (state_reg),
        .round_const (round_constant(round_idx)),
        .state_out   (round_state_out),
        .busy        (round_busy),
        .done        (round_done)
    );

    wire _unused = &{round_busy, 1'b0};

    localparam S_IDLE       = 3'd0;
    localparam S_START_ROUND = 3'd1;
    localparam S_WAIT_ROUND  = 3'd2;
    localparam S_DONE       = 3'd3;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            state_reg   <= 320'd0;
            state_out_r <= 320'd0;
            round_idx   <= 4'd0;
            round_start <= 1'b0;
            busy_r      <= 1'b0;
            done_r      <= 1'b0;
        end else begin
            done_r      <= 1'b0;
            round_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_r <= 1'b0;

                    if (start) begin
                        state_reg <= state_in;
                        round_idx <= round_start_index(num_rounds);
                        busy_r    <= 1'b1;
                        state     <= S_START_ROUND;
                    end
                end

                S_START_ROUND: begin
                    round_start <= 1'b1;
                    state       <= S_WAIT_ROUND;
                end

                S_WAIT_ROUND: begin
                    if (round_done) begin
                        state_reg <= round_state_out;

                        if (round_idx == 4'd11) begin
                            state <= S_DONE;
                        end else begin
                            round_idx <= round_idx + 4'd1;
                            state     <= S_START_ROUND;
                        end
                    end
                end

                S_DONE: begin
                    state_out_r <= state_reg;
                    done_r      <= 1'b1;
                    busy_r      <= 1'b0;
                    state       <= S_IDLE;
                end

                default: begin
                    state       <= S_IDLE;
                    state_reg   <= 320'd0;
                    round_idx   <= 4'd0;
                    round_start <= 1'b0;
                    busy_r      <= 1'b0;
                    done_r      <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
