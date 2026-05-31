/*
 * lane_router.v — Phase 3b: schedules which packer lane drives the
 * 64-bit SDMC input stream for the active crypto operation.
 *
 * Architecture roles (locked):
 *   protocol_parser:  dumb frame decoder, metadata + start pulse only.
 *   lane_router:      lane scheduler / byte counter / phase selector
 *                     (THIS module).
 *   mode_controller:  SDMC crypto mode controller (unchanged).
 *   crypto controllers: unchanged.
 *
 * Locked lane policy:
 *   UART0 = control frame only (parser side, not here)
 *   UART1 = key + nonce + AD / CS
 *   UART2 = message / plaintext / ciphertext / tag
 *
 * Per-mode lane sequence (driven by counter exhaustion):
 *   HASH256 / XOF128 / XOF_CHAIN:    UART2 only
 *   CXOF128 / CXOF_CHAIN:            UART1 (CS bytes), then UART2 (msg)
 *   AEAD_ENC:                        UART1 (key+nonce+AD), then UART2 (PT)
 *   AEAD_DEC:                        UART1 (key+nonce+AD), then UART2 (CT+tag)
 *
 * Safety rules (locked):
 *   1. Byte counter never decrements below zero (clamped).
 *   2. When selected lane is exhausted, valid is deasserted to mode_controller
 *      until router transitions to the next lane / state.
 *
 * Counter decrement rule:
 *   bytes_left -= sdmc_in_word_bytes  ONLY when
 *   (sdmc_in_word_valid && sdmc_in_word_ready) is asserted at clock edge.
 */
