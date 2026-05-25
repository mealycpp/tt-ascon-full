/*
 * mode_controller.v — SDMC-ASCON dispatcher (streaming I/O).
 *
 * Transitional patch-fed architecture:
 * - HASH256, XOF128, CXOF128, and AEAD128 use patch-fed ASCON sponge cores.
 * - Legacy 320-bit permutation input/output boundary is removed from mode_controller.
 */

`default_nettype none

module mode_controller (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [2:0]   mode_sel,
    input  wire         start,
    input  wire         reset_engine,

    input  wire [15:0]  cs_total_bits,
    input  wire [15:0]  msg_total_bytes,
    input  wire [15:0]  out_length,
    input  wire         chain_enable,
    input  wire [15:0]  chain_count,
    input  wire         chain_debug,

    input  wire         is_decrypt,
    input  wire [15:0]  ad_total_bytes,
    input  wire [15:0]  data_total_bytes,

    input  wire [63:0]  in_word,
    input  wire [3:0]   in_word_bytes,
    input  wire         in_word_last,
    input  wire         in_word_is_cs,
    input  wire         in_word_valid,
    output reg          in_word_ready,

    output reg  [63:0]  out_block,
    output reg          out_valid,
    output reg          out_last,
    output reg  [3:0]   out_byte_count,

    output reg          auth_ok,

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

    reg sel_hash_r;
    reg sel_xof_r;
    reg sel_cxof_r;
    reg sel_aead_r;

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

    wire hash_in_valid = in_word_valid & sel_hash_r;
    wire xof_in_valid  = in_word_valid & sel_xof_r;
    wire cxof_in_valid = in_word_valid & sel_cxof_r;
    wire aead_in_valid = in_word_valid & sel_aead_r;

    // -------------------------------------------------------------------------
    // HASH256: new patch-fed sponge core path
    // -------------------------------------------------------------------------
    wire         hash_patch_valid;
    wire         hash_patch_ready;
    wire [1:0]   hash_patch_op;
    wire [2:0]   hash_patch_lane;
    wire [63:0]  hash_patch_data;

    wire         hash_core_perm_start;
    wire [3:0]   hash_core_perm_rounds;
    wire         hash_core_perm_busy;
    wire         hash_core_perm_done;

    wire [63:0]  hash_core_x0;
    wire [63:0]  hash_core_x1;
    wire [63:0]  hash_core_x2;
    wire [63:0]  hash_core_x3;
    wire [63:0]  hash_core_x4;

    ascon_sponge_core u_hash_core (
        .clk          (clk),
        .rst_n        (rst_n),

        .patch_valid  (hash_patch_valid),
        .patch_ready  (hash_patch_ready),
        .patch_op     (hash_patch_op),
        .patch_lane   (hash_patch_lane),
        .patch_data   (hash_patch_data),

        .perm_start   (hash_core_perm_start),
        .perm_rounds  (hash_core_perm_rounds),
        .perm_busy    (hash_core_perm_busy),
        .perm_done    (hash_core_perm_done),

        .x0           (hash_core_x0),
        .x1           (hash_core_x1),
        .x2           (hash_core_x2),
        .x3           (hash_core_x3),
        .x4           (hash_core_x4)
    );

    wire         hash_in_ready;
    wire [63:0]  hash_out_block;
    wire         hash_out_valid;
    wire         hash_out_last;
    wire [3:0]   hash_out_byte_count;
    wire         hash_busy;
    wire         hash_done;

    hash_patch_controller u_hash (
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

        .patch_valid    (hash_patch_valid),
        .patch_ready    (hash_patch_ready),
        .patch_op       (hash_patch_op),
        .patch_lane     (hash_patch_lane),
        .patch_data     (hash_patch_data),

        .perm_start     (hash_core_perm_start),
        .perm_rounds    (hash_core_perm_rounds),
        .perm_busy      (hash_core_perm_busy),
        .perm_done      (hash_core_perm_done),

        .core_x0        (hash_core_x0)
    );

    wire _unused_hash_core = &{hash_core_x1, hash_core_x2, hash_core_x3, hash_core_x4, 1'b0};

    // -------------------------------------------------------------------------
    // No legacy 320-bit permutation boundary remains in mode_controller.
    // Each migrated mode currently owns a patch-fed sponge instance.
    // Final area cleanup can collapse these into one shared patch-fed core.
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // XOF128: new patch-fed sponge core path
    // -------------------------------------------------------------------------
    wire         xof_patch_valid;
    wire         xof_patch_ready;
    wire [1:0]   xof_patch_op;
    wire [2:0]   xof_patch_lane;
    wire [63:0]  xof_patch_data;

    wire         xof_core_perm_start;
    wire [3:0]   xof_core_perm_rounds;
    wire         xof_core_perm_busy;
    wire         xof_core_perm_done;

    wire [63:0]  xof_core_x0;
    wire [63:0]  xof_core_x1;
    wire [63:0]  xof_core_x2;
    wire [63:0]  xof_core_x3;
    wire [63:0]  xof_core_x4;

    ascon_sponge_core u_xof_core (
        .clk          (clk),
        .rst_n        (rst_n),

        .patch_valid  (xof_patch_valid),
        .patch_ready  (xof_patch_ready),
        .patch_op     (xof_patch_op),
        .patch_lane   (xof_patch_lane),
        .patch_data   (xof_patch_data),

        .perm_start   (xof_core_perm_start),
        .perm_rounds  (xof_core_perm_rounds),
        .perm_busy    (xof_core_perm_busy),
        .perm_done    (xof_core_perm_done),

        .x0           (xof_core_x0),
        .x1           (xof_core_x1),
        .x2           (xof_core_x2),
        .x3           (xof_core_x3),
        .x4           (xof_core_x4)
    );

    wire         xof_in_ready;
    wire [63:0]  xof_out_block;
    wire         xof_out_valid;
    wire         xof_out_last;
    wire [3:0]   xof_out_byte_count;
    wire         xof_busy;
    wire         xof_done;

    xof_patch_controller u_xof (
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

        .patch_valid    (xof_patch_valid),
        .patch_ready    (xof_patch_ready),
        .patch_op       (xof_patch_op),
        .patch_lane     (xof_patch_lane),
        .patch_data     (xof_patch_data),

        .perm_start     (xof_core_perm_start),
        .perm_rounds    (xof_core_perm_rounds),
        .perm_busy      (xof_core_perm_busy),
        .perm_done      (xof_core_perm_done),

        .core_x0        (xof_core_x0)
    );

    wire _unused_xof_core = &{xof_core_x1, xof_core_x2, xof_core_x3, xof_core_x4, 1'b0};

    // -------------------------------------------------------------------------
    // CXOF128: new patch-fed sponge core path
    // -------------------------------------------------------------------------
    wire         cxof_patch_valid;
    wire         cxof_patch_ready;
    wire [1:0]   cxof_patch_op;
    wire [2:0]   cxof_patch_lane;
    wire [63:0]  cxof_patch_data;

    wire         cxof_core_perm_start;
    wire [3:0]   cxof_core_perm_rounds;
    wire         cxof_core_perm_busy;
    wire         cxof_core_perm_done;

    wire [63:0]  cxof_core_x0;
    wire [63:0]  cxof_core_x1;
    wire [63:0]  cxof_core_x2;
    wire [63:0]  cxof_core_x3;
    wire [63:0]  cxof_core_x4;

    ascon_sponge_core u_cxof_core (
        .clk          (clk),
        .rst_n        (rst_n),

        .patch_valid  (cxof_patch_valid),
        .patch_ready  (cxof_patch_ready),
        .patch_op     (cxof_patch_op),
        .patch_lane   (cxof_patch_lane),
        .patch_data   (cxof_patch_data),

        .perm_start   (cxof_core_perm_start),
        .perm_rounds  (cxof_core_perm_rounds),
        .perm_busy    (cxof_core_perm_busy),
        .perm_done    (cxof_core_perm_done),

        .x0           (cxof_core_x0),
        .x1           (cxof_core_x1),
        .x2           (cxof_core_x2),
        .x3           (cxof_core_x3),
        .x4           (cxof_core_x4)
    );

    wire         cxof_in_ready;
    wire [63:0]  cxof_out_block;
    wire         cxof_out_valid;
    wire         cxof_out_last;
    wire [3:0]   cxof_out_byte_count;
    wire         cxof_busy;
    wire         cxof_done;

    cxof_patch_controller u_cxof (
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

        .patch_valid    (cxof_patch_valid),
        .patch_ready    (cxof_patch_ready),
        .patch_op       (cxof_patch_op),
        .patch_lane     (cxof_patch_lane),
        .patch_data     (cxof_patch_data),

        .perm_start     (cxof_core_perm_start),
        .perm_rounds    (cxof_core_perm_rounds),
        .perm_busy      (cxof_core_perm_busy),
        .perm_done      (cxof_core_perm_done),

        .core_x0        (cxof_core_x0)
    );

    wire _unused_cxof_core = &{cxof_core_x1, cxof_core_x2, cxof_core_x3, cxof_core_x4, 1'b0};

    // -------------------------------------------------------------------------
    // AEAD128: new patch-fed sponge core path
    // -------------------------------------------------------------------------
    wire         aead_patch_valid;
    wire         aead_patch_ready;
    wire [1:0]   aead_patch_op;
    wire [2:0]   aead_patch_lane;
    wire [63:0]  aead_patch_data;

    wire         aead_core_perm_start;
    wire [3:0]   aead_core_perm_rounds;
    wire         aead_core_perm_busy;
    wire         aead_core_perm_done;

    wire [63:0]  aead_core_x0;
    wire [63:0]  aead_core_x1;
    wire [63:0]  aead_core_x2;
    wire [63:0]  aead_core_x3;
    wire [63:0]  aead_core_x4;

    ascon_sponge_core u_aead_core (
        .clk          (clk),
        .rst_n        (rst_n),

        .patch_valid  (aead_patch_valid),
        .patch_ready  (aead_patch_ready),
        .patch_op     (aead_patch_op),
        .patch_lane   (aead_patch_lane),
        .patch_data   (aead_patch_data),

        .perm_start   (aead_core_perm_start),
        .perm_rounds  (aead_core_perm_rounds),
        .perm_busy    (aead_core_perm_busy),
        .perm_done    (aead_core_perm_done),

        .x0           (aead_core_x0),
        .x1           (aead_core_x1),
        .x2           (aead_core_x2),
        .x3           (aead_core_x3),
        .x4           (aead_core_x4)
    );

    wire         aead_in_ready;
    wire [63:0]  aead_out_block;
    wire         aead_out_valid;
    wire         aead_out_last;
    wire [3:0]   aead_out_byte_count;
    wire         aead_auth_ok;
    wire         aead_busy;
    wire         aead_done;

    aead_patch_controller u_aead (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (aead_start),
        .reset_engine    (reset_engine),

        .is_decrypt      (is_decrypt),
        .ad_total_bytes  (ad_total_bytes),
        .data_total_bytes(data_total_bytes),

        .in_word         (in_word),
        .in_word_bytes   (in_word_bytes),
        .in_word_last    (in_word_last),
        .in_phase        (3'd0),
        .in_word_valid   (aead_in_valid),
        .in_word_ready   (aead_in_ready),

        .out_block       (aead_out_block),
        .out_valid       (aead_out_valid),
        .out_last        (aead_out_last),
        .out_byte_count  (aead_out_byte_count),
        .auth_ok         (aead_auth_ok),

        .busy            (aead_busy),
        .done            (aead_done),

        .patch_valid     (aead_patch_valid),
        .patch_ready     (aead_patch_ready),
        .patch_op        (aead_patch_op),
        .patch_lane      (aead_patch_lane),
        .patch_data      (aead_patch_data),

        .perm_start      (aead_core_perm_start),
        .perm_rounds     (aead_core_perm_rounds),
        .perm_busy       (aead_core_perm_busy),
        .perm_done       (aead_core_perm_done),

        .core_x0         (aead_core_x0),
        .core_x1         (aead_core_x1),
        .core_x2         (aead_core_x2),
        .core_x3         (aead_core_x3),
        .core_x4         (aead_core_x4)
    );

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
