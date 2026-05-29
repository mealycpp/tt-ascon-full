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

    localparam S_IDLE             = 7'd0;
    localparam S_KEY0             = 7'd1;
    localparam S_WAIT_KEY1        = 7'd2;
    localparam S_KEY1             = 7'd3;
    localparam S_WAIT_NONCE0      = 7'd4;
    localparam S_NONCE0           = 7'd5;
    localparam S_WAIT_NONCE1      = 7'd6;
    localparam S_NONCE1           = 7'd7;

    localparam S_LOAD_X0          = 7'd8;
    localparam S_LOAD_X1          = 7'd9;
    localparam S_LOAD_X2          = 7'd10;
    localparam S_LOAD_X3          = 7'd11;
    localparam S_LOAD_X4          = 7'd12;

    localparam S_INIT_START       = 7'd13;
    localparam S_INIT_WAIT        = 7'd14;
    localparam S_INIT_X3          = 7'd15;
    localparam S_INIT_X4          = 7'd16;

    localparam S_AD_BEGIN         = 7'd17;
    localparam S_AD_GET_W0        = 7'd18;
    localparam S_AD_WAIT_W1       = 7'd19;
    localparam S_AD_GET_W1        = 7'd20;
    localparam S_AD_X0            = 7'd21;
    localparam S_AD_X1            = 7'd22;
    localparam S_AD_P8_START      = 7'd23;
    localparam S_AD_P8_WAIT       = 7'd24;

    localparam S_DOMSEP           = 7'd25;

    localparam S_DATA_BEGIN       = 7'd26;
    localparam S_DATA_GET_W0      = 7'd27;
    localparam S_DATA_WAIT_W1     = 7'd28;
    localparam S_DATA_GET_W1      = 7'd29;
    localparam S_DATA_X0          = 7'd30;
    localparam S_DATA_X1          = 7'd31;
    localparam S_DATA_EMIT_W0     = 7'd32;
    localparam S_DATA_EMIT_W1     = 7'd33;
    localparam S_DATA_P8_START    = 7'd34;
    localparam S_DATA_P8_WAIT     = 7'd35;

    localparam S_FINAL_X2         = 7'd36;
    localparam S_FINAL_X3         = 7'd37;
    localparam S_FINAL_START      = 7'd38;
    localparam S_FINAL_WAIT       = 7'd39;

    localparam S_TAG0             = 7'd40;
    localparam S_TAG1             = 7'd41;
    localparam S_TAGIN0           = 7'd42;
    localparam S_WAIT_TAG1        = 7'd43;
    localparam S_TAGIN1           = 7'd44;

    localparam S_DONE             = 7'd45;
    localparam S_ERR              = 7'd46;

    reg [6:0] state;

    reg [63:0] key0_q;
    reg [63:0] key1_q;
    reg [63:0] nonce0_q;
    reg [63:0] nonce1_q;

    reg        is_decrypt_q;
    reg [15:0] ad_left_q;
    reg [15:0] data_left_q;

    reg [15:0] ad_block_start_left_q;
    reg [15:0] data_block_start_left_q;

    reg [63:0] w0_q;
    reg [63:0] w1_q;
    reg [3:0]  w0_bytes_q;
    reg [3:0]  w1_bytes_q;
    reg        w0_has_real_q;
    reg        w1_has_real_q;
    reg        w0_pad_q;
    reg        w1_pad_q;
    reg        block_final_q;
    reg        block_pad_only_q;

    reg [63:0] out_w0_q;
    reg [63:0] out_w1_q;

    wire        tok_last  = in_token[`SDMC_TOKEN_LAST_BIT];
    wire [3:0]  tok_kind  = in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
    wire [3:0]  tok_bytes = in_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
    wire [63:0] tok_data  = in_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

    function [63:0] mask_n;
        input [3:0] n;
        begin
            case (n)
                4'd0: mask_n = 64'h0000_0000_0000_0000;
                4'd1: mask_n = 64'h0000_0000_0000_00ff;
                4'd2: mask_n = 64'h0000_0000_0000_ffff;
                4'd3: mask_n = 64'h0000_0000_00ff_ffff;
                4'd4: mask_n = 64'h0000_0000_ffff_ffff;
                4'd5: mask_n = 64'h0000_00ff_ffff_ffff;
                4'd6: mask_n = 64'h0000_ffff_ffff_ffff;
                4'd7: mask_n = 64'h00ff_ffff_ffff_ffff;
                4'd8: mask_n = 64'hffff_ffff_ffff_ffff;
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

        .host_rd_en    (1'b0),
        .host_rd_lane  (3'd0),
        .host_rd_data  (),
        .host_rd_valid (),

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

    wire _unused = &{perm_busy, tok_last, 1'b0};

    task set_wr;
        input [2:0] lane;
        input [63:0] data;
        begin
            perm_wr_en   <= 1'b1;
            perm_wr_lane <= lane;
            perm_wr_data <= data;
        end
    endtask

    task clear_block_regs;
        begin
            w0_q              <= 64'd0;
            w1_q              <= 64'd0;
            w0_bytes_q        <= 4'd0;
            w1_bytes_q        <= 4'd0;
            w0_has_real_q     <= 1'b0;
            w1_has_real_q     <= 1'b0;
            w0_pad_q          <= 1'b0;
            w1_pad_q          <= 1'b0;
            block_final_q     <= 1'b0;
            block_pad_only_q  <= 1'b0;
            out_w0_q          <= 64'd0;
            out_w1_q          <= 64'd0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            in_pop      <= 1'b0;
            out_token   <= {`SDMC_TOKEN_W{1'b0}};
            out_push    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
            auth_ok     <= 1'b0;

            key0_q      <= 64'd0;
            key1_q      <= 64'd0;
            nonce0_q    <= 64'd0;
            nonce1_q    <= 64'd0;
            is_decrypt_q <= 1'b0;
            ad_left_q   <= 16'd0;
            data_left_q <= 16'd0;
            ad_block_start_left_q <= 16'd0;
            data_block_start_left_q <= 16'd0;

            perm_wr_en   <= 1'b0;
            perm_wr_lane <= 3'd0;
            perm_wr_data <= 64'd0;
            perm_start   <= 1'b0;
            perm_rounds_q <= 4'd12;

            clear_block_regs();
        end else if (clear) begin
            state       <= S_IDLE;
            in_pop      <= 1'b0;
            out_token   <= {`SDMC_TOKEN_W{1'b0}};
            out_push    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
            auth_ok     <= 1'b0;

            key0_q      <= 64'd0;
            key1_q      <= 64'd0;
            nonce0_q    <= 64'd0;
            nonce1_q    <= 64'd0;
            is_decrypt_q <= 1'b0;
            ad_left_q   <= 16'd0;
            data_left_q <= 16'd0;
            ad_block_start_left_q <= 16'd0;
            data_block_start_left_q <= 16'd0;

            perm_wr_en   <= 1'b0;
            perm_wr_lane <= 3'd0;
            perm_wr_data <= 64'd0;
            perm_start   <= 1'b0;
            perm_rounds_q <= 4'd12;

            clear_block_regs();
        end else begin
            in_pop      <= 1'b0;
            out_push    <= 1'b0;
            out_token   <= {`SDMC_TOKEN_W{1'b0}};
            done        <= 1'b0;
            perm_wr_en  <= 1'b0;
            perm_start  <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy  <= 1'b0;
                    error <= 1'b0;
                    if (start) begin
                        busy         <= 1'b1;
                        is_decrypt_q <= is_decrypt;
                        ad_left_q    <= ad_len;
                        data_left_q  <= data_len;
                        auth_ok      <= is_decrypt ? 1'b1 : 1'b0;
                        clear_block_regs();
                        state        <= S_KEY0;
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

                S_INIT_X3: begin
                    if (perm_ready) begin
                        set_wr(3'd3, p3 ^ key0_q);
                        state <= S_INIT_X4;
                    end
                end

                S_INIT_X4: begin
                    if (perm_ready) begin
                        set_wr(3'd4, p4 ^ key1_q);
                        state <= S_AD_BEGIN;
                    end
                end

                S_AD_BEGIN: begin
                    clear_block_regs();

                    if (ad_len == 16'd0) begin
                        state <= S_DOMSEP;
                    end else if (ad_left_q == 16'd0) begin
                        w0_pad_q         <= 1'b1;
                        block_final_q    <= 1'b1;
                        block_pad_only_q <= 1'b1;
                        state            <= S_AD_X0;
                    end else begin
                        ad_block_start_left_q <= ad_left_q;
                        state <= S_AD_GET_W0;
                    end
                end

                S_AD_GET_W0: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_AD || tok_bytes == 4'd0 || tok_bytes > 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (ad_left_q >= 16'd8 && tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (ad_left_q < 16'd8 && tok_bytes != ad_left_q[3:0]) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            w0_q          <= tok_data;
                            w0_bytes_q    <= tok_bytes;
                            w0_has_real_q <= 1'b1;
                            in_pop        <= 1'b1;

                            if (ad_left_q > 16'd8) begin
                                ad_left_q <= ad_left_q - 16'd8;
                                state     <= S_AD_WAIT_W1;
                            end else if (ad_left_q == 16'd8) begin
                                ad_left_q     <= 16'd0;
                                w1_pad_q      <= 1'b1;
                                block_final_q <= 1'b1;
                                state         <= S_AD_X0;
                            end else begin
                                ad_left_q    <= 16'd0;
                                w0_pad_q     <= 1'b1;
                                block_final_q <= 1'b1;
                                state        <= S_AD_X0;
                            end
                        end
                    end
                end

                S_AD_WAIT_W1: begin
                    state <= S_AD_GET_W1;
                end

                S_AD_GET_W1: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_AD || tok_bytes == 4'd0 || tok_bytes > 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (ad_left_q >= 16'd8 && tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (ad_left_q < 16'd8 && tok_bytes != ad_left_q[3:0]) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            w1_q          <= tok_data;
                            w1_bytes_q    <= tok_bytes;
                            w1_has_real_q <= 1'b1;
                            in_pop        <= 1'b1;

                            if (ad_left_q > 16'd8) begin
                                ad_left_q <= ad_left_q - 16'd8;
                            end else if (ad_left_q == 16'd8) begin
                                ad_left_q <= 16'd0;
                            end else begin
                                ad_left_q    <= 16'd0;
                                w1_pad_q     <= 1'b1;
                                block_final_q <= 1'b1;
                            end
                            state <= S_AD_X0;
                        end
                    end
                end

                S_AD_X0: begin
                    if (perm_ready) begin
                        if (block_pad_only_q) begin
                            set_wr(3'd0, p0 ^ pad_n(4'd0));
                        end else if (w0_has_real_q) begin
                            if (w0_pad_q) begin
                                set_wr(3'd0, p0 ^ ((w0_q & mask_n(w0_bytes_q)) ^ pad_n(w0_bytes_q)));
                            end else begin
                                set_wr(3'd0, p0 ^ w0_q);
                            end
                        end else begin
                            set_wr(3'd0, p0);
                        end
                        state <= S_AD_X1;
                    end
                end

                S_AD_X1: begin
                    if (perm_ready) begin
                        if (w1_has_real_q) begin
                            if (w1_pad_q) begin
                                set_wr(3'd1, p1 ^ ((w1_q & mask_n(w1_bytes_q)) ^ pad_n(w1_bytes_q)));
                            end else begin
                                set_wr(3'd1, p1 ^ w1_q);
                            end
                        end else if (w1_pad_q) begin
                            set_wr(3'd1, p1 ^ pad_n(4'd0));
                        end else begin
                            set_wr(3'd1, p1);
                        end
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
                        if (block_final_q || block_pad_only_q) begin
                            state <= S_DOMSEP;
                        end else begin
                            state <= S_AD_BEGIN;
                        end
                    end
                end

                S_DOMSEP: begin
                    if (perm_ready) begin
                        set_wr(3'd4, p4 ^ 64'h8000_0000_0000_0000);
                        state <= S_DATA_BEGIN;
                    end
                end

                S_DATA_BEGIN: begin
                    clear_block_regs();

                    if (data_left_q == 16'd0) begin
                        w0_pad_q         <= 1'b1;
                        block_final_q    <= 1'b1;
                        block_pad_only_q <= 1'b1;
                        state            <= S_DATA_X0;
                    end else begin
                        data_block_start_left_q <= data_left_q;
                        state <= S_DATA_GET_W0;
                    end
                end

                S_DATA_GET_W0: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_MSG || tok_bytes == 4'd0 || tok_bytes > 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (data_left_q >= 16'd8 && tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (data_left_q < 16'd8 && tok_bytes != data_left_q[3:0]) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            w0_q          <= tok_data;
                            w0_bytes_q    <= tok_bytes;
                            w0_has_real_q <= 1'b1;
                            in_pop        <= 1'b1;

                            if (data_left_q > 16'd8) begin
                                data_left_q <= data_left_q - 16'd8;
                                state       <= S_DATA_WAIT_W1;
                            end else if (data_left_q == 16'd8) begin
                                data_left_q <= 16'd0;
                                w1_pad_q    <= 1'b1;
                                block_final_q <= 1'b1;
                                state       <= S_DATA_X0;
                            end else begin
                                data_left_q  <= 16'd0;
                                w0_pad_q     <= 1'b1;
                                block_final_q <= 1'b1;
                                state        <= S_DATA_X0;
                            end
                        end
                    end
                end

                S_DATA_WAIT_W1: begin
                    state <= S_DATA_GET_W1;
                end

                S_DATA_GET_W1: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_MSG || tok_bytes == 4'd0 || tok_bytes > 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (data_left_q >= 16'd8 && tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else if (data_left_q < 16'd8 && tok_bytes != data_left_q[3:0]) begin
                            state <= S_ERR;
                            error <= 1'b1;
                        end else begin
                            w1_q          <= tok_data;
                            w1_bytes_q    <= tok_bytes;
                            w1_has_real_q <= 1'b1;
                            in_pop        <= 1'b1;

                            if (data_left_q > 16'd8) begin
                                data_left_q <= data_left_q - 16'd8;
                                block_final_q <= 1'b0;
                            end else if (data_left_q == 16'd8) begin
                                data_left_q <= 16'd0;
                                block_final_q <= 1'b0;
                            end else begin
                                data_left_q  <= 16'd0;
                                w1_pad_q     <= 1'b1;
                                block_final_q <= 1'b1;
                            end
                            state <= S_DATA_X0;
                        end
                    end
                end

                S_DATA_X0: begin
                    if (perm_ready) begin
                        if (block_pad_only_q) begin
                            set_wr(3'd0, p0 ^ pad_n(4'd0));
                        end else if (w0_has_real_q) begin
                            if (is_decrypt_q) begin
                                out_w0_q <= (p0 ^ w0_q) & mask_n(w0_bytes_q);
                                if (w0_pad_q) begin
                                    set_wr(3'd0, (p0 & ~mask_n(w0_bytes_q)) ^
                                                 ((w0_q & mask_n(w0_bytes_q)) ^ pad_n(w0_bytes_q)));
                                end else begin
                                    set_wr(3'd0, w0_q);
                                end
                            end else begin
                                out_w0_q <= p0 ^ w0_q;
                                if (w0_pad_q) begin
                                    set_wr(3'd0, p0 ^ ((w0_q & mask_n(w0_bytes_q)) ^ pad_n(w0_bytes_q)));
                                end else begin
                                    set_wr(3'd0, p0 ^ w0_q);
                                end
                            end
                        end else begin
                            set_wr(3'd0, p0);
                        end
                        state <= S_DATA_X1;
                    end
                end

                S_DATA_X1: begin
                    if (perm_ready) begin
                        if (w1_has_real_q) begin
                            if (is_decrypt_q) begin
                                out_w1_q <= (p1 ^ w1_q) & mask_n(w1_bytes_q);
                                if (w1_pad_q) begin
                                    set_wr(3'd1, (p1 & ~mask_n(w1_bytes_q)) ^
                                                 ((w1_q & mask_n(w1_bytes_q)) ^ pad_n(w1_bytes_q)));
                                end else begin
                                    set_wr(3'd1, w1_q);
                                end
                            end else begin
                                out_w1_q <= p1 ^ w1_q;
                                if (w1_pad_q) begin
                                    set_wr(3'd1, p1 ^ ((w1_q & mask_n(w1_bytes_q)) ^ pad_n(w1_bytes_q)));
                                end else begin
                                    set_wr(3'd1, p1 ^ w1_q);
                                end
                            end
                        end else if (w1_pad_q) begin
                            set_wr(3'd1, p1 ^ pad_n(4'd0));
                        end else begin
                            set_wr(3'd1, p1);
                        end
                        state <= S_DATA_EMIT_W0;
                    end
                end

                S_DATA_EMIT_W0: begin
                    if (w0_has_real_q) begin
                        if (!out_full) begin
                            out_token <= {1'b0, `SDMC_TOK_OUT, w0_bytes_q, out_w0_q};
                            out_push  <= 1'b1;
                            state     <= S_DATA_EMIT_W1;
                        end
                    end else begin
                        state <= S_DATA_EMIT_W1;
                    end
                end

                S_DATA_EMIT_W1: begin
                    if (w1_has_real_q) begin
                        if (!out_full) begin
                            out_token <= {1'b0, `SDMC_TOK_OUT, w1_bytes_q, out_w1_q};
                            out_push  <= 1'b1;
                            if (block_final_q || block_pad_only_q) begin
                                state <= S_FINAL_X2;
                            end else begin
                                state <= S_DATA_P8_START;
                            end
                        end
                    end else begin
                        if (block_final_q || block_pad_only_q) begin
                            state <= S_FINAL_X2;
                        end else begin
                            state <= S_DATA_P8_START;
                        end
                    end
                end

                S_DATA_P8_START: begin
                    if (perm_ready) begin
                        perm_rounds_q <= 4'd8;
                        perm_start    <= 1'b1;
                        state         <= S_DATA_P8_WAIT;
                    end
                end

                S_DATA_P8_WAIT: begin
                    if (perm_done) begin
                        state <= S_DATA_BEGIN;
                    end
                end

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
                        if (is_decrypt_q) begin
                            state <= S_TAGIN0;
                        end else begin
                            state <= S_TAG0;
                        end
                    end
                end

                S_TAG0: begin
                    if (!out_full) begin
                        out_token <= {1'b0, `SDMC_TOK_TAG, 4'd8, p3 ^ key0_q};
                        out_push  <= 1'b1;
                        state     <= S_TAG1;
                    end
                end

                S_TAG1: begin
                    if (!out_full) begin
                        out_token <= {1'b1, `SDMC_TOK_TAG, 4'd8, p4 ^ key1_q};
                        out_push  <= 1'b1;
                        auth_ok   <= 1'b1;
                        state     <= S_DONE;
                    end
                end

                S_TAGIN0: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_TAG || tok_bytes != 4'd8) begin
                            state <= S_ERR;
                            error <= 1'b1;
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
                            state <= S_ERR;
                            error <= 1'b1;
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
                    error <= 1'b1;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_ERR;
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
