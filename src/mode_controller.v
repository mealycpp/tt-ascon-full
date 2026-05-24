/*
 * mode_controller.v — SDMC-ASCON dispatcher (streaming I/O).
 *
 * ONE shared ascon_permutation instance. All sub-controllers expose
 * streaming 64-bit input/output handshakes. No wide ports.
 *
 * Width inventory (audit):
 *   perm_state_in mux:  320 bit, combinational -> registered inside ascon_permutation
 *   in_word broadcast:   64 bit, fan-out wire (NOT a mux)
 *   in_word_valid gate:   1 bit, AND'd with active-mode select
 *   in_word_ready mux:    1 bit, combinational
 *   out_block mux:       64 bit, combinational -> goes to chip TX/FIFO downstream
 *   out_valid/last/bc mux: 1-4 bit
 *
 * Mode encoding:
 *   3'd0: IDLE
 *   3'd1: Hash256
 *   3'd2: XOF128
 *   3'd3: CXOF128 single
 *   3'd4: CXOF128 chained
 *   3'd5: AEAD-128 encrypt (reserved)
 *   3'd6: AEAD-128 decrypt (reserved)
 */
`default_nettype none

module mode_controller (
    input  wire         clk,
    input  wire         rst_n,

    // Command
    input  wire [2:0]   mode_sel,
    input  wire         start,
    input  wire         reset_engine,

    // Scalar metadata
    input  wire [15:0]  cs_total_bits,
    input  wire [15:0]  msg_total_bytes,
    input  wire [15:0]  out_length,
    input  wire         chain_enable,
    input  wire [15:0]  chain_count,
    input  wire         chain_debug,

    // Streaming input (64-bit, FIFO-friendly)
    input  wire [63:0]  in_word,
    input  wire [3:0]   in_word_bytes,
    input  wire         in_word_last,
    input  wire         in_word_is_cs,
    input  wire         in_word_valid,
    output reg          in_word_ready,

    // Streaming output (64-bit, FIFO-friendly)
    output reg  [63:0]  out_block,
    output reg          out_valid,
    output reg          out_last,
    output reg  [3:0]   out_byte_count,

    // Status
    output reg          busy,
    output reg          done
);

    localparam M_IDLE        = 3'd0;
    localparam M_HASH256     = 3'd1;
    localparam M_XOF128      = 3'd2;
    localparam M_CXOF128     = 3'd3;
    localparam M_CXOF_CHAIN  = 3'd4;
    localparam M_AEAD_ENC    = 3'd5;
    localparam M_AEAD_DEC    = 3'd6;
    localparam M_XOF_CHAIN   = 3'd7;

    reg [2:0] active_mode;

    // ---------------- Shared permutation (THE ONE) ----------------
    reg          perm_start;
    reg  [3:0]   perm_rounds;
    reg  [319:0] perm_state_in;
    wire [319:0] perm_state_out;
    wire         perm_busy;
    wire         perm_done;

    ascon_permutation u_perm (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (perm_start),
        .num_rounds (perm_rounds),
        .state_in   (perm_state_in),
        .state_out  (perm_state_out),
        .busy       (perm_busy),
        .done       (perm_done)
    );

    // ---------------- Selection ----------------
    wire sel_hash = (active_mode == M_HASH256);
    wire sel_xof  = (active_mode == M_XOF128) || (active_mode == M_XOF_CHAIN);
    wire sel_cxof = (active_mode == M_CXOF128) || (active_mode == M_CXOF_CHAIN);

    // ---------------- Start routing ----------------
    reg hash_start, xof_start, cxof_start;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_mode <= M_IDLE;
            hash_start  <= 1'b0;
            xof_start   <= 1'b0;
            cxof_start  <= 1'b0;
        end else begin
            hash_start <= 1'b0;
            xof_start  <= 1'b0;
            cxof_start <= 1'b0;
            if (start && !busy) begin
                active_mode <= mode_sel;
                case (mode_sel)
                    M_HASH256:    hash_start <= 1'b1;
                    M_XOF128,
                    M_XOF_CHAIN:  xof_start  <= 1'b1;
                    M_CXOF128,
                    M_CXOF_CHAIN: cxof_start <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    // ---------------- in_word_valid gating per sub-controller ----------------
    wire hash_in_valid = in_word_valid & sel_hash;
    wire xof_in_valid  = in_word_valid & sel_xof;
    wire cxof_in_valid = in_word_valid & sel_cxof;

    // ---------------- Sub-controllers ----------------
    // Hash256
    wire          hash_perm_start;
    wire [3:0]    hash_perm_rounds;
    wire [319:0]  hash_perm_state_in;
    wire          hash_in_ready;
    wire [63:0]   hash_out_block;
    wire          hash_out_valid;
    wire          hash_out_last;
    wire [3:0]    hash_out_byte_count;
    wire          hash_busy;
    wire          hash_done;

    hash_controller u_hash (
        .clk(clk), .rst_n(rst_n),
        .start(hash_start), .reset_engine(reset_engine),
        .msg_total_bytes(msg_total_bytes),
        .in_word(in_word), .in_word_bytes(in_word_bytes),
        .in_word_last(in_word_last), .in_word_valid(hash_in_valid),
        .in_word_ready(hash_in_ready),
        .out_block(hash_out_block), .out_valid(hash_out_valid),
        .out_last(hash_out_last), .out_byte_count(hash_out_byte_count),
        .busy(hash_busy), .done(hash_done),
        .perm_start(hash_perm_start), .perm_rounds(hash_perm_rounds),
        .perm_state_in(hash_perm_state_in),
        .perm_state_out(perm_state_out),
        .perm_busy(perm_busy),
        .perm_done(perm_done & sel_hash)
    );

    // XOF128
    wire          xof_perm_start;
    wire [3:0]    xof_perm_rounds;
    wire [319:0]  xof_perm_state_in;
    wire          xof_in_ready;
    wire [63:0]   xof_out_block;
    wire          xof_out_valid;
    wire          xof_out_last;
    wire [3:0]    xof_out_byte_count;
    wire          xof_busy;
    wire          xof_done;

    xof_controller u_xof (
        .clk(clk), .rst_n(rst_n),
        .start(xof_start), .reset_engine(reset_engine),
        .msg_total_bytes(msg_total_bytes), .out_length(out_length),
        .chain_enable(chain_enable), .chain_count(chain_count),
        .chain_debug(chain_debug),
        .in_word(in_word), .in_word_bytes(in_word_bytes),
        .in_word_last(in_word_last), .in_word_valid(xof_in_valid),
        .in_word_ready(xof_in_ready),
        .out_block(xof_out_block), .out_valid(xof_out_valid),
        .out_last(xof_out_last), .out_byte_count(xof_out_byte_count),
        .busy(xof_busy), .done(xof_done),
        .perm_start(xof_perm_start), .perm_rounds(xof_perm_rounds),
        .perm_state_in(xof_perm_state_in),
        .perm_state_out(perm_state_out),
        .perm_busy(perm_busy),
        .perm_done(perm_done & sel_xof)
    );

    // CXOF128
    wire          cxof_perm_start;
    wire [3:0]    cxof_perm_rounds;
    wire [319:0]  cxof_perm_state_in;
    wire          cxof_in_ready;
    wire [63:0]   cxof_out_block;
    wire          cxof_out_valid;
    wire          cxof_out_last;
    wire [3:0]    cxof_out_byte_count;
    wire          cxof_busy;
    wire          cxof_done;

    cxof_controller u_cxof (
        .clk(clk), .rst_n(rst_n),
        .start(cxof_start), .reset_engine(reset_engine),
        .cs_total_bits(cs_total_bits), .msg_total_bytes(msg_total_bytes),
        .out_length(out_length),
        .chain_enable(chain_enable), .chain_count(chain_count),
        .chain_debug(chain_debug),
        .in_word(in_word), .in_word_bytes(in_word_bytes),
        .in_word_last(in_word_last), .in_word_is_cs(in_word_is_cs),
        .in_word_valid(cxof_in_valid),
        .in_word_ready(cxof_in_ready),
        .out_block(cxof_out_block), .out_valid(cxof_out_valid),
        .out_last(cxof_out_last), .out_byte_count(cxof_out_byte_count),
        .busy(cxof_busy), .done(cxof_done),
        .perm_start(cxof_perm_start), .perm_rounds(cxof_perm_rounds),
        .perm_state_in(cxof_perm_state_in),
        .perm_state_out(perm_state_out),
        .perm_busy(perm_busy),
        .perm_done(perm_done & sel_cxof)
    );

    // ---------------- Perm arbiter (320b mux -> registered destination) ----------------
    always @(*) begin
        case (active_mode)
            M_HASH256: begin
                perm_start    = hash_perm_start;
                perm_rounds   = hash_perm_rounds;
                perm_state_in = hash_perm_state_in;
            end
            M_XOF128,
            M_XOF_CHAIN: begin
                perm_start    = xof_perm_start;
                perm_rounds   = xof_perm_rounds;
                perm_state_in = xof_perm_state_in;
            end
            M_CXOF128,
            M_CXOF_CHAIN: begin
                perm_start    = cxof_perm_start;
                perm_rounds   = cxof_perm_rounds;
                perm_state_in = cxof_perm_state_in;
            end
            default: begin
                perm_start    = 1'b0;
                perm_rounds   = 4'd12;
                perm_state_in = 320'd0;
            end
        endcase
    end

    // ---------------- in_word_ready mux (1 bit) ----------------
    always @(*) begin
        case (active_mode)
            M_HASH256:    in_word_ready = hash_in_ready;
            M_XOF128,
            M_XOF_CHAIN:  in_word_ready = xof_in_ready;
            M_CXOF128,
            M_CXOF_CHAIN: in_word_ready = cxof_in_ready;
            default:      in_word_ready = 1'b0;
        endcase
    end

    // ---------------- Output mux (uniform 64-bit) ----------------
    always @(*) begin
        case (active_mode)
            M_HASH256: begin
                out_block      = hash_out_block;
                out_valid      = hash_out_valid;
                out_last       = hash_out_last;
                out_byte_count = hash_out_byte_count;
                busy           = hash_busy;
                done           = hash_done;
            end
            M_XOF128,
            M_XOF_CHAIN: begin
                out_block      = xof_out_block;
                out_valid      = xof_out_valid;
                out_last       = xof_out_last;
                out_byte_count = xof_out_byte_count;
                busy           = xof_busy;
                done           = xof_done;
            end
            M_CXOF128,
            M_CXOF_CHAIN: begin
                out_block      = cxof_out_block;
                out_valid      = cxof_out_valid;
                out_last       = cxof_out_last;
                out_byte_count = cxof_out_byte_count;
                busy           = cxof_busy;
                done           = cxof_done;
            end
            default: begin
                out_block      = 64'd0;
                out_valid      = 1'b0;
                out_last       = 1'b0;
                out_byte_count = 4'd0;
                busy           = 1'b0;
                done           = 1'b0;
            end
        endcase
    end

endmodule
