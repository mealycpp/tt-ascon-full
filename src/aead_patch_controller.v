/*
 * aead_patch_controller.v -- ASCON-AEAD128 controller for patch-fed sponge core.
 *
 * Rule:
 *   - This controller never builds a 320-bit permutation input.
 *   - The sponge core owns x0..x4.
 *   - This controller sends 64-bit LOAD/XOR patches and starts p[12]/p[8].
 */

`default_nettype none

module aead_patch_controller (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    input  wire         reset_engine,
    input  wire         is_decrypt,

    input  wire [15:0]  ad_total_bytes,
    input  wire [15:0]  data_total_bytes,

    input  wire [63:0]  in_word,
    input  wire [3:0]   in_word_bytes,
    input  wire         in_word_last,
    input  wire [2:0]   in_phase,
    input  wire         in_word_valid,
    output reg          in_word_ready,

    output reg  [63:0]  out_block,
    output reg          out_valid,
    output reg          out_last,
    output reg  [3:0]   out_byte_count,

    output reg          auth_ok,

    output reg          busy,
    output reg          done,

    output reg          patch_valid,
    input  wire         patch_ready,
    output reg  [1:0]   patch_op,
    output reg  [2:0]   patch_lane,
    output reg  [63:0]  patch_data,

    output reg          perm_start,
    output reg  [3:0]   perm_rounds,
    input  wire         perm_busy,
    input  wire         perm_done,

    input  wire [63:0]  core_x0,
    input  wire [63:0]  core_x1,
    input  wire [63:0]  core_x2,
    input  wire [63:0]  core_x3,
    input  wire [63:0]  core_x4
);

    localparam [63:0] AEAD_IV = 64'h0000_1000_808C_0001;

    localparam PATCH_LOAD  = 2'd0;
    localparam PATCH_XOR   = 2'd1;
    localparam PATCH_CLEAR = 2'd2;

    localparam LANE_X0 = 3'd0;
    localparam LANE_X1 = 3'd1;
    localparam LANE_X2 = 3'd2;
    localparam LANE_X3 = 3'd3;
    localparam LANE_X4 = 3'd4;

    localparam S_IDLE              = 6'd0;
    localparam S_KEY_PULL_LO       = 6'd1;
    localparam S_KEY_PULL_HI       = 6'd2;
    localparam S_NONCE_PULL_LO     = 6'd3;
    localparam S_NONCE_PULL_HI     = 6'd4;

    localparam S_CLEAR             = 6'd5;
    localparam S_LOAD_X0_IV        = 6'd6;
    localparam S_LOAD_X1_KEYLO     = 6'd7;
    localparam S_LOAD_X2_KEYHI     = 6'd8;
    localparam S_LOAD_X3_NONCELO   = 6'd9;
    localparam S_LOAD_X4_NONCEHI   = 6'd10;
    localparam S_INIT_KICK         = 6'd11;
    localparam S_INIT_WAIT         = 6'd12;
    localparam S_INIT_X4_KEYHI     = 6'd13;
    localparam S_INIT_X3_KEYLO     = 6'd14;

    localparam S_AD_W0_GET         = 6'd15;
    localparam S_AD_W1_GET         = 6'd16;
    localparam S_AD_PATCH_X0       = 6'd17;
    localparam S_AD_PATCH_X1       = 6'd18;
    localparam S_AD_PERM           = 6'd19;
    localparam S_AD_WAIT           = 6'd20;
    localparam S_AD_DOMSEP         = 6'd21;

    localparam S_DATA_W0_GET       = 6'd22;
    localparam S_DATA_W1_GET       = 6'd23;
    localparam S_DATA_EMIT_W0      = 6'd24;
    localparam S_DATA_EMIT_W1      = 6'd25;
    localparam S_DATA_PATCH_X0     = 6'd26;
    localparam S_DATA_PATCH_X1     = 6'd27;
    localparam S_DATA_PERM         = 6'd28;
    localparam S_DATA_WAIT         = 6'd29;

    localparam S_FINAL_PATCH_X3    = 6'd30;
    localparam S_FINAL_PATCH_X2    = 6'd31;
    localparam S_FINAL_KICK        = 6'd32;
    localparam S_FINAL_WAIT        = 6'd33;

    localparam S_TAG_EMIT_LO       = 6'd34;
    localparam S_TAG_EMIT_HI       = 6'd35;
    localparam S_TAG_CMP_LO        = 6'd36;
    localparam S_TAG_CMP_HI        = 6'd37;
    localparam S_FINISH            = 6'd38;

    reg [5:0]   state;

    reg [63:0]  key_lo;
    reg [63:0]  key_hi;
    reg [63:0]  nonce_lo_tmp;
    reg [63:0]  nonce_hi_tmp;
    reg         is_decrypt_r;

    reg [11:0]  ad_blocks_left;
    reg [11:0]  data_blocks_left;

    reg [15:0]  ad_bytes_left;
    reg [15:0]  data_bytes_left;
    reg         ad_pad_done;
    reg         data_pad_done;

    reg [63:0]  w0_buf;
    reg [3:0]   w0_real;
    reg [63:0]  w1_buf;
    reg [3:0]   w1_real;

    wire _unused = &{perm_busy, in_phase, in_word_last, in_word_bytes, core_x2, 1'b0};

    function [63:0] pad_word;
        input [3:0] n;
        begin
            case (n[2:0])
                3'd0: pad_word = 64'h0000_0000_0000_0001;
                3'd1: pad_word = 64'h0000_0000_0000_0100;
                3'd2: pad_word = 64'h0000_0000_0001_0000;
                3'd3: pad_word = 64'h0000_0000_0100_0000;
                3'd4: pad_word = 64'h0000_0001_0000_0000;
                3'd5: pad_word = 64'h0000_0100_0000_0000;
                3'd6: pad_word = 64'h0001_0000_0000_0000;
                3'd7: pad_word = 64'h0100_0000_0000_0000;
                default: pad_word = 64'h0;
            endcase
        end
    endfunction

    function [63:0] mask_lo;
        input [3:0] n;
        begin
            case (n[2:0])
                3'd0: mask_lo = 64'h0000_0000_0000_0000;
                3'd1: mask_lo = 64'h0000_0000_0000_00FF;
                3'd2: mask_lo = 64'h0000_0000_0000_FFFF;
                3'd3: mask_lo = 64'h0000_0000_00FF_FFFF;
                3'd4: mask_lo = 64'h0000_0000_FFFF_FFFF;
                3'd5: mask_lo = 64'h0000_00FF_FFFF_FFFF;
                3'd6: mask_lo = 64'h0000_FFFF_FFFF_FFFF;
                3'd7: mask_lo = 64'h00FF_FFFF_FFFF_FFFF;
                default: mask_lo = 64'h0;
            endcase
        end
    endfunction

    wire [63:0] dec_last_x0 =
        (w0_real == 4'd8) ? w0_buf : ((core_x0 & ~mask_lo(w0_real)) ^ w0_buf);

    wire [63:0] dec_last_x1 =
        (w1_real == 4'd8) ? w1_buf : ((core_x1 & ~mask_lo(w1_real)) ^ w1_buf);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            key_lo           <= 64'd0;
            key_hi           <= 64'd0;
            nonce_lo_tmp     <= 64'd0;
            nonce_hi_tmp     <= 64'd0;
            is_decrypt_r     <= 1'b0;
            ad_blocks_left   <= 12'd0;
            data_blocks_left <= 12'd0;
            ad_bytes_left    <= 16'd0;
            data_bytes_left  <= 16'd0;
            ad_pad_done      <= 1'b0;
            data_pad_done    <= 1'b0;
            w0_buf           <= 64'd0;
            w0_real          <= 4'd0;
            w1_buf           <= 64'd0;
            w1_real          <= 4'd0;
            in_word_ready    <= 1'b0;
            out_block        <= 64'd0;
            out_valid        <= 1'b0;
            out_last         <= 1'b0;
            out_byte_count   <= 4'd0;
            auth_ok          <= 1'b0;
            busy             <= 1'b0;
            done             <= 1'b0;
            patch_valid      <= 1'b0;
            patch_op         <= PATCH_CLEAR;
            patch_lane       <= LANE_X0;
            patch_data       <= 64'd0;
            perm_start       <= 1'b0;
            perm_rounds      <= 4'd12;
        end else if (reset_engine) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            in_word_ready <= 1'b0;
            patch_valid   <= 1'b0;
            perm_start    <= 1'b0;
        end else begin
            patch_valid   <= 1'b0;
            perm_start    <= 1'b0;
            done          <= 1'b0;
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            in_word_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        is_decrypt_r     <= is_decrypt;
                        auth_ok          <= 1'b1;
                        ad_blocks_left   <= (ad_total_bytes == 16'd0) ? 12'd0
                                            : (ad_total_bytes[15:4] + 12'd1);
                        data_blocks_left <= data_total_bytes[15:4] + 12'd1;
                        ad_bytes_left    <= ad_total_bytes;
                        data_bytes_left  <= data_total_bytes;
                        ad_pad_done      <= 1'b0;
                        data_pad_done    <= 1'b0;
                        busy             <= 1'b1;
                        state            <= S_KEY_PULL_LO;
                    end
                end

                S_KEY_PULL_LO: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        key_lo        <= in_word;
                        in_word_ready <= 1'b0;
                        state         <= S_KEY_PULL_HI;
                    end
                end

                S_KEY_PULL_HI: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        key_hi        <= in_word;
                        in_word_ready <= 1'b0;
                        state         <= S_NONCE_PULL_LO;
                    end
                end

                S_NONCE_PULL_LO: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        nonce_lo_tmp  <= in_word;
                        in_word_ready <= 1'b0;
                        state         <= S_NONCE_PULL_HI;
                    end
                end

                S_NONCE_PULL_HI: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        nonce_hi_tmp  <= in_word;
                        in_word_ready <= 1'b0;
                        state         <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_CLEAR;
                        patch_lane  <= LANE_X0;
                        patch_data  <= 64'd0;
                        state       <= S_LOAD_X0_IV;
                    end
                end

                S_LOAD_X0_IV: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_LOAD;
                        patch_lane  <= LANE_X0;
                        patch_data  <= AEAD_IV;
                        state       <= S_LOAD_X1_KEYLO;
                    end
                end

                S_LOAD_X1_KEYLO: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_LOAD;
                        patch_lane  <= LANE_X1;
                        patch_data  <= key_lo;
                        state       <= S_LOAD_X2_KEYHI;
                    end
                end

                S_LOAD_X2_KEYHI: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_LOAD;
                        patch_lane  <= LANE_X2;
                        patch_data  <= key_hi;
                        state       <= S_LOAD_X3_NONCELO;
                    end
                end

                S_LOAD_X3_NONCELO: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_LOAD;
                        patch_lane  <= LANE_X3;
                        patch_data  <= nonce_lo_tmp;
                        state       <= S_LOAD_X4_NONCEHI;
                    end
                end

                S_LOAD_X4_NONCEHI: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_LOAD;
                        patch_lane  <= LANE_X4;
                        patch_data  <= nonce_hi_tmp;
                        state       <= S_INIT_KICK;
                    end
                end

                S_INIT_KICK: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_INIT_WAIT;
                end

                S_INIT_WAIT: begin
                    if (perm_done) begin
                        state <= S_INIT_X4_KEYHI;
                    end
                end

                S_INIT_X4_KEYHI: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X4;
                        patch_data  <= key_hi;
                        state       <= S_INIT_X3_KEYLO;
                    end
                end

                S_INIT_X3_KEYLO: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X3;
                        patch_data  <= key_lo;
                        if (ad_blocks_left == 12'd0) state <= S_AD_DOMSEP;
                        else                         state <= S_AD_W0_GET;
                    end
                end

                S_AD_W0_GET: begin
                    if (ad_bytes_left >= 16'd8) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w0_buf        <= in_word;
                            w0_real       <= 4'd8;
                            ad_bytes_left <= ad_bytes_left - 16'd8;
                            in_word_ready <= 1'b0;
                            state         <= S_AD_W1_GET;
                        end
                    end else if (ad_bytes_left > 16'd0) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w0_buf        <= (in_word & mask_lo(ad_bytes_left[3:0]))
                                           | pad_word(ad_bytes_left[3:0]);
                            w0_real       <= ad_bytes_left[3:0];
                            ad_bytes_left <= 16'd0;
                            ad_pad_done   <= 1'b1;
                            in_word_ready <= 1'b0;
                            state         <= S_AD_W1_GET;
                        end
                    end else begin
                        if (!ad_pad_done) begin
                            w0_buf      <= pad_word(4'd0);
                            w0_real     <= 4'd0;
                            ad_pad_done <= 1'b1;
                        end else begin
                            w0_buf  <= 64'd0;
                            w0_real <= 4'd0;
                        end
                        state <= S_AD_W1_GET;
                    end
                end

                S_AD_W1_GET: begin
                    if (ad_bytes_left >= 16'd8) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w1_buf        <= in_word;
                            w1_real       <= 4'd8;
                            ad_bytes_left <= ad_bytes_left - 16'd8;
                            in_word_ready <= 1'b0;
                            state         <= S_AD_PATCH_X0;
                        end
                    end else if (ad_bytes_left > 16'd0) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w1_buf        <= (in_word & mask_lo(ad_bytes_left[3:0]))
                                           | pad_word(ad_bytes_left[3:0]);
                            w1_real       <= ad_bytes_left[3:0];
                            ad_bytes_left <= 16'd0;
                            ad_pad_done   <= 1'b1;
                            in_word_ready <= 1'b0;
                            state         <= S_AD_PATCH_X0;
                        end
                    end else begin
                        if (!ad_pad_done) begin
                            w1_buf      <= pad_word(4'd0);
                            w1_real     <= 4'd0;
                            ad_pad_done <= 1'b1;
                        end else begin
                            w1_buf  <= 64'd0;
                            w1_real <= 4'd0;
                        end
                        state <= S_AD_PATCH_X0;
                    end
                end

                S_AD_PATCH_X0: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X0;
                        patch_data  <= w0_buf;
                        state       <= S_AD_PATCH_X1;
                    end
                end

                S_AD_PATCH_X1: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X1;
                        patch_data  <= w1_buf;
                        state       <= S_AD_PERM;
                    end
                end

                S_AD_PERM: begin
                    perm_rounds <= 4'd8;
                    perm_start  <= 1'b1;
                    state       <= S_AD_WAIT;
                end

                S_AD_WAIT: begin
                    if (perm_done) begin
                        ad_blocks_left <= ad_blocks_left - 12'd1;
                        if (ad_blocks_left == 12'd1) state <= S_AD_DOMSEP;
                        else                         state <= S_AD_W0_GET;
                    end
                end

                S_AD_DOMSEP: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X4;
                        patch_data  <= 64'h8000_0000_0000_0000;
                        state       <= S_DATA_W0_GET;
                    end
                end

                S_DATA_W0_GET: begin
                    if (data_bytes_left >= 16'd8) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w0_buf          <= in_word;
                            w0_real         <= 4'd8;
                            data_bytes_left <= data_bytes_left - 16'd8;
                            in_word_ready   <= 1'b0;
                            state           <= S_DATA_W1_GET;
                        end
                    end else if (data_bytes_left > 16'd0) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w0_buf          <= (in_word & mask_lo(data_bytes_left[3:0]))
                                             | pad_word(data_bytes_left[3:0]);
                            w0_real         <= data_bytes_left[3:0];
                            data_bytes_left <= 16'd0;
                            data_pad_done   <= 1'b1;
                            in_word_ready   <= 1'b0;
                            state           <= S_DATA_W1_GET;
                        end
                    end else begin
                        if (!data_pad_done) begin
                            w0_buf        <= pad_word(4'd0);
                            w0_real       <= 4'd0;
                            data_pad_done <= 1'b1;
                        end else begin
                            w0_buf  <= 64'd0;
                            w0_real <= 4'd0;
                        end
                        state <= S_DATA_W1_GET;
                    end
                end

                S_DATA_W1_GET: begin
                    if (data_bytes_left >= 16'd8) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w1_buf          <= in_word;
                            w1_real         <= 4'd8;
                            data_bytes_left <= data_bytes_left - 16'd8;
                            in_word_ready   <= 1'b0;
                            state           <= S_DATA_EMIT_W0;
                        end
                    end else if (data_bytes_left > 16'd0) begin
                        in_word_ready <= 1'b1;
                        if (in_word_valid && in_word_ready) begin
                            w1_buf          <= (in_word & mask_lo(data_bytes_left[3:0]))
                                             | pad_word(data_bytes_left[3:0]);
                            w1_real         <= data_bytes_left[3:0];
                            data_bytes_left <= 16'd0;
                            data_pad_done   <= 1'b1;
                            in_word_ready   <= 1'b0;
                            state           <= S_DATA_EMIT_W0;
                        end
                    end else begin
                        if (!data_pad_done) begin
                            w1_buf        <= pad_word(4'd0);
                            w1_real       <= 4'd0;
                            data_pad_done <= 1'b1;
                        end else begin
                            w1_buf  <= 64'd0;
                            w1_real <= 4'd0;
                        end
                        state <= S_DATA_EMIT_W0;
                    end
                end

                S_DATA_EMIT_W0: begin
                    if (w0_real > 4'd0) begin
                        out_block      <= core_x0 ^ w0_buf;
                        out_valid      <= 1'b1;
                        out_byte_count <= w0_real;
                        out_last       <= (data_blocks_left == 12'd1) && (w1_real == 4'd0);
                    end
                    state <= S_DATA_EMIT_W1;
                end

                S_DATA_EMIT_W1: begin
                    if (w1_real > 4'd0) begin
                        out_block      <= core_x1 ^ w1_buf;
                        out_valid      <= 1'b1;
                        out_byte_count <= w1_real;
                        out_last       <= (data_blocks_left == 12'd1);
                    end
                    state <= S_DATA_PATCH_X0;
                end

                S_DATA_PATCH_X0: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_lane  <= LANE_X0;
                        if (is_decrypt_r) begin
                            patch_op   <= PATCH_LOAD;
                            patch_data <= (data_blocks_left == 12'd1) ? dec_last_x0 : w0_buf;
                        end else begin
                            patch_op   <= PATCH_XOR;
                            patch_data <= w0_buf;
                        end
                        state <= S_DATA_PATCH_X1;
                    end
                end

                S_DATA_PATCH_X1: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_lane  <= LANE_X1;
                        if (is_decrypt_r) begin
                            patch_op   <= PATCH_LOAD;
                            patch_data <= (data_blocks_left == 12'd1) ? dec_last_x1 : w1_buf;
                        end else begin
                            patch_op   <= PATCH_XOR;
                            patch_data <= w1_buf;
                        end

                        if (data_blocks_left == 12'd1) state <= S_FINAL_PATCH_X3;
                        else                           state <= S_DATA_PERM;
                    end
                end

                S_DATA_PERM: begin
                    perm_rounds <= 4'd8;
                    perm_start  <= 1'b1;
                    state       <= S_DATA_WAIT;
                end

                S_DATA_WAIT: begin
                    if (perm_done) begin
                        data_blocks_left <= data_blocks_left - 12'd1;
                        state            <= S_DATA_W0_GET;
                    end
                end

                S_FINAL_PATCH_X3: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X3;
                        patch_data  <= key_hi;
                        state       <= S_FINAL_PATCH_X2;
                    end
                end

                S_FINAL_PATCH_X2: begin
                    if (patch_ready) begin
                        patch_valid <= 1'b1;
                        patch_op    <= PATCH_XOR;
                        patch_lane  <= LANE_X2;
                        patch_data  <= key_lo;
                        state       <= S_FINAL_KICK;
                    end
                end

                S_FINAL_KICK: begin
                    perm_rounds <= 4'd12;
                    perm_start  <= 1'b1;
                    state       <= S_FINAL_WAIT;
                end

                S_FINAL_WAIT: begin
                    if (perm_done) begin
                        if (is_decrypt_r) state <= S_TAG_CMP_LO;
                        else              state <= S_TAG_EMIT_LO;
                    end
                end

                S_TAG_EMIT_LO: begin
                    out_block      <= core_x3 ^ key_lo;
                    out_valid      <= 1'b1;
                    out_last       <= 1'b0;
                    out_byte_count <= 4'd8;
                    state          <= S_TAG_EMIT_HI;
                end

                S_TAG_EMIT_HI: begin
                    out_block      <= core_x4 ^ key_hi;
                    out_valid      <= 1'b1;
                    out_last       <= 1'b1;
                    out_byte_count <= 4'd8;
                    state          <= S_FINISH;
                end

                S_TAG_CMP_LO: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        auth_ok       <= auth_ok & (in_word == (core_x3 ^ key_lo));
                        in_word_ready <= 1'b0;
                        state         <= S_TAG_CMP_HI;
                    end
                end

                S_TAG_CMP_HI: begin
                    in_word_ready <= 1'b1;
                    if (in_word_valid && in_word_ready) begin
                        auth_ok       <= auth_ok & (in_word == (core_x4 ^ key_hi));
                        in_word_ready <= 1'b0;
                        state         <= S_FINISH;
                    end
                end

                S_FINISH: begin
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

`default_nettype wire
