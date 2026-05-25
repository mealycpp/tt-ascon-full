/*
 * mode_controller.v — SDMC-ASCON dispatcher (streaming I/O).
 *
 * Patch-fed architecture:
 * - ONE shared ascon_sponge_core instance.
 * - HASH256, XOF128, CXOF128, and AEAD128 are patch-command producers.
 * - Controllers never build or mux a 320-bit permutation input.
 * - The only 320-bit ASCON state exists inside ascon_sponge_core.
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
    // Per-mode patch-command wires
    // -------------------------------------------------------------------------
    wire         hash_patch_valid;
    wire [1:0]   hash_patch_op;
    wire [2:0]   hash_patch_lane;
    wire [63:0]  hash_patch_data;
    wire         hash_perm_start;
    wire [3:0]   hash_perm_rounds;

    wire         xof_patch_valid;
    wire [1:0]   xof_patch_op;
    wire [2:0]   xof_patch_lane;
    wire [63:0]  xof_patch_data;
    wire         xof_perm_start;
    wire [3:0]   xof_perm_rounds;

    wire         cxof_patch_valid;
    wire [1:0]   cxof_patch_op;
    wire [2:0]   cxof_patch_lane;
    wire [63:0]  cxof_patch_data;
    wire         cxof_perm_start;
    wire [3:0]   cxof_perm_rounds;

    wire         aead_patch_valid;
    wire [1:0]   aead_patch_op;
    wire [2:0]   aead_patch_lane;
    wire [63:0]  aead_patch_data;
    wire         aead_perm_start;
    wire [3:0]   aead_perm_rounds;

    // -------------------------------------------------------------------------
    // Three local buses feeding one physical patch-fed ASCON sponge core
    //
    // HASH bus  : HASH/XOF, x0-only readback
    // CHAIN bus : CXOF/CXOF-chain, x0-only readback
    // AEAD bus  : AEAD enc/dec, full x0..x4 readback
    //
    // Core outputs are captured on core_perm_done and forwarded to controllers
    // with a one-cycle delayed done pulse. This removes live core_x* fanout.
    // -------------------------------------------------------------------------
    wire hash_bus_sel  = sel_hash_r | sel_xof_r;
    wire chain_bus_sel = sel_cxof_r;
    wire aead_bus_sel  = sel_aead_r;

    wire         hash_bus_patch_valid = sel_hash_r ? hash_patch_valid : xof_patch_valid;
    wire [1:0]   hash_bus_patch_op    = sel_hash_r ? hash_patch_op    : xof_patch_op;
    wire [2:0]   hash_bus_patch_lane  = sel_hash_r ? hash_patch_lane  : xof_patch_lane;
    wire [63:0]  hash_bus_patch_data  = sel_hash_r ? hash_patch_data  : xof_patch_data;
    wire         hash_bus_perm_start  = sel_hash_r ? hash_perm_start  : xof_perm_start;
    wire [3:0]   hash_bus_perm_rounds = sel_hash_r ? hash_perm_rounds : xof_perm_rounds;

    wire         chain_bus_patch_valid = cxof_patch_valid;
    wire [1:0]   chain_bus_patch_op    = cxof_patch_op;
    wire [2:0]   chain_bus_patch_lane  = cxof_patch_lane;
    wire [63:0]  chain_bus_patch_data  = cxof_patch_data;
    wire         chain_bus_perm_start  = cxof_perm_start;
    wire [3:0]   chain_bus_perm_rounds = cxof_perm_rounds;

    wire         aead_bus_patch_valid = aead_patch_valid;
    wire [1:0]   aead_bus_patch_op    = aead_patch_op;
    wire [2:0]   aead_bus_patch_lane  = aead_patch_lane;
    wire [63:0]  aead_bus_patch_data  = aead_patch_data;
    wire         aead_bus_perm_start  = aead_perm_start;
    wire [3:0]   aead_bus_perm_rounds = aead_perm_rounds;

    reg         core_patch_valid;
    reg [1:0]   core_patch_op;
    reg [2:0]   core_patch_lane;
    reg [63:0]  core_patch_data;

    reg         core_perm_start;
    reg [3:0]   core_perm_rounds;

    wire        core_patch_ready;
    wire        core_perm_busy;
    wire        core_perm_done;

    wire [63:0] core_x0;
    wire [63:0] core_x1;
    wire [63:0] core_x2;
    wire [63:0] core_x3;
    wire [63:0] core_x4;

    ascon_sponge_core u_core (
        .clk          (clk),
        .rst_n        (rst_n),

        .patch_valid  (core_patch_valid),
        .patch_ready  (core_patch_ready),
        .patch_op     (core_patch_op),
        .patch_lane   (core_patch_lane),
        .patch_data   (core_patch_data),

        .perm_start   (core_perm_start),
        .perm_rounds  (core_perm_rounds),
        .perm_busy    (core_perm_busy),
        .perm_done    (core_perm_done),

        .x0           (core_x0),
        .x1           (core_x1),
        .x2           (core_x2),
        .x3           (core_x3),
        .x4           (core_x4)
    );

    always @(*) begin
        core_patch_valid = 1'b0;
        core_patch_op    = 2'd0;
        core_patch_lane  = 3'd0;
        core_patch_data  = 64'd0;

        if (hash_bus_sel) begin
            core_patch_valid = hash_bus_patch_valid;
            core_patch_op    = hash_bus_patch_op;
            core_patch_lane  = hash_bus_patch_lane;
            core_patch_data  = hash_bus_patch_data;
        end else if (chain_bus_sel) begin
            core_patch_valid = chain_bus_patch_valid;
            core_patch_op    = chain_bus_patch_op;
            core_patch_lane  = chain_bus_patch_lane;
            core_patch_data  = chain_bus_patch_data;
        end else if (aead_bus_sel) begin
            core_patch_valid = aead_bus_patch_valid;
            core_patch_op    = aead_bus_patch_op;
            core_patch_lane  = aead_bus_patch_lane;
            core_patch_data  = aead_bus_patch_data;
        end
    end

    always @(*) begin
        core_perm_start  = 1'b0;
        core_perm_rounds = 4'd12;

        if (hash_bus_sel) begin
            core_perm_start  = hash_bus_perm_start;
            core_perm_rounds = hash_bus_perm_rounds;
        end else if (chain_bus_sel) begin
            core_perm_start  = chain_bus_perm_start;
            core_perm_rounds = chain_bus_perm_rounds;
        end else if (aead_bus_sel) begin
            core_perm_start  = aead_bus_perm_start;
            core_perm_rounds = aead_bus_perm_rounds;
        end
    end

    wire hash_bus_patch_ready  = core_patch_ready & hash_bus_sel;
    wire chain_bus_patch_ready = core_patch_ready & chain_bus_sel;
    wire aead_bus_patch_ready  = core_patch_ready & aead_bus_sel;

    wire hash_patch_ready_local = hash_bus_patch_ready & sel_hash_r;
    wire xof_patch_ready_local  = hash_bus_patch_ready & sel_xof_r;
    wire cxof_patch_ready_local = chain_bus_patch_ready & sel_cxof_r;
    wire aead_patch_ready_local = aead_bus_patch_ready & sel_aead_r;

    wire hash_bus_perm_busy  = core_perm_busy & hash_bus_sel;
    wire chain_bus_perm_busy = core_perm_busy & chain_bus_sel;
    wire aead_bus_perm_busy  = core_perm_busy & aead_bus_sel;

    wire hash_perm_busy_local = hash_bus_perm_busy & sel_hash_r;
    wire xof_perm_busy_local  = hash_bus_perm_busy & sel_xof_r;
    wire cxof_perm_busy_local = chain_bus_perm_busy & sel_cxof_r;
    wire aead_perm_busy_local = aead_bus_perm_busy & sel_aead_r;

    reg [63:0] hash_bus_x0;
    reg [63:0] chain_bus_x0;

    reg [63:0] aead_bus_x0;
    reg [63:0] aead_bus_x1;
    reg [63:0] aead_bus_x2;
    reg [63:0] aead_bus_x3;
    reg [63:0] aead_bus_x4;

    reg hash_core_done;
    reg xof_core_done;
    reg cxof_core_done;
    reg aead_core_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hash_bus_x0    <= 64'd0;
            chain_bus_x0   <= 64'd0;
            aead_bus_x0    <= 64'd0;
            aead_bus_x1    <= 64'd0;
            aead_bus_x2    <= 64'd0;
            aead_bus_x3    <= 64'd0;
            aead_bus_x4    <= 64'd0;
            hash_core_done <= 1'b0;
            xof_core_done  <= 1'b0;
            cxof_core_done <= 1'b0;
            aead_core_done <= 1'b0;
        end else begin
            hash_core_done <= 1'b0;
            xof_core_done  <= 1'b0;
            cxof_core_done <= 1'b0;
            aead_core_done <= 1'b0;

            if (reset_engine) begin
                hash_bus_x0  <= 64'd0;
                chain_bus_x0 <= 64'd0;
                aead_bus_x0  <= 64'd0;
                aead_bus_x1  <= 64'd0;
                aead_bus_x2  <= 64'd0;
                aead_bus_x3  <= 64'd0;
                aead_bus_x4  <= 64'd0;
            end else if (core_perm_done) begin
                if (sel_hash_r) begin
                    hash_bus_x0    <= core_x0;
                    hash_core_done <= 1'b1;
                end else if (sel_xof_r) begin
                    hash_bus_x0   <= core_x0;
                    xof_core_done <= 1'b1;
                end else if (sel_cxof_r) begin
                    chain_bus_x0   <= core_x0;
                    cxof_core_done <= 1'b1;
                end else if (sel_aead_r) begin
                    aead_bus_x0    <= core_x0;
                    aead_bus_x1    <= core_x1;
                    aead_bus_x2    <= core_x2;
                    aead_bus_x3    <= core_x3;
                    aead_bus_x4    <= core_x4;
                    aead_core_done <= 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // HASH256 patch controller
    // -------------------------------------------------------------------------
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
        .patch_ready    (hash_patch_ready_local),
        .patch_op       (hash_patch_op),
        .patch_lane     (hash_patch_lane),
        .patch_data     (hash_patch_data),

        .perm_start     (hash_perm_start),
        .perm_rounds    (hash_perm_rounds),
        .perm_busy      (hash_perm_busy_local),
        .perm_done      (hash_core_done),

        .core_x0        (hash_bus_x0)
    );

    // -------------------------------------------------------------------------
    // XOF128 patch controller
    // -------------------------------------------------------------------------
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
        .patch_ready    (xof_patch_ready_local),
        .patch_op       (xof_patch_op),
        .patch_lane     (xof_patch_lane),
        .patch_data     (xof_patch_data),

        .perm_start     (xof_perm_start),
        .perm_rounds    (xof_perm_rounds),
        .perm_busy      (xof_perm_busy_local),
        .perm_done      (xof_core_done),

        .core_x0        (hash_bus_x0)
    );

    // -------------------------------------------------------------------------
    // CXOF128 patch controller
    // -------------------------------------------------------------------------
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
        .patch_ready    (cxof_patch_ready_local),
        .patch_op       (cxof_patch_op),
        .patch_lane     (cxof_patch_lane),
        .patch_data     (cxof_patch_data),

        .perm_start     (cxof_perm_start),
        .perm_rounds    (cxof_perm_rounds),
        .perm_busy      (cxof_perm_busy_local),
        .perm_done      (cxof_core_done),

        .core_x0        (chain_bus_x0)
    );

    // -------------------------------------------------------------------------
    // AEAD128 patch controller
    // -------------------------------------------------------------------------
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
        .patch_ready     (aead_patch_ready_local),
        .patch_op        (aead_patch_op),
        .patch_lane      (aead_patch_lane),
        .patch_data      (aead_patch_data),

        .perm_start      (aead_perm_start),
        .perm_rounds     (aead_perm_rounds),
        .perm_busy       (aead_perm_busy_local),
        .perm_done       (aead_core_done),

        .core_x0         (aead_bus_x0),
        .core_x1         (aead_bus_x1),
        .core_x2         (aead_bus_x2),
        .core_x3         (aead_bus_x3),
        .core_x4         (aead_bus_x4)
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
