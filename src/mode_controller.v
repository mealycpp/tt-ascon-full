/*
 * mode_controller.v — SDMC-ASCON dispatcher (streaming I/O).
 *
 * Area/fanout surgery version:
 * - ONE shared ascon_permutation instance.
 * - Decode mode once at operation start.
 * - Use registered one-hot selects for controller routing.
 * - Avoid repeated active_mode equality decoders in every mux.
 * - No wide message/result buffers.
 *
 * Timing surgery:
 * - Register the shared permutation input mux.
 * - Breaks the long path:
 *      sel_*_r -> 320-bit perm_state mux -> ASCON permutation input/state logic.
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

    // AEAD-specific scalar metadata
    input  wire         is_decrypt,
    input  wire [15:0]  ad_total_bytes,
    input  wire [15:0]  data_total_bytes,

    // Streaming input
    input  wire [63:0]  in_word,
    input  wire [3:0]   in_word_bytes,
    input  wire         in_word_last,
    input  wire         in_word_is_cs,
    input  wire         in_word_valid,
    output reg          in_word_ready,

    // Streaming output
    output reg  [63:0]  out_block,
    output reg          out_valid,
    output reg          out_last,
    output reg  [3:0]   out_byte_count,

    // AEAD auth result
    output reg          auth_ok,

    // Status
    output reg          busy,
    output reg          done
);

    localparam M_HASH256    = 3'd1;
    localparam M_XOF128     = 3'd2;
    localparam M_CXOF128    = 3'd3;
    localparam M_CXOF_CHAIN = 3'd4;
    localparam M_AEAD_ENC   = 3'd5;
    localparam M_AEAD_DEC   = 3'd6;
    localparam M_XOF_CHAIN  = 3'd7;

    // Registered one-hot controller selects.
    reg sel_hash_r;
    reg sel_xof_r;
    reg sel_cxof_r;
    reg sel_aead_r;

    // -------------------------------------------------------------------------
    // Shared permutation: THE ONLY physical ASCON datapath
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Start routing and one-hot decode
    // -------------------------------------------------------------------------
    reg hash_start;
    reg xof_start;
    reg cxof_start;
    reg aead_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel_hash_r <= 1'b0;
            sel_xof_r  <= 1'b0;
            sel_cxof_r <= 1'b0;
            sel_aead_r <= 1'b0;

            hash_start <= 1'b0;
            xof_start  <= 1'b0;
            cxof_start <= 1'b0;
            aead_start <= 1'b0;
        end else begin
            hash_start <= 1'b0;
            xof_start  <= 1'b0;
            cxof_start <= 1'b0;
            aead_start <= 1'b0;

            if (reset_engine) begin
                sel_hash_r <= 1'b0;
                sel_xof_r  <= 1'b0;
                sel_cxof_r <= 1'b0;
                sel_aead_r <= 1'b0;
            end else if (start && !busy) begin
                sel_hash_r <= (mode_sel == M_HASH256);
                sel_xof_r  <= (mode_sel == M_XOF128) || (mode_sel == M_XOF_CHAIN);
                sel_cxof_r <= (mode_sel == M_CXOF128) || (mode_sel == M_CXOF_CHAIN);
                sel_aead_r <= (mode_sel == M_AEAD_ENC) || (mode_sel == M_AEAD_DEC);

                case (mode_sel)
                    M_HASH256: begin
                        hash_start <= 1'b1;
                    end

                    M_XOF128,
                    M_XOF_CHAIN: begin
                        xof_start <= 1'b1;
                    end

                    M_CXOF128,
                    M_CXOF_CHAIN: begin
                        cxof_start <= 1'b1;
                    end

                    M_AEAD_ENC,
                    M_AEAD_DEC: begin
                        aead_start <= 1'b1;
                    end

                    default: begin
                        sel_hash_r <= 1'b0;
                        sel_xof_r  <= 1'b0;
                        sel_cxof_r <= 1'b0;
                        sel_aead_r <= 1'b0;
                    end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // in_word_valid gating
    // -------------------------------------------------------------------------
    wire hash_in_valid = in_word_valid & sel_hash_r;
    wire xof_in_valid  = in_word_valid & sel_xof_r;
    wire cxof_in_valid = in_word_valid & sel_cxof_r;
    wire aead_in_valid = in_word_valid & sel_aead_r;

    // -------------------------------------------------------------------------
    // Hash256 controller
    // -------------------------------------------------------------------------
    wire         hash_perm_start;
    wire [3:0]   hash_perm_rounds;
    wire [319:0] hash_perm_state_in;

    wire         hash_in_ready;
    wire [63:0]  hash_out_block;
    wire         hash_out_valid;
    wire         hash_out_last;
    wire [3:0]   hash_out_byte_count;
    wire         hash_busy;
    wire         hash_done;

    hash_controller u_hash (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (hash_start),
        .reset_engine   (reset_engine),

        .msg_total_bytes(msg_total_bytes),

        .in_word        (in_word),
        .in_word_bytes  (in_word_bytes),
        .in_word_last   (in_word_last),
        .in_word_valid  (hash_in_valid),
        .in_word_ready  (hash_in_ready),

        .out_block      (hash_out_block),
        .out_valid      (hash_out_valid),
        .out_last       (hash_out_last),
        .out_byte_count (hash_out_byte_count),

        .busy           (hash_busy),
        .done           (hash_done),

        .perm_start     (hash_perm_start),
        .perm_rounds    (hash_perm_rounds),
        .perm_state_in  (hash_perm_state_in),
        .perm_state_out (perm_state_out),
        .perm_busy      (perm_busy),
        .perm_done      (perm_done & sel_hash_r)
    );

    // -------------------------------------------------------------------------
    // XOF128 controller
    // -------------------------------------------------------------------------
    wire         xof_perm_start;
    wire [3:0]   xof_perm_rounds;
    wire [319:0] xof_perm_state_in;

    wire         xof_in_ready;
    wire [63:0]  xof_out_block;
    wire         xof_out_valid;
    wire         xof_out_last;
    wire [3:0]   xof_out_byte_count;
    wire         xof_busy;
    wire         xof_done;

    xof_controller u_xof (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (xof_start),
        .reset_engine   (reset_engine),

        .msg_total_bytes(msg_total_bytes),
        .out_length     (out_length),
        .chain_enable   (chain_enable),
        .chain_count    (chain_count),
        .chain_debug    (chain_debug),

        .in_word        (in_word),
        .in_word_bytes  (in_word_bytes),
        .in_word_last   (in_word_last),
        .in_word_valid  (xof_in_valid),
        .in_word_ready  (xof_in_ready),

        .out_block      (xof_out_block),
        .out_valid      (xof_out_valid),
        .out_last       (xof_out_last),
        .out_byte_count (xof_out_byte_count),

        .busy           (xof_busy),
        .done           (xof_done),

        .perm_start     (xof_perm_start),
        .perm_rounds    (xof_perm_rounds),
        .perm_state_in  (xof_perm_state_in),
        .perm_state_out (perm_state_out),
        .perm_busy      (perm_busy),
        .perm_done      (perm_done & sel_xof_r)
    );

    // -------------------------------------------------------------------------
    // CXOF128 controller
    // -------------------------------------------------------------------------
    wire         cxof_perm_start;
    wire [3:0]   cxof_perm_rounds;
    wire [319:0] cxof_perm_state_in;

    wire         cxof_in_ready;
    wire [63:0]  cxof_out_block;
    wire         cxof_out_valid;
    wire         cxof_out_last;
    wire [3:0]   cxof_out_byte_count;
    wire         cxof_busy;
    wire         cxof_done;

    cxof_controller u_cxof (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (cxof_start),
        .reset_engine   (reset_engine),

        .cs_total_bits  (cs_total_bits),
        .msg_total_bytes(msg_total_bytes),
        .out_length     (out_length),
        .chain_enable   (chain_enable),
        .chain_count    (chain_count),
        .chain_debug    (chain_debug),

        .in_word        (in_word),
        .in_word_bytes  (in_word_bytes),
        .in_word_last   (in_word_last),
        .in_word_is_cs  (in_word_is_cs),
        .in_word_valid  (cxof_in_valid),
        .in_word_ready  (cxof_in_ready),

        .out_block      (cxof_out_block),
        .out_valid      (cxof_out_valid),
        .out_last       (cxof_out_last),
        .out_byte_count (cxof_out_byte_count),

        .busy           (cxof_busy),
        .done           (cxof_done),

        .perm_start     (cxof_perm_start),
        .perm_rounds    (cxof_perm_rounds),
        .perm_state_in  (cxof_perm_state_in),
        .perm_state_out (perm_state_out),
        .perm_busy      (perm_busy),
        .perm_done      (perm_done & sel_cxof_r)
    );

    // -------------------------------------------------------------------------
    // AEAD128 controller
    // -------------------------------------------------------------------------
    wire         aead_perm_start;
    wire [3:0]   aead_perm_rounds;
    wire [319:0] aead_perm_state_in;

    wire         aead_in_ready;
    wire [63:0]  aead_out_block;
    wire         aead_out_valid;
    wire         aead_out_last;
    wire [3:0]   aead_out_byte_count;
    wire         aead_auth_ok;
    wire         aead_busy;
    wire         aead_done;

    aead_controller u_aead (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (aead_start),
        .reset_engine   (reset_engine),

        .is_decrypt     (is_decrypt),
        .ad_total_bytes (ad_total_bytes),
        .data_total_bytes(data_total_bytes),

        .in_word        (in_word),
        .in_word_bytes  (in_word_bytes),
        .in_word_last   (in_word_last),
        .in_phase       (3'd0),
        .in_word_valid  (aead_in_valid),
        .in_word_ready  (aead_in_ready),

        .out_block      (aead_out_block),
        .out_valid      (aead_out_valid),
        .out_last       (aead_out_last),
        .out_byte_count (aead_out_byte_count),
        .auth_ok        (aead_auth_ok),

        .busy           (aead_busy),
        .done           (aead_done),

        .perm_start     (aead_perm_start),
        .perm_rounds    (aead_perm_rounds),
        .perm_state_in  (aead_perm_state_in),
        .perm_state_out (perm_state_out),
        .perm_busy      (perm_busy),
        .perm_done      (perm_done & sel_aead_r)
    );

    // -------------------------------------------------------------------------
    // Registered permutation input arbiter / 1-entry input slice
    // -------------------------------------------------------------------------
    reg         perm_start_req;
    reg [3:0]   perm_rounds_req;
    reg [319:0] perm_state_in_req;

    always @(*) begin
        perm_start_req    = 1'b0;
        perm_rounds_req   = 4'd12;
        perm_state_in_req = 320'd0;

        if (sel_hash_r) begin
            perm_start_req    = hash_perm_start;
            perm_rounds_req   = hash_perm_rounds;
            perm_state_in_req = hash_perm_state_in;
        end else if (sel_xof_r) begin
            perm_start_req    = xof_perm_start;
            perm_rounds_req   = xof_perm_rounds;
            perm_state_in_req = xof_perm_state_in;
        end else if (sel_cxof_r) begin
            perm_start_req    = cxof_perm_start;
            perm_rounds_req   = cxof_perm_rounds;
            perm_state_in_req = cxof_perm_state_in;
        end else if (sel_aead_r) begin
            perm_start_req    = aead_perm_start;
            perm_rounds_req   = aead_perm_rounds;
            perm_state_in_req = aead_perm_state_in;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perm_start    <= 1'b0;
            perm_rounds   <= 4'd12;
            perm_state_in <= 320'd0;
        end else if (reset_engine) begin
            perm_start    <= 1'b0;
            perm_rounds   <= 4'd12;
            perm_state_in <= 320'd0;
        end else begin
            perm_start <= 1'b0;

            if (perm_start_req) begin
                perm_start    <= 1'b1;
                perm_rounds   <= perm_rounds_req;
                perm_state_in <= perm_state_in_req;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Input ready mux
    // -------------------------------------------------------------------------
    always @(*) begin
        in_word_ready = 1'b0;

        if (sel_hash_r) begin
            in_word_ready = hash_in_ready;
        end else if (sel_xof_r) begin
            in_word_ready = xof_in_ready;
        end else if (sel_cxof_r) begin
            in_word_ready = cxof_in_ready;
        end else if (sel_aead_r) begin
            in_word_ready = aead_in_ready;
        end
    end

    // -------------------------------------------------------------------------
    // Output/status mux
    // -------------------------------------------------------------------------
    always @(*) begin
        out_block      = 64'd0;
        out_valid      = 1'b0;
        out_last       = 1'b0;
        out_byte_count = 4'd0;
        busy           = 1'b0;
        done           = 1'b0;
        auth_ok        = 1'b0;

        if (sel_hash_r) begin
            out_block      = hash_out_block;
            out_valid      = hash_out_valid;
            out_last       = hash_out_last;
            out_byte_count = hash_out_byte_count;
            busy           = hash_busy;
            done           = hash_done;
        end else if (sel_xof_r) begin
            out_block      = xof_out_block;
            out_valid      = xof_out_valid;
            out_last       = xof_out_last;
            out_byte_count = xof_out_byte_count;
            busy           = xof_busy;
            done           = xof_done;
        end else if (sel_cxof_r) begin
            out_block      = cxof_out_block;
            out_valid      = cxof_out_valid;
            out_last       = cxof_out_last;
            out_byte_count = cxof_out_byte_count;
            busy           = cxof_busy;
            done           = cxof_done;
        end else if (sel_aead_r) begin
            out_block      = aead_out_block;
            out_valid      = aead_out_valid;
            out_last       = aead_out_last;
            out_byte_count = aead_out_byte_count;
            busy           = aead_busy;
            done           = aead_done;
            auth_ok        = aead_auth_ok;
        end
    end

endmodule

`default_nettype wire