`default_nettype none

module lane_router (
    input  wire        clk,
    input  wire        rst_n,

    // From protocol_parser (latched, stable while operation runs)
    input  wire [2:0]  mode,
    input  wire        is_decrypt,
    input  wire [15:0] ad_total_bytes,
    input  wire [15:0] data_total_bytes,
    input  wire [15:0] cs_total_bits,
    input  wire        start_pulse,       // 1-cycle pulse from parser

    // From mode_controller
    input  wire        sdmc_done,         // 1-cycle pulse when crypto op completes
    input  wire        sdmc_in_word_ready,

    // From bridge (3 packed word streams)
    input  wire [63:0] pack_word_0,
    input  wire [3:0]  pack_bytes_0,
    input  wire        pack_valid_0,
    input  wire [63:0] pack_word_1,
    input  wire [3:0]  pack_bytes_1,
    input  wire        pack_valid_1,
    input  wire [63:0] pack_word_2,
    input  wire [3:0]  pack_bytes_2,
    input  wire        pack_valid_2,

    input  wire [3:0]  pack_pending_1,
    input  wire [3:0]  pack_pending_2,

    // To bridge: word mux select and final-partial-word flush
    output reg  [1:0]  phase_sel,
    output wire        flush_lane1,
    output wire        flush_lane2,

    // To mode_controller: 64-bit input stream
    output wire [63:0] sdmc_in_word,
    output wire [3:0]  sdmc_in_word_bytes,
    output wire        sdmc_in_word_valid,
    output wire        sdmc_in_word_last,

    // Status (for top integration / debug)
    output reg         router_busy
);

    // Mode codes (match protocol_parser / mode_controller localparams)
    localparam M_HASH256    = 3'd1;
    localparam M_XOF128     = 3'd2;
    localparam M_CXOF128    = 3'd3;
    localparam M_CXOF_CHAIN = 3'd4;
    localparam M_AEAD_ENC   = 3'd5;
    localparam M_AEAD_DEC   = 3'd6;
    localparam M_XOF_CHAIN  = 3'd7;

    // FSM states
    localparam S_IDLE       = 3'd0;
    localparam S_UART1      = 3'd1;  // UART1 lane: CS or key+nonce+AD
    localparam S_UART2      = 3'd2;  // UART2 lane: message / data / ct+tag
    localparam S_WAIT_DONE  = 3'd3;

    reg [2:0]  state;
    reg [16:0] bytes_left;  // 17-bit to allow for safe clamping arithmetic

    // CS byte count from bit count (round up)
    wire [15:0] cs_bytes = (cs_total_bits + 16'd7) >> 3;

    // ============================================================
    // Word mux (combinational): pick the selected lane's stream.
    // Gated by router_busy so we don't forward stale words while IDLE.
    // ============================================================
    wire lane_sel_valid = (phase_sel == 2'd1) ? pack_valid_1
                        : (phase_sel == 2'd2) ? pack_valid_2
                        : 1'b0;

    wire [63:0] lane_sel_word  = (phase_sel == 2'd1) ? pack_word_1
                               : (phase_sel == 2'd2) ? pack_word_2
                               : 64'd0;

    wire [3:0]  lane_sel_bytes = (phase_sel == 2'd1) ? pack_bytes_1
                               : (phase_sel == 2'd2) ? pack_bytes_2
                               : 4'd0;

    wire [3:0]  lane_pending = (phase_sel == 2'd1) ? pack_pending_1
                              : (phase_sel == 2'd2) ? pack_pending_2
                              : 4'd0;

    // Gate: only present a word to SDMC when we're actively in a lane
    // state (S_UART1 or S_UART2) AND bytes still expected.
    wire active = (state == S_UART1) || (state == S_UART2);
    wire any_left = (bytes_left != 17'd0);

    wire [16:0] lane_sel_bytes_ext = {13'd0, lane_sel_bytes};

    // Final partial word handling:
    // If the selected packer has accumulated exactly the remaining
    // byte count and it is less than one full 64-bit word, flush it.
    wire final_partial_pending =
        active &&
        any_left &&
        (bytes_left < 17'd8) &&
        !lane_sel_valid &&
        (lane_pending == bytes_left[3:0]);

    assign flush_lane1 = final_partial_pending && (phase_sel == 2'd1);
    assign flush_lane2 = final_partial_pending && (phase_sel == 2'd2);

    assign sdmc_in_word        = lane_sel_word;
    assign sdmc_in_word_bytes  = lane_sel_bytes;
    assign sdmc_in_word_valid  = lane_sel_valid && active && any_left;
    assign sdmc_in_word_last   = sdmc_in_word_valid &&
                                 (lane_sel_bytes_ext >= bytes_left);

    // ============================================================
    // FSM + byte counter
    // ============================================================

    // Compute next-state values when start_pulse arrives
    function [16:0] uart1_byte_count;
        input [2:0] m;
        input [15:0] ad;
        input [15:0] cs_b;
        begin
            case (m)
                M_CXOF128, M_CXOF_CHAIN:
                    uart1_byte_count = {1'b0, cs_b};
                M_AEAD_ENC, M_AEAD_DEC:
                    // 16 key + 16 nonce + ad bytes
                    uart1_byte_count = 17'd32 + {1'b0, ad};
                default:
                    uart1_byte_count = 17'd0;
            endcase
        end
    endfunction

    function [16:0] uart2_byte_count;
        input [2:0] m;
        input        is_dec;
        input [15:0] data;
        begin
            case (m)
                M_HASH256, M_XOF128, M_XOF_CHAIN,
                M_CXOF128, M_CXOF_CHAIN, M_AEAD_ENC:
                    uart2_byte_count = {1'b0, data};
                M_AEAD_DEC:
                    // data (ciphertext) + 16 bytes tag
                    uart2_byte_count = {1'b0, data} + 17'd16;
                default:
                    uart2_byte_count = 17'd0;
            endcase
        end
    endfunction

    // Does this mode have a UART1 phase?
    function has_uart1_phase;
        input [2:0] m;
        begin
            case (m)
                M_CXOF128, M_CXOF_CHAIN, M_AEAD_ENC, M_AEAD_DEC:
                    has_uart1_phase = 1'b1;
                default:
                    has_uart1_phase = 1'b0;
            endcase
        end
    endfunction

    // Latched UART2 count, used when switching from UART1 phase to UART2 phase.
    reg [16:0] uart2_count_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= S_IDLE;
            bytes_left           <= 17'd0;
            phase_sel            <= 2'd0;
            router_busy          <= 1'b0;
            uart2_count_latched  <= 17'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    router_busy <= 1'b0;
                    phase_sel   <= 2'd0;
                    bytes_left  <= 17'd0;
                    if (start_pulse) begin
                        // Latch all derived counts
                        uart2_count_latched <= uart2_byte_count(mode, is_decrypt, data_total_bytes);
                        router_busy         <= 1'b1;
                        // Select first lane
                        if (has_uart1_phase(mode)) begin
                            phase_sel  <= 2'd1;
                            bytes_left <= uart1_byte_count(mode, ad_total_bytes, cs_bytes);
                            state      <= S_UART1;
                        end else begin
                            phase_sel  <= 2'd2;
                            bytes_left <= uart2_byte_count(mode, is_decrypt, data_total_bytes);
                            state      <= S_UART2;
                        end
                    end
                end

                S_UART1: begin
                    // Decrement on successful handshake; clamp at zero.
                    if (sdmc_in_word_valid && sdmc_in_word_ready) begin
                        if ({13'd0, sdmc_in_word_bytes} >= bytes_left) begin
                            bytes_left <= 17'd0;
                        end else begin
                            bytes_left <= bytes_left - {13'd0, sdmc_in_word_bytes};
                        end
                    end
                    // Transition to UART2 when counter hits zero
                    if (bytes_left == 17'd0) begin
                        phase_sel  <= 2'd2;
                        bytes_left <= uart2_count_latched;
                        state      <= S_UART2;
                    end
                end

                S_UART2: begin
                    if (sdmc_in_word_valid && sdmc_in_word_ready) begin
                        if ({13'd0, sdmc_in_word_bytes} >= bytes_left) begin
                            bytes_left <= 17'd0;
                        end else begin
                            bytes_left <= bytes_left - {13'd0, sdmc_in_word_bytes};
                        end
                    end
                    if (bytes_left == 17'd0) begin
                        state <= S_WAIT_DONE;
                    end
                end

                S_WAIT_DONE: begin
                    if (sdmc_done) begin
                        router_busy <= 1'b0;
                        phase_sel   <= 2'd0;
                        state       <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
