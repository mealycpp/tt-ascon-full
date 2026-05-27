`default_nettype none

`include "sdmc_stream_defs.vh"
`include "sdmc_crypto_defs.vh"

module sdmc_aead128_core (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire                     start,
    input  wire                     is_decrypt,
    input  wire [15:0]              ad_len,
    input  wire [15:0]              data_len,

    input  wire [`SDMC_TOKEN_W-1:0] in_token,
    input  wire                     in_empty,
    output reg                      in_pop,

    output reg  [`SDMC_TOKEN_W-1:0] out_token,
    output reg                      out_push,
    input  wire                     out_full,

    output reg                      busy,
    output reg                      done,
    output reg                      error,
    output reg                      auth_ok
);

    localparam S_IDLE        = 6'd0;
    localparam S_KEY0        = 6'd1;
    localparam S_KEY1        = 6'd2;
    localparam S_NONCE0      = 6'd3;
    localparam S_NONCE1      = 6'd4;

    localparam S_LOAD_X0     = 6'd5;
    localparam S_LOAD_X1     = 6'd6;
    localparam S_LOAD_X2     = 6'd7;
    localparam S_LOAD_X3     = 6'd8;
    localparam S_LOAD_X4     = 6'd9;

    localparam S_INIT_START  = 6'd10;
    localparam S_INIT_WAIT   = 6'd11;

    localparam S_INIT_X3     = 6'd12;
    localparam S_INIT_X4_DOM = 6'd13;
    localparam S_DATA_PAD    = 6'd14;
    localparam S_FINAL_X2    = 6'd15;
    localparam S_FINAL_X3    = 6'd16;

    localparam S_FINAL_START = 6'd17;
    localparam S_FINAL_WAIT  = 6'd18;

    localparam S_TAG0        = 6'd19;
    localparam S_TAG1        = 6'd20;
    localparam S_DONE        = 6'd21;
    localparam S_ERR         = 6'd22;
    localparam S_MSG_WAIT    = 6'd23;
    localparam S_MSG_ABSORB  = 6'd24;
    localparam S_MSG_EMIT    = 6'd25;
    localparam S_TAGIN0      = 6'd26;
    localparam S_TAGIN1      = 6'd27;
    localparam S_WAIT_KEY1   = 6'd28;
    localparam S_WAIT_NONCE0 = 6'd29;
    localparam S_WAIT_NONCE1 = 6'd30;
    localparam S_WAIT_MSG    = 6'd31;
    localparam S_WAIT_TAG1   = 6'd32;
    localparam S_AD_DOMSEP    = 6'd38;
    localparam S_AD_PAD_X1  = 6'd39;
    localparam S_MSG_PAD_X1 = 6'd40;
    localparam S_AD_WAIT     = 6'd33;
    localparam S_WAIT_AD     = 6'd34;
    localparam S_AD_ABSORB   = 6'd35;
    localparam S_AD_P8_START = 6'd36;
    localparam S_AD_P8_WAIT  = 6'd37;

    reg [5:0] state;

    reg [63:0] key0_q;
    reg [63:0] key1_q;
    reg [63:0] nonce0_q;
    reg [63:0] nonce1_q;
    reg [63:0] msg_word_q;
    reg [3:0]  msg_bytes_q;
    reg [63:0] ct_word_q;
    reg [63:0] ad_word_q;
    reg [3:0]  ad_bytes_q;

    wire        tok_last  = in_token[`SDMC_TOKEN_LAST_BIT];
    wire [3:0]  tok_kind  = in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
    wire [3:0]  tok_bytes = in_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
    wire [63:0] tok_data  = in_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

    function [63:0] mask_n;
        input [3:0] n;
        begin
            case (n[2:0])
                3'd0: mask_n = 64'h0000_0000_0000_0000;
                3'd1: mask_n = 64'h0000_0000_0000_00FF;
                3'd2: mask_n = 64'h0000_0000_0000_FFFF;
                3'd3: mask_n = 64'h0000_0000_00FF_FFFF;
                3'd4: mask_n = 64'h0000_0000_FFFF_FFFF;
                3'd5: mask_n = 64'h0000_00FF_FFFF_FFFF;
                3'd6: mask_n = 64'h0000_FFFF_FFFF_FFFF;
                3'd7: mask_n = 64'h00FF_FFFF_FFFF_FFFF;
                default: mask_n = 64'h0000_0000_0000_0000;
            endcase
        end
    endfunction

    function [63:0] pad_n;
        input [3:0] n;
        begin
            case (n[2:0])
                3'd0: pad_n = 64'h0000_0000_0000_0001;
                3'd1: pad_n = 64'h0000_0000_0000_0100;
                3'd2: pad_n = 64'h0000_0000_0001_0000;
                3'd3: pad_n = 64'h0000_0000_0100_0000;
                3'd4: pad_n = 64'h0000_0001_0000_0000;
                3'd5: pad_n = 64'h0000_0100_0000_0000;
                3'd6: pad_n = 64'h0001_0000_0000_0000;
                3'd7: pad_n = 64'h0100_0000_0000_0000;
                default: pad_n = 64'h0000_0000_0000_0001;
            endcase
        end
    endfunction

    reg        perm_wr_en;
    reg [2:0]  perm_wr_lane;
    reg [63:0] perm_wr_data;

    reg        perm_rd_en;
    reg [2:0]  perm_rd_lane;
    wire [63:0] perm_rd_data;
    wire        perm_rd_valid;

    reg        perm_start;
    reg [3:0]  perm_rounds_q;
    wire       perm_ready;
    wire       perm_busy;
    wire       perm_done;

    wire [63:0] p0;
    wire [63:0] p1;
    wire [63:0] p2;
    wire [63:0] p3;
    wire [63:0] p4;

    sdmc_ascon_perm_unit64 u_perm (
        .clk           (clk),
        .rst_n         (rst_n),
        .clear         (clear),

        .host_wr_en    (perm_wr_en),
        .host_wr_lane  (perm_wr_lane),
        .host_wr_data  (perm_wr_data),

        .host_rd_en    (perm_rd_en),
        .host_rd_lane  (perm_rd_lane),
        .host_rd_data  (perm_rd_data),
        .host_rd_valid (perm_rd_valid),

        .start         (perm_start),
        .rounds        (perm_rounds_q),

        .host_ready    (perm_ready),
        .busy          (perm_busy),
        .done          (perm_done),

        .x0            (p0),
        .x1            (p1),
        .x2            (p2),
        .x3            (p3),
        .x4            (p4)
    );

    wire _unused = &{perm_busy, perm_rd_data, perm_rd_valid, perm_rd_lane,
                     tok_last, p1, 1'b0};

    task set_wr;
        input [2:0] lane;
        input [63:0] data;
        begin
            perm_wr_en   <= 1'b1;
            perm_wr_lane <= lane;
            perm_wr_data <= data;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            key0_q       <= 64'd0;
            key1_q       <= 64'd0;
            nonce0_q     <= 64'd0;
            nonce1_q     <= 64'd0;
            msg_word_q   <= 64'd0;
            msg_bytes_q  <= 4'd0;
            ct_word_q    <= 64'd0;
            ad_word_q    <= 64'd0;
            ad_bytes_q   <= 4'd0;

            in_pop       <= 1'b0;

            perm_wr_en   <= 1'b0;
            perm_wr_lane <= 3'd0;
            perm_wr_data <= 64'd0;
            perm_rd_en   <= 1'b0;
            perm_rd_lane <= 3'd0;
            perm_start   <= 1'b0;
            perm_rounds_q <= 4'd12;

            out_token    <= {`SDMC_TOKEN_W{1'b0}};
            out_push     <= 1'b0;

            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            auth_ok      <= 1'b0;
        end else if (clear) begin
            state        <= S_IDLE;
            key0_q       <= 64'd0;
            key1_q       <= 64'd0;
            nonce0_q     <= 64'd0;
            nonce1_q     <= 64'd0;
            msg_word_q   <= 64'd0;
            msg_bytes_q  <= 4'd0;
            ct_word_q    <= 64'd0;
            ad_word_q    <= 64'd0;
            ad_bytes_q   <= 4'd0;

            in_pop       <= 1'b0;

            perm_wr_en   <= 1'b0;
            perm_wr_lane <= 3'd0;
            perm_wr_data <= 64'd0;
            perm_rd_en   <= 1'b0;
            perm_rd_lane <= 3'd0;
            perm_start   <= 1'b0;
            perm_rounds_q <= 4'd12;

            out_token    <= {`SDMC_TOKEN_W{1'b0}};
            out_push     <= 1'b0;

            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            auth_ok      <= 1'b0;
        end else begin
            in_pop     <= 1'b0;
            perm_wr_en <= 1'b0;
            perm_rd_en <= 1'b0;
            perm_start <= 1'b0;
            out_push   <= 1'b0;
            done       <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy    <= 1'b0;
                    error   <= 1'b0;

                    if (start) begin
                        auth_ok <= is_decrypt ? 1'b1 : 1'b0;
                        // This first clean milestone supports only AEAD encrypt
                        // with empty AD and empty plaintext.
                        if (ad_len > 16'd8 || data_len > 16'd8) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            busy  <= 1'b1;
                            state <= S_KEY0;
                        end
                    end
                end

                S_KEY0: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_KEY || tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            key0_q <= tok_data;
                            in_pop <= 1'b1;
                            state  <= S_WAIT_KEY1;
                        end
                    end
                end

                S_WAIT_KEY1: begin
                    state <= S_KEY1;
                end

                S_KEY1: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_KEY || tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            key1_q <= tok_data;
                            in_pop <= 1'b1;
                            state  <= S_WAIT_NONCE0;
                        end
                    end
                end

                S_WAIT_NONCE0: begin
                    state <= S_NONCE0;
                end

                S_NONCE0: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_NONCE || tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            nonce0_q <= tok_data;
                            in_pop   <= 1'b1;
                            state    <= S_WAIT_NONCE1;
                        end
                    end
                end

                S_WAIT_NONCE1: begin
                    state <= S_NONCE1;
                end

                S_NONCE1: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_NONCE || tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            nonce1_q <= tok_data;
                            in_pop   <= 1'b1;
                            state    <= S_LOAD_X0;
                        end
                    end
                end

                S_LOAD_X0: begin
                    if (perm_ready) begin
                        set_wr(3'd0, `SDMC_AEAD128_IV);
                        state <= S_LOAD_X1;
                    end
                end

                S_LOAD_X1: begin
                    if (perm_ready) begin
                        set_wr(3'd1, key0_q);
                        state <= S_LOAD_X2;
                    end
                end

                S_LOAD_X2: begin
                    if (perm_ready) begin
                        set_wr(3'd2, key1_q);
                        state <= S_LOAD_X3;
                    end
                end

                S_LOAD_X3: begin
                    if (perm_ready) begin
                        set_wr(3'd3, nonce0_q);
                        state <= S_LOAD_X4;
                    end
                end

                S_LOAD_X4: begin
                    if (perm_ready) begin
                        set_wr(3'd4, nonce1_q);
                        state <= S_INIT_START;
                    end
                end

                S_INIT_START: begin
                    if (perm_ready) begin
                        perm_rounds_q <= 4'd12;
                        perm_start    <= 1'b1;
                        state         <= S_INIT_WAIT;
                    end
                end

                S_INIT_WAIT: begin
                    if (perm_done) begin
                        state <= S_INIT_X3;
                    end
                end

                // After initial p12:
                // x3 ^= K0, x4 ^= K1, then domain separation x4 ^= 1.
                S_INIT_X3: begin
                    if (perm_ready) begin
                        set_wr(3'd3, p3 ^ key0_q);
                        state <= S_INIT_X4_DOM;
                    end
                end

                S_INIT_X4_DOM: begin
                    if (perm_ready) begin
                        if (ad_len != 16'd0) begin
                            set_wr(3'd4, p4 ^ key1_q);
                            state <= S_AD_WAIT;
                        end else begin
                            set_wr(3'd4, p4 ^ key1_q ^ 64'h8000_0000_0000_0000);
                            if (data_len == 16'd0) begin
                                state <= S_DATA_PAD;
                            end else begin
                                state <= S_MSG_WAIT;
                            end
                        end
                    end
                end

                S_AD_WAIT: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_AD || tok_bytes == 4'd0 || tok_bytes > 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            ad_word_q  <= tok_data;
                            ad_bytes_q <= tok_bytes;
                            in_pop     <= 1'b1;
                            state      <= S_WAIT_AD;
                        end
                    end
                end

                S_WAIT_AD: begin
                    state <= S_AD_ABSORB;
                end

                // Single AD block for short official KATs:
                // AD < 8: x0 ^= AD || pad
                // AD = 8: x0 ^= AD, x1 ^= pad(0)
                S_AD_ABSORB: begin
                    if (perm_ready) begin
                        if (ad_bytes_q == 4'd8) begin
                            set_wr(3'd0, p0 ^ ad_word_q);
                            state <= S_AD_PAD_X1;
                        end else begin
                            set_wr(3'd0, p0 ^ ((ad_word_q & mask_n(ad_bytes_q)) ^ pad_n(ad_bytes_q)));
                            state <= S_AD_P8_START;
                        end
                    end
                end

                S_AD_PAD_X1: begin
                    if (perm_ready) begin
                        set_wr(3'd1, p1 ^ 64'h0000_0000_0000_0001);
                        state <= S_AD_P8_START;
                    end
                end

                S_AD_P8_START: begin
                    if (perm_ready) begin
                        perm_rounds_q <= 4'd8;
                        perm_start    <= 1'b1;
                        state         <= S_AD_P8_WAIT;
                    end
                end

                S_AD_P8_WAIT: begin
                    if (perm_done) begin
                        state <= S_AD_DOMSEP;
                    end
                end

                S_AD_DOMSEP: begin
                    if (perm_ready) begin
                        set_wr(3'd4, p4 ^ 64'h8000_0000_0000_0000);
                        if (data_len == 16'd0) begin
                            state <= S_DATA_PAD;
                        end else begin
                            state <= S_MSG_WAIT;
                        end
                    end
                end

                S_MSG_WAIT: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_MSG || tok_bytes == 4'd0 || tok_bytes > 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            msg_word_q  <= tok_data;
                            msg_bytes_q <= tok_bytes;
                            in_pop      <= 1'b1;
                            state       <= S_WAIT_MSG;
                        end
                    end
                end

                S_WAIT_MSG: begin
                    state <= S_MSG_ABSORB;
                end

                // Last data block for short official KATs:
                // len < 8: one partial word with padding in x0.
                // len = 8: full x0 word, padding moves to x1.
                S_MSG_ABSORB: begin
                    if (perm_ready) begin
                        if (msg_bytes_q == 4'd8) begin
                            if (is_decrypt) begin
                                ct_word_q <= p0 ^ msg_word_q;
                                set_wr(3'd0, msg_word_q);
                            end else begin
                                ct_word_q <= p0 ^ msg_word_q;
                                set_wr(3'd0, p0 ^ msg_word_q);
                            end
                            state <= S_MSG_PAD_X1;
                        end else begin
                            if (is_decrypt) begin
                                ct_word_q <= (p0 ^ msg_word_q) & mask_n(msg_bytes_q);
                                set_wr(3'd0, (p0 & ~mask_n(msg_bytes_q)) ^
                                             ((msg_word_q & mask_n(msg_bytes_q)) ^ pad_n(msg_bytes_q)));
                            end else begin
                                ct_word_q <= p0 ^ ((msg_word_q & mask_n(msg_bytes_q)) ^ pad_n(msg_bytes_q));
                                set_wr(3'd0, p0 ^ ((msg_word_q & mask_n(msg_bytes_q)) ^ pad_n(msg_bytes_q)));
                            end
                            state <= S_MSG_EMIT;
                        end
                    end
                end

                S_MSG_PAD_X1: begin
                    if (perm_ready) begin
                        set_wr(3'd1, p1 ^ 64'h0000_0000_0000_0001);
                        state <= S_MSG_EMIT;
                    end
                end

                S_MSG_EMIT: begin
                    if (!out_full) begin
                        out_token <= {
                            1'b0,
                            `SDMC_TOK_OUT,
                            msg_bytes_q,
                            ct_word_q
                        };
                        out_push <= 1'b1;
                        state    <= S_FINAL_X2;
                    end
                end

                // Empty data final block: x0 ^= pad(0), no p8 on last block.
                S_DATA_PAD: begin
                    if (perm_ready) begin
                        set_wr(3'd0, p0 ^ 64'h0000_0000_0000_0001);
                        state <= S_FINAL_X2;
                    end
                end

                // Finalization for AEAD128:
                // x2 ^= K0, x3 ^= K1, p12, tag=(x3^K0)||(x4^K1).
                S_FINAL_X2: begin
                    if (perm_ready) begin
                        set_wr(3'd2, p2 ^ key0_q);
                        state <= S_FINAL_X3;
                    end
                end

                S_FINAL_X3: begin
                    if (perm_ready) begin
                        set_wr(3'd3, p3 ^ key1_q);
                        state <= S_FINAL_START;
                    end
                end

                S_FINAL_START: begin
                    if (perm_ready) begin
                        perm_rounds_q <= 4'd12;
                        perm_start    <= 1'b1;
                        state         <= S_FINAL_WAIT;
                    end
                end

                S_FINAL_WAIT: begin
                    if (perm_done) begin
                        if (is_decrypt) begin
                            state <= S_TAGIN0;
                        end else begin
                            state <= S_TAG0;
                        end
                    end
                end

                S_TAG0: begin
                    if (!out_full) begin
                        out_token <= {
                            1'b0,
                            `SDMC_TOK_TAG,
                            4'd8,
                            p3 ^ key0_q
                        };
                        out_push <= 1'b1;
                        state    <= S_TAG1;
                    end
                end

                S_TAG1: begin
                    if (!out_full) begin
                        out_token <= {
                            1'b1,
                            `SDMC_TOK_TAG,
                            4'd8,
                            p4 ^ key1_q
                        };
                        out_push <= 1'b1;
                        auth_ok  <= 1'b1;
                        state    <= S_DONE;
                    end
                end

                S_TAGIN0: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_TAG || tok_bytes != 4'd8) begin
                            error <= 1'b1;
                            state <= S_ERR;
                        end else begin
                            auth_ok <= auth_ok & (tok_data == (p3 ^ key0_q));
                            in_pop  <= 1'b1;
                            state   <= S_WAIT_TAG1;
                        end
                    end
                end

                S_WAIT_TAG1: begin
                    state <= S_TAGIN1;
                end

                S_TAGIN1: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_TAG || tok_bytes != 4'd8) begin
                            error <= 1'b1;
                            state <= S_ERR;
                        end else begin
                            auth_ok <= auth_ok & (tok_data == (p4 ^ key1_q));
                            in_pop  <= 1'b1;
                            state   <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                S_ERR: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    busy  <= 1'b0;
                    error <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
