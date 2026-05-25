/*
 * ascon_sponge_core.v -- stateful ASCON sponge/permutation core.
 *
 * Architectural rule:
 *   - The 320-bit ASCON state is owned only inside this module.
 *   - External controllers never drive a 320-bit state input.
 *   - Controllers modify the state using 64-bit lane patches.
 *
 * State lane convention:
 *   x0 = state[63:0]      rate lane for HASH/XOF/CXOF
 *   x1 = state[127:64]    second rate lane for AEAD
 *   x2 = state[191:128]
 *   x3 = state[255:192]
 *   x4 = state[319:256]
 *
 * Patch interface:
 *   patch_op:
 *     2'd0 = LOAD lane with patch_data
 *     2'd1 = XOR  lane with patch_data
 *     2'd2 = CLEAR whole state
 *
 * Permutation interface:
 *   perm_start pulses for one cycle when the desired patches are already applied.
 *   perm_rounds is usually 12 or 8.
 */

`default_nettype none

module ascon_sponge_core (
    input  wire        clk,
    input  wire        rst_n,

    // 64-bit lane patch interface
    input  wire        patch_valid,
    output wire        patch_ready,
    input  wire [1:0]  patch_op,
    input  wire [2:0]  patch_lane,
    input  wire [63:0] patch_data,

    // permutation control
    input  wire        perm_start,
    input  wire [3:0]  perm_rounds,
    output reg         perm_busy,
    output reg         perm_done,

    // lane readback
    output wire [63:0] x0,
    output wire [63:0] x1,
    output wire [63:0] x2,
    output wire [63:0] x3,
    output wire [63:0] x4
);

    localparam PATCH_LOAD  = 2'd0;
    localparam PATCH_XOR   = 2'd1;
    localparam PATCH_CLEAR = 2'd2;

    localparam LANE_X0 = 3'd0;
    localparam LANE_X1 = 3'd1;
    localparam LANE_X2 = 3'd2;
    localparam LANE_X3 = 3'd3;
    localparam LANE_X4 = 3'd4;

    // Permutation FSM
    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0] state;
    reg [3:0] round_idx;

    reg [319:0] state_reg;
    wire [319:0] state_next;

    assign x0 = state_reg[63:0];
    assign x1 = state_reg[127:64];
    assign x2 = state_reg[191:128];
    assign x3 = state_reg[255:192];
    assign x4 = state_reg[319:256];

    assign patch_ready = (state == S_IDLE);

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

    ascon_round u_round (
        .state_in    (state_reg),
        .round_const (round_constant(round_idx)),
        .state_out   (state_next)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            state_reg  <= 320'd0;
            round_idx  <= 4'd0;
            perm_busy  <= 1'b0;
            perm_done  <= 1'b0;
        end else begin
            perm_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    perm_busy <= 1'b0;

                    if (patch_valid && patch_ready) begin
                        case (patch_op)
                            PATCH_CLEAR: begin
                                state_reg <= 320'd0;
                            end

                            PATCH_LOAD: begin
                                case (patch_lane)
                                    LANE_X0: state_reg[63:0]    <= patch_data;
                                    LANE_X1: state_reg[127:64]  <= patch_data;
                                    LANE_X2: state_reg[191:128] <= patch_data;
                                    LANE_X3: state_reg[255:192] <= patch_data;
                                    LANE_X4: state_reg[319:256] <= patch_data;
                                    default: state_reg          <= state_reg;
                                endcase
                            end

                            PATCH_XOR: begin
                                case (patch_lane)
                                    LANE_X0: state_reg[63:0]    <= state_reg[63:0]    ^ patch_data;
                                    LANE_X1: state_reg[127:64]  <= state_reg[127:64]  ^ patch_data;
                                    LANE_X2: state_reg[191:128] <= state_reg[191:128] ^ patch_data;
                                    LANE_X3: state_reg[255:192] <= state_reg[255:192] ^ patch_data;
                                    LANE_X4: state_reg[319:256] <= state_reg[319:256] ^ patch_data;
                                    default: state_reg          <= state_reg;
                                endcase
                            end

                            default: begin
                                state_reg <= state_reg;
                            end
                        endcase
                    end else if (perm_start) begin
                        round_idx <= 4'd12 - perm_rounds;
                        perm_busy <= 1'b1;
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
                    perm_done <= 1'b1;
                    perm_busy <= 1'b0;
                    state     <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
