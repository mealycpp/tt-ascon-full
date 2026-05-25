`default_nettype none
/*
 * aead_patch_controller.v -- ASCON-AEAD128 controller for patch-fed sponge core.
 *
 * Streaming/dataflow version:
 *   - External interface is preserved.
 *   - Input words are pushed into small typed FIFOs.
 *   - The AEAD scheduler pulls from FIFOs and emits patch/permutation tokens.
 *   - Sponge readback is captured into local registers on perm_done.
 *   - Output words are pushed into an output FIFO.
 *
 * Goal: remove live in_word/core_x* fanout from the large AEAD control cone.
 */
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

    localparam I_KEY_LO    = 3'd0;
    localparam I_KEY_HI    = 3'd1;
    localparam I_NONCE_LO  = 3'd2;
    localparam I_NONCE_HI  = 3'd3;
    localparam I_AD        = 3'd4;
    localparam I_DATA      = 3'd5;
    localparam I_TAG       = 3'd6;
    localparam I_DONE      = 3'd7;

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
    reg [2:0]   ingress_phase;
    reg         is_decrypt_r;

    reg [63:0]  key_lo;
    reg [63:0]  key_hi;
    reg [63:0]  nonce_lo_tmp;
    reg [63:0]  nonce_hi_tmp;

    reg [63:0]  w0_buf;
    reg [63:0]  w1_buf;
    reg [3:0]   w0_real;
    reg [3:0]   w1_real;

    reg [11:0]  ad_blocks_left;
    reg [11:0]  data_blocks_left;
    reg [15:0]  ad_bytes_left;
    reg [15:0]  data_bytes_left;
    reg [12:0]  ad_input_words_left;
    reg [12:0]  data_input_words_left;
    reg [1:0]   tag_input_words_left;
    reg         ad_pad_done;
    reg         data_pad_done;

    // Registered sponge readback. Controllers never consume live core_x*.
    reg [63:0]  rb_x0;
    reg [63:0]  rb_x1;
    reg [63:0]  rb_x2;
    reg [63:0]  rb_x3;
    reg [63:0]  rb_x4;

    wire _unused = &{in_phase, in_word_last, in_word_bytes, rb_x2, core_x2, 1'b0};

    function [12:0] ceil_words8;
        input [15:0] nbytes;
        begin
            ceil_words8 = {1'b0, nbytes[15:3]} + ((nbytes[2:0] != 3'd0) ? 13'd1 : 13'd0);
        end
    endfunction

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
        (w0_real == 4'd8) ? w0_buf : ((rb_x0 & ~mask_lo(w0_real)) ^ w0_buf);
    wire [63:0] dec_last_x1 =
        (w1_real == 4'd8) ? w1_buf : ((rb_x1 & ~mask_lo(w1_real)) ^ w1_buf);

    wire fifo_clear = reset_engine | !busy;

    wire cfg_full;
    wire cfg_empty;
    wire [63:0] cfg_dout;
    reg  cfg_pop;

    wire ad_full  = cfg_full;
    wire ad_empty = cfg_empty;
    wire [63:0] ad_dout = cfg_dout;
    reg  ad_pop;

    wire msg_full;
    wire msg_empty;
    wire [63:0] msg_dout;
    reg  msg_pop;

    wire tag_full  = cfg_full;
    wire tag_empty = cfg_empty;
    wire [63:0] tag_dout = cfg_dout;
    reg  tag_pop;

    wire cfg_stream_pop = cfg_pop | ad_pop | tag_pop;

    wire out_fifo_full;
    wire out_fifo_empty;
    wire [68:0] out_fifo_dout;
    reg  out_fifo_push;
    reg  [68:0] out_fifo_din;
    wire out_fifo_pop = !out_fifo_empty;

    wire in_fire = in_word_valid & in_word_ready;

    wire cfg_push_premerge =
        in_fire && ((ingress_phase == I_KEY_LO)   ||
                    (ingress_phase == I_KEY_HI)   ||
                    (ingress_phase == I_NONCE_LO) ||
                    (ingress_phase == I_NONCE_HI));
    wire cfg_push =
        cfg_push_premerge ||
        (in_fire && (ingress_phase == I_AD)) ||
        (in_fire && (ingress_phase == I_TAG));
    wire ad_push   = 1'b0;
    wire msg_push  = in_fire && (ingress_phase == I_DATA);
    wire tag_push  = 1'b0;

    aead_stream_fifo #(.WIDTH(64), .DEPTH_LOG2(2)) u_cfg_fifo (
        .clk(clk), .rst_n(rst_n), .clear(fifo_clear),
        .push(cfg_push), .pop(cfg_stream_pop), .din(in_word), .dout(cfg_dout),
        .full(cfg_full), .empty(cfg_empty)
    );


    aead_stream_fifo #(.WIDTH(64), .DEPTH_LOG2(1)) u_msg_fifo (
        .clk(clk), .rst_n(rst_n), .clear(fifo_clear),
        .push(msg_push), .pop(msg_pop), .din(in_word), .dout(msg_dout),
        .full(msg_full), .empty(msg_empty)
    );


    aead_stream_fifo #(.WIDTH(69), .DEPTH_LOG2(1)) u_out_fifo (
        .clk(clk), .rst_n(rst_n), .clear(fifo_clear),
        .push(out_fifo_push), .pop(out_fifo_pop), .din(out_fifo_din), .dout(out_fifo_dout),
        .full(out_fifo_full), .empty(out_fifo_empty)
    );

    // Input push side: accept serial stream into typed FIFOs.
    always @(*) begin
        in_word_ready = 1'b0;

        if (busy && !reset_engine) begin
            case (ingress_phase)
                I_KEY_LO,
                I_KEY_HI,
                I_NONCE_LO,
                I_NONCE_HI: begin
                    in_word_ready = !cfg_full;
                end

                I_AD: begin
                    in_word_ready = (ad_input_words_left != 13'd0) && !ad_full;
                end

                I_DATA: begin
                    in_word_ready = (data_input_words_left != 13'd0) && !msg_full;
                end

                I_TAG: begin
                    in_word_ready = (tag_input_words_left != 2'd0) && !tag_full;
                end

                default: begin
                    in_word_ready = 1'b0;
                end
            endcase
        end
    end

    // Output pull side: no external ready exists, so drain one FIFO word per cycle.
    always @(*) begin
        out_valid      = !out_fifo_empty;
        out_last       = out_fifo_dout[68];
        out_byte_count = out_fifo_dout[67:64];
        out_block      = out_fifo_dout[63:0];
    end

    // Controller combinational token generation.
    always @(*) begin
        cfg_pop       = 1'b0;
        ad_pop        = 1'b0;
        msg_pop       = 1'b0;
        tag_pop       = 1'b0;

        out_fifo_push = 1'b0;
        out_fifo_din  = 69'd0;

        patch_valid   = 1'b0;
        patch_op      = PATCH_CLEAR;
        patch_lane    = LANE_X0;
        patch_data    = 64'd0;

        perm_start    = 1'b0;
        perm_rounds   = 4'd12;

        case (state)
            S_KEY_PULL_LO,
            S_KEY_PULL_HI,
            S_NONCE_PULL_LO,
            S_NONCE_PULL_HI: begin
                cfg_pop = !cfg_empty;
            end

            S_CLEAR: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_CLEAR;
                patch_lane  = LANE_X0;
                patch_data  = 64'd0;
            end

            S_LOAD_X0_IV: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_LOAD;
                patch_lane  = LANE_X0;
                patch_data  = AEAD_IV;
            end

            S_LOAD_X1_KEYLO: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_LOAD;
                patch_lane  = LANE_X1;
                patch_data  = key_lo;
            end

            S_LOAD_X2_KEYHI: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_LOAD;
                patch_lane  = LANE_X2;
                patch_data  = key_hi;
            end

            S_LOAD_X3_NONCELO: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_LOAD;
                patch_lane  = LANE_X3;
                patch_data  = nonce_lo_tmp;
            end

            S_LOAD_X4_NONCEHI: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_LOAD;
                patch_lane  = LANE_X4;
                patch_data  = nonce_hi_tmp;
            end

            S_INIT_KICK: begin
                if (!perm_busy) begin
                    perm_start  = 1'b1;
                    perm_rounds = 4'd12;
                end
            end

            S_INIT_X4_KEYHI: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_XOR;
                patch_lane  = LANE_X4;
                patch_data  = key_hi;
            end

            S_INIT_X3_KEYLO: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_XOR;
                patch_lane  = LANE_X3;
                patch_data  = key_lo;
            end

            S_AD_W0_GET: begin
                if (ad_bytes_left >= 16'd8) begin
                    ad_pop = !ad_empty;
                end else if (ad_bytes_left > 16'd0) begin
                    ad_pop = !ad_empty;
                end
            end

            S_AD_W1_GET: begin
                if (ad_bytes_left >= 16'd8) begin
                    ad_pop = !ad_empty;
                end else if (ad_bytes_left > 16'd0) begin
                    ad_pop = !ad_empty;
                end
            end

            S_AD_PATCH_X0: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_XOR;
                patch_lane  = LANE_X0;
                patch_data  = w0_buf;
            end

            S_AD_PATCH_X1: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_XOR;
                patch_lane  = LANE_X1;
                patch_data  = w1_buf;
            end

            S_AD_PERM: begin
                if (!perm_busy) begin
                    perm_start  = 1'b1;
                    perm_rounds = 4'd8;
                end
            end

            S_AD_DOMSEP: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_XOR;
                patch_lane  = LANE_X4;
                patch_data  = 64'h8000_0000_0000_0000;
            end

            S_DATA_W0_GET: begin
                if (data_bytes_left >= 16'd8) begin
                    msg_pop = !msg_empty;
                end else if (data_bytes_left > 16'd0) begin
                    msg_pop = !msg_empty;
                end
            end

            S_DATA_W1_GET: begin
                if (data_bytes_left >= 16'd8) begin
                    msg_pop = !msg_empty;
                end else if (data_bytes_left > 16'd0) begin
                    msg_pop = !msg_empty;
                end
            end

            S_DATA_EMIT_W0: begin
                if ((w0_real != 4'd0) && !out_fifo_full) begin
                    out_fifo_push = 1'b1;
                    out_fifo_din  = {(data_blocks_left == 12'd1) && (w1_real == 4'd0),
                                     w0_real,
                                     (rb_x0 ^ w0_buf)};
                end
            end

            S_DATA_EMIT_W1: begin
                if ((w1_real != 4'd0) && !out_fifo_full) begin
                    out_fifo_push = 1'b1;
                    out_fifo_din  = {(data_blocks_left == 12'd1),
                                     w1_real,
                                     (rb_x1 ^ w1_buf)};
                end
            end

            S_DATA_PATCH_X0: begin
                patch_valid = 1'b1;
                patch_lane  = LANE_X0;
                if (is_decrypt_r) begin
                    patch_op   = PATCH_LOAD;
                    patch_data = (data_blocks_left == 12'd1) ? dec_last_x0 : w0_buf;
                end else begin
                    patch_op   = PATCH_XOR;
                    patch_data = w0_buf;
                end
            end

            S_DATA_PATCH_X1: begin
                patch_valid = 1'b1;
                patch_lane  = LANE_X1;
                if (is_decrypt_r) begin
                    patch_op   = PATCH_LOAD;
                    patch_data = (data_blocks_left == 12'd1) ? dec_last_x1 : w1_buf;
                end else begin
                    patch_op   = PATCH_XOR;
                    patch_data = w1_buf;
                end
            end

            S_DATA_PERM: begin
                if (!perm_busy) begin
                    perm_start  = 1'b1;
                    perm_rounds = 4'd8;
                end
            end

            S_FINAL_PATCH_X3: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_XOR;
                patch_lane  = LANE_X3;
                patch_data  = key_hi;
            end

            S_FINAL_PATCH_X2: begin
                patch_valid = 1'b1;
                patch_op    = PATCH_XOR;
                patch_lane  = LANE_X2;
                patch_data  = key_lo;
            end

            S_FINAL_KICK: begin
                if (!perm_busy) begin
                    perm_start  = 1'b1;
                    perm_rounds = 4'd12;
                end
            end

            S_TAG_EMIT_LO: begin
                if (!out_fifo_full) begin
                    out_fifo_push = 1'b1;
                    out_fifo_din  = {1'b0, 4'd8, (rb_x3 ^ key_lo)};
                end
            end

            S_TAG_EMIT_HI: begin
                if (!out_fifo_full) begin
                    out_fifo_push = 1'b1;
                    out_fifo_din  = {1'b1, 4'd8, (rb_x4 ^ key_hi)};
                end
            end

            S_TAG_CMP_LO,
            S_TAG_CMP_HI: begin
                tag_pop = !tag_empty;
            end

            default: begin
            end
        endcase
    end

    // Main sequential control.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                 <= S_IDLE;
            ingress_phase         <= I_DONE;
            is_decrypt_r          <= 1'b0;

            key_lo                <= 64'd0;
            key_hi                <= 64'd0;
            nonce_lo_tmp          <= 64'd0;
            nonce_hi_tmp          <= 64'd0;
            w0_buf                <= 64'd0;
            w1_buf                <= 64'd0;
            w0_real               <= 4'd0;
            w1_real               <= 4'd0;

            ad_blocks_left        <= 12'd0;
            data_blocks_left      <= 12'd0;
            ad_bytes_left         <= 16'd0;
            data_bytes_left       <= 16'd0;
            ad_input_words_left   <= 13'd0;
            data_input_words_left <= 13'd0;
            tag_input_words_left  <= 2'd0;
            ad_pad_done           <= 1'b0;
            data_pad_done         <= 1'b0;

            rb_x0                 <= 64'd0;
            rb_x1                 <= 64'd0;
            rb_x2                 <= 64'd0;
            rb_x3                 <= 64'd0;
            rb_x4                 <= 64'd0;

            auth_ok               <= 1'b0;
            busy                  <= 1'b0;
            done                  <= 1'b0;
        end else if (reset_engine) begin
            state                 <= S_IDLE;
            ingress_phase         <= I_DONE;
            is_decrypt_r          <= 1'b0;

            key_lo                <= 64'd0;
            key_hi                <= 64'd0;
            nonce_lo_tmp          <= 64'd0;
            nonce_hi_tmp          <= 64'd0;
            w0_buf                <= 64'd0;
            w1_buf                <= 64'd0;
            w0_real               <= 4'd0;
            w1_real               <= 4'd0;

            ad_blocks_left        <= 12'd0;
            data_blocks_left      <= 12'd0;
            ad_bytes_left         <= 16'd0;
            data_bytes_left       <= 16'd0;
            ad_input_words_left   <= 13'd0;
            data_input_words_left <= 13'd0;
            tag_input_words_left  <= 2'd0;
            ad_pad_done           <= 1'b0;
            data_pad_done         <= 1'b0;

            rb_x0                 <= 64'd0;
            rb_x1                 <= 64'd0;
            rb_x2                 <= 64'd0;
            rb_x3                 <= 64'd0;
            rb_x4                 <= 64'd0;

            auth_ok               <= 1'b0;
            busy                  <= 1'b0;
            done                  <= 1'b0;
        end else begin
            done <= 1'b0;

            if (perm_done) begin
                rb_x0 <= core_x0;
                rb_x1 <= core_x1;
                rb_x2 <= core_x2;
                rb_x3 <= core_x3;
                rb_x4 <= core_x4;
            end

            if (!busy && start) begin
                state                 <= S_KEY_PULL_LO;
                ingress_phase         <= I_KEY_LO;
                is_decrypt_r          <= is_decrypt;

                ad_blocks_left        <= (ad_total_bytes == 16'd0) ? 12'd0
                                         : (ad_total_bytes[15:4] + 12'd1);
                data_blocks_left      <= data_total_bytes[15:4] + 12'd1;
                ad_bytes_left         <= ad_total_bytes;
                data_bytes_left       <= data_total_bytes;
                ad_input_words_left   <= ceil_words8(ad_total_bytes);
                data_input_words_left <= ceil_words8(data_total_bytes);
                tag_input_words_left  <= is_decrypt ? 2'd2 : 2'd0;
                ad_pad_done           <= 1'b0;
                data_pad_done         <= 1'b0;

                auth_ok               <= 1'b1;
                busy                  <= 1'b1;
            end

            // Input ingress phase advancement.
            if (busy && in_fire) begin
                case (ingress_phase)
                    I_KEY_LO: begin
                        ingress_phase <= I_KEY_HI;
                    end

                    I_KEY_HI: begin
                        ingress_phase <= I_NONCE_LO;
                    end

                    I_NONCE_LO: begin
                        ingress_phase <= I_NONCE_HI;
                    end

                    I_NONCE_HI: begin
                        if (ad_input_words_left != 13'd0) begin
                            ingress_phase <= I_AD;
                        end else if (data_input_words_left != 13'd0) begin
                            ingress_phase <= I_DATA;
                        end else if (is_decrypt_r) begin
                            ingress_phase <= I_TAG;
                        end else begin
                            ingress_phase <= I_DONE;
                        end
                    end

                    I_AD: begin
                        if (ad_input_words_left != 13'd0) begin
                            ad_input_words_left <= ad_input_words_left - 13'd1;
                            if (ad_input_words_left == 13'd1) begin
                                if (data_input_words_left != 13'd0) begin
                                    ingress_phase <= I_DATA;
                                end else if (is_decrypt_r) begin
                                    ingress_phase <= I_TAG;
                                end else begin
                                    ingress_phase <= I_DONE;
                                end
                            end
                        end
                    end

                    I_DATA: begin
                        if (data_input_words_left != 13'd0) begin
                            data_input_words_left <= data_input_words_left - 13'd1;
                            if (data_input_words_left == 13'd1) begin
                                if (is_decrypt_r) begin
                                    ingress_phase <= I_TAG;
                                end else begin
                                    ingress_phase <= I_DONE;
                                end
                            end
                        end
                    end

                    I_TAG: begin
                        if (tag_input_words_left != 2'd0) begin
                            tag_input_words_left <= tag_input_words_left - 2'd1;
                            if (tag_input_words_left == 2'd1) begin
                                ingress_phase <= I_DONE;
                            end
                        end
                    end

                    default: begin
                        ingress_phase <= I_DONE;
                    end
                endcase
            end

            // Scheduler/control side.
            if (busy) begin
                case (state)
                    S_KEY_PULL_LO: begin
                        if (cfg_pop) begin
                            key_lo <= cfg_dout;
                            state  <= S_KEY_PULL_HI;
                        end
                    end

                    S_KEY_PULL_HI: begin
                        if (cfg_pop) begin
                            key_hi <= cfg_dout;
                            state  <= S_NONCE_PULL_LO;
                        end
                    end

                    S_NONCE_PULL_LO: begin
                        if (cfg_pop) begin
                            nonce_lo_tmp <= cfg_dout;
                            state        <= S_NONCE_PULL_HI;
                        end
                    end

                    S_NONCE_PULL_HI: begin
                        if (cfg_pop) begin
                            nonce_hi_tmp <= cfg_dout;
                            state        <= S_CLEAR;
                        end
                    end

                    S_CLEAR: begin
                        if (patch_ready) state <= S_LOAD_X0_IV;
                    end

                    S_LOAD_X0_IV: begin
                        if (patch_ready) state <= S_LOAD_X1_KEYLO;
                    end

                    S_LOAD_X1_KEYLO: begin
                        if (patch_ready) state <= S_LOAD_X2_KEYHI;
                    end

                    S_LOAD_X2_KEYHI: begin
                        if (patch_ready) state <= S_LOAD_X3_NONCELO;
                    end

                    S_LOAD_X3_NONCELO: begin
                        if (patch_ready) state <= S_LOAD_X4_NONCEHI;
                    end

                    S_LOAD_X4_NONCEHI: begin
                        if (patch_ready) state <= S_INIT_KICK;
                    end

                    S_INIT_KICK: begin
                        if (!perm_busy) state <= S_INIT_WAIT;
                    end

                    S_INIT_WAIT: begin
                        if (perm_done) state <= S_INIT_X4_KEYHI;
                    end

                    S_INIT_X4_KEYHI: begin
                        if (patch_ready) state <= S_INIT_X3_KEYLO;
                    end

                    S_INIT_X3_KEYLO: begin
                        if (patch_ready) begin
                            if (ad_blocks_left == 12'd0) state <= S_AD_DOMSEP;
                            else                         state <= S_AD_W0_GET;
                        end
                    end

                    S_AD_W0_GET: begin
                        if (ad_bytes_left >= 16'd8) begin
                            if (ad_pop) begin
                                w0_buf        <= ad_dout;
                                w0_real       <= 4'd8;
                                ad_bytes_left <= ad_bytes_left - 16'd8;
                                state         <= S_AD_W1_GET;
                            end
                        end else if (ad_bytes_left > 16'd0) begin
                            if (ad_pop) begin
                                w0_buf        <= (ad_dout & mask_lo(ad_bytes_left[3:0]))
                                               | pad_word(ad_bytes_left[3:0]);
                                w0_real       <= ad_bytes_left[3:0];
                                ad_bytes_left <= 16'd0;
                                ad_pad_done   <= 1'b1;
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
                            if (ad_pop) begin
                                w1_buf        <= ad_dout;
                                w1_real       <= 4'd8;
                                ad_bytes_left <= ad_bytes_left - 16'd8;
                                state         <= S_AD_PATCH_X0;
                            end
                        end else if (ad_bytes_left > 16'd0) begin
                            if (ad_pop) begin
                                w1_buf        <= (ad_dout & mask_lo(ad_bytes_left[3:0]))
                                               | pad_word(ad_bytes_left[3:0]);
                                w1_real       <= ad_bytes_left[3:0];
                                ad_bytes_left <= 16'd0;
                                ad_pad_done   <= 1'b1;
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
                        if (patch_ready) state <= S_AD_PATCH_X1;
                    end

                    S_AD_PATCH_X1: begin
                        if (patch_ready) state <= S_AD_PERM;
                    end

                    S_AD_PERM: begin
                        if (!perm_busy) state <= S_AD_WAIT;
                    end

                    S_AD_WAIT: begin
                        if (perm_done) begin
                            ad_blocks_left <= ad_blocks_left - 12'd1;
                            if (ad_blocks_left == 12'd1) state <= S_AD_DOMSEP;
                            else                         state <= S_AD_W0_GET;
                        end
                    end

                    S_AD_DOMSEP: begin
                        if (patch_ready) state <= S_DATA_W0_GET;
                    end

                    S_DATA_W0_GET: begin
                        if (data_bytes_left >= 16'd8) begin
                            if (msg_pop) begin
                                w0_buf          <= msg_dout;
                                w0_real         <= 4'd8;
                                data_bytes_left <= data_bytes_left - 16'd8;
                                state           <= S_DATA_W1_GET;
                            end
                        end else if (data_bytes_left > 16'd0) begin
                            if (msg_pop) begin
                                w0_buf          <= (msg_dout & mask_lo(data_bytes_left[3:0]))
                                                 | pad_word(data_bytes_left[3:0]);
                                w0_real         <= data_bytes_left[3:0];
                                data_bytes_left <= 16'd0;
                                data_pad_done   <= 1'b1;
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
                            if (msg_pop) begin
                                w1_buf          <= msg_dout;
                                w1_real         <= 4'd8;
                                data_bytes_left <= data_bytes_left - 16'd8;
                                state           <= S_DATA_EMIT_W0;
                            end
                        end else if (data_bytes_left > 16'd0) begin
                            if (msg_pop) begin
                                w1_buf          <= (msg_dout & mask_lo(data_bytes_left[3:0]))
                                                 | pad_word(data_bytes_left[3:0]);
                                w1_real         <= data_bytes_left[3:0];
                                data_bytes_left <= 16'd0;
                                data_pad_done   <= 1'b1;
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
                        if (w0_real == 4'd0) begin
                            state <= S_DATA_EMIT_W1;
                        end else if (!out_fifo_full) begin
                            state <= S_DATA_EMIT_W1;
                        end
                    end

                    S_DATA_EMIT_W1: begin
                        if (w1_real == 4'd0) begin
                            state <= S_DATA_PATCH_X0;
                        end else if (!out_fifo_full) begin
                            state <= S_DATA_PATCH_X0;
                        end
                    end

                    S_DATA_PATCH_X0: begin
                        if (patch_ready) state <= S_DATA_PATCH_X1;
                    end

                    S_DATA_PATCH_X1: begin
                        if (patch_ready) begin
                            if (data_blocks_left == 12'd1) state <= S_FINAL_PATCH_X3;
                            else                           state <= S_DATA_PERM;
                        end
                    end

                    S_DATA_PERM: begin
                        if (!perm_busy) state <= S_DATA_WAIT;
                    end

                    S_DATA_WAIT: begin
                        if (perm_done) begin
                            data_blocks_left <= data_blocks_left - 12'd1;
                            state            <= S_DATA_W0_GET;
                        end
                    end

                    S_FINAL_PATCH_X3: begin
                        if (patch_ready) state <= S_FINAL_PATCH_X2;
                    end

                    S_FINAL_PATCH_X2: begin
                        if (patch_ready) state <= S_FINAL_KICK;
                    end

                    S_FINAL_KICK: begin
                        if (!perm_busy) state <= S_FINAL_WAIT;
                    end

                    S_FINAL_WAIT: begin
                        if (perm_done) begin
                            if (is_decrypt_r) state <= S_TAG_CMP_LO;
                            else              state <= S_TAG_EMIT_LO;
                        end
                    end

                    S_TAG_EMIT_LO: begin
                        if (!out_fifo_full) state <= S_TAG_EMIT_HI;
                    end

                    S_TAG_EMIT_HI: begin
                        if (!out_fifo_full) state <= S_FINISH;
                    end

                    S_TAG_CMP_LO: begin
                        if (tag_pop) begin
                            auth_ok <= auth_ok & (tag_dout == (rb_x3 ^ key_lo));
                            state   <= S_TAG_CMP_HI;
                        end
                    end

                    S_TAG_CMP_HI: begin
                        if (tag_pop) begin
                            auth_ok <= auth_ok & (tag_dout == (rb_x4 ^ key_hi));
                            state   <= S_FINISH;
                        end
                    end

                    S_FINISH: begin
                        done          <= 1'b1;
                        busy          <= 1'b0;
                        state         <= S_IDLE;
                        ingress_phase <= I_DONE;
                    end

                    default: begin
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end

endmodule


module aead_stream_fifo #(
    parameter WIDTH = 64,
    parameter DEPTH_LOG2 = 2
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             clear,
    input  wire             push,
    input  wire             pop,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout,
    output wire             full,
    output wire             empty
);
    localparam integer DEPTH = (1 << DEPTH_LOG2);
    localparam [DEPTH_LOG2:0] DEPTH_COUNT = (1 << DEPTH_LOG2);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [DEPTH_LOG2-1:0] rd_ptr;
    reg [DEPTH_LOG2-1:0] wr_ptr;
    reg [DEPTH_LOG2:0]   count;

    wire do_pop  = pop  && (count != {DEPTH_LOG2+1{1'b0}});
    wire do_push = push && (count != DEPTH_COUNT);

    assign empty = (count == {DEPTH_LOG2+1{1'b0}});
    assign full  = (count == DEPTH_COUNT);
    assign dout  = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= {DEPTH_LOG2{1'b0}};
            wr_ptr <= {DEPTH_LOG2{1'b0}};
            count  <= {DEPTH_LOG2+1{1'b0}};
        end else if (clear) begin
            rd_ptr <= {DEPTH_LOG2{1'b0}};
            wr_ptr <= {DEPTH_LOG2{1'b0}};
            count  <= {DEPTH_LOG2+1{1'b0}};
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= wr_ptr + {{(DEPTH_LOG2-1){1'b0}}, 1'b1};
            end

            if (do_pop) begin
                rd_ptr <= rd_ptr + {{(DEPTH_LOG2-1){1'b0}}, 1'b1};
            end

            case ({do_push, do_pop})
                2'b10: count <= count + {{DEPTH_LOG2{1'b0}}, 1'b1};
                2'b01: count <= count - {{DEPTH_LOG2{1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end

endmodule

`default_nettype wire
