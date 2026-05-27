`default_nettype none

`include "sdmc_stream_defs.vh"
`include "sdmc_crypto_defs.vh"

module sdmc_xof_family_core (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire                     start,
    input  wire                     use_hash,
    input  wire                     use_cxof,
    input  wire [15:0]              chain_count,
    input  wire [15:0]              cs_len,
    input  wire [15:0]              out_len,
    input  wire [15:0]              msg_len,

    input  wire [`SDMC_TOKEN_W-1:0] in_token,
    input  wire                     in_empty,
    output reg                      in_pop,

    output reg  [`SDMC_TOKEN_W-1:0] out_token,
    output reg                      out_push,
    input  wire                     out_full,

    output reg                      busy,
    output reg                      done,
    output reg                      error
);

    localparam S_IDLE       = 5'd0;
    localparam S_LOAD_X0    = 5'd1;
    localparam S_LOAD_X1    = 5'd2;
    localparam S_LOAD_X2    = 5'd3;
    localparam S_LOAD_X3    = 5'd4;
    localparam S_LOAD_X4    = 5'd5;
    localparam S_INIT_START = 5'd6;
    localparam S_INIT_WAIT  = 5'd7;
    localparam S_MSG_WAIT   = 5'd8;
    localparam S_ABS_RD     = 5'd9;
    localparam S_ABS_PATCH  = 5'd10;
    localparam S_ABS_WR     = 5'd11;
    localparam S_ABS_START  = 5'd12;
    localparam S_ABS_WAIT   = 5'd13;
    localparam S_SQ_EMIT    = 5'd14;
    localparam S_SQ_START   = 5'd15;
    localparam S_SQ_WAIT    = 5'd16;
    localparam S_DONE       = 5'd17;
    localparam S_ERR        = 5'd18;
    localparam S_CS_WAIT    = 5'd19;

    reg [4:0] state;

    reg [15:0] out_left_q;
    reg [1:0]  phase_q;

    localparam PH_MSG   = 2'd0;
    localparam PH_CS    = 2'd1;
    localparam PH_CSLEN = 2'd2;

    reg [63:0] x0_q;

    reg [63:0] msg_word_q;
    reg [3:0]  msg_bytes_q;
    reg        msg_last_q;
    reg        empty_pad_q;

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
        .rounds        (`SDMC_ASCON_P12),

        .host_ready    (perm_ready),
        .busy          (perm_busy),
        .done          (perm_done),

        .x0            (p0),
        .x1            (p1),
        .x2            (p2),
        .x3            (p3),
        .x4            (p4)
    );

    wire _unused = &{perm_busy, p1, p2, p3, p4, use_cxof, chain_count[0], cs_len[0], out_len[0], 1'b0};

    wire [3:0] emit_bytes = (out_left_q >= 16'd8) ? 4'd8 : out_left_q[3:0];
    wire       emit_last  = (out_left_q <= 16'd8);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            out_left_q   <= 16'd0;
            x0_q         <= 64'd0;
            msg_word_q   <= 64'd0;
            msg_bytes_q  <= 4'd0;
            msg_last_q   <= 1'b0;
            empty_pad_q  <= 1'b0;

            in_pop       <= 1'b0;

            perm_wr_en   <= 1'b0;
            perm_wr_lane <= 3'd0;
            perm_wr_data <= 64'd0;
            perm_rd_en   <= 1'b0;
            perm_rd_lane <= 3'd0;
            perm_start   <= 1'b0;

            out_token    <= {`SDMC_TOKEN_W{1'b0}};
            out_push     <= 1'b0;

            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
        end else if (clear) begin
            state        <= S_IDLE;
            out_left_q   <= 16'd0;
            x0_q         <= 64'd0;
            msg_word_q   <= 64'd0;
            msg_bytes_q  <= 4'd0;
            msg_last_q   <= 1'b0;
            empty_pad_q  <= 1'b0;

            in_pop       <= 1'b0;

            perm_wr_en   <= 1'b0;
            perm_wr_lane <= 3'd0;
            perm_wr_data <= 64'd0;
            perm_rd_en   <= 1'b0;
            perm_rd_lane <= 3'd0;
            perm_start   <= 1'b0;

            out_token    <= {`SDMC_TOKEN_W{1'b0}};
            out_push     <= 1'b0;

            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
        end else begin
            in_pop     <= 1'b0;
            perm_wr_en <= 1'b0;
            perm_rd_en <= 1'b0;
            perm_start <= 1'b0;
            out_push   <= 1'b0;
            done       <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy  <= 1'b0;
                    error <= 1'b0;

                    if (start) begin
                        busy        <= 1'b1;
                        out_left_q  <= out_len;
                        empty_pad_q <= 1'b0;
                        state       <= S_LOAD_X0;
                    end
                end

                S_LOAD_X0: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd0;
                        perm_wr_data <= use_cxof ? `SDMC_CXOF128_IV : `SDMC_XOF128_IV;
                        state        <= S_LOAD_X1;
                    end
                end

                S_LOAD_X1: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd1;
                        perm_wr_data <= 64'd0;
                        state        <= S_LOAD_X2;
                    end
                end

                S_LOAD_X2: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd2;
                        perm_wr_data <= 64'd0;
                        state        <= S_LOAD_X3;
                    end
                end

                S_LOAD_X3: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd3;
                        perm_wr_data <= 64'd0;
                        state        <= S_LOAD_X4;
                    end
                end

                S_LOAD_X4: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd4;
                        perm_wr_data <= 64'd0;
                        state        <= S_INIT_START;
                    end
                end

                S_INIT_START: begin
                    if (perm_ready) begin
                        perm_start <= 1'b1;
                        state      <= S_INIT_WAIT;
                    end
                end

                S_INIT_WAIT: begin
                    if (perm_done) begin
                        if (use_cxof) begin
                            phase_q     <= PH_CSLEN;
                            msg_word_q  <= {45'd0, cs_len, 3'b000};
                            msg_bytes_q <= 4'd8;
                            msg_last_q  <= 1'b0;
                            state       <= S_ABS_RD;
                        end else if (msg_len == 16'd0) begin
                            phase_q     <= PH_MSG;
                            msg_word_q  <= 64'd0;
                            msg_bytes_q <= 4'd0;
                            msg_last_q  <= 1'b1;
                            state       <= S_ABS_RD;
                        end else begin
                            phase_q <= PH_MSG;
                            state   <= S_MSG_WAIT;
                        end
                    end
                end

                S_MSG_WAIT: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_MSG || tok_bytes == 4'd0) begin
                            error <= 1'b1;
                            state <= S_ERR;
                        end else begin
                            in_pop      <= 1'b1;
                            msg_word_q  <= tok_data;
                            msg_bytes_q <= tok_bytes;
                            msg_last_q  <= tok_last;
                            state       <= S_ABS_RD;
                        end
                    end
                end

                S_CS_WAIT: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_CS || tok_bytes == 4'd0) begin
                            error <= 1'b1;
                            state <= S_ERR;
                        end else begin
                            in_pop      <= 1'b1;
                            phase_q     <= PH_CS;
                            msg_word_q  <= tok_data;
                            msg_bytes_q <= tok_bytes;
                            msg_last_q  <= tok_last;
                            state       <= S_ABS_RD;
                        end
                    end
                end

                S_ABS_RD: begin
                    if (perm_ready) begin
                        perm_rd_en   <= 1'b1;
                        perm_rd_lane <= 3'd0;
                        state        <= S_ABS_PATCH;
                    end
                end

                S_ABS_PATCH: begin
                    if (perm_rd_valid) begin
                        if (empty_pad_q) begin
                            x0_q <= perm_rd_data ^ pad_n(4'd0);
                        end else if (msg_last_q) begin
                            if (msg_bytes_q == 4'd8) begin
                                x0_q <= perm_rd_data ^ msg_word_q;
                            end else begin
                                x0_q <= perm_rd_data ^
                                        ((msg_word_q & mask_n(msg_bytes_q)) ^ pad_n(msg_bytes_q));
                            end
                        end else begin
                            x0_q <= perm_rd_data ^ msg_word_q;
                        end

                        state <= S_ABS_WR;
                    end
                end

                S_ABS_WR: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd0;
                        perm_wr_data <= x0_q;
                        state        <= S_ABS_START;
                    end
                end

                S_ABS_START: begin
                    if (perm_ready) begin
                        perm_start <= 1'b1;
                        state      <= S_ABS_WAIT;
                    end
                end

                S_ABS_WAIT: begin
                    if (perm_done) begin
                        if (phase_q == PH_CSLEN) begin
                            phase_q <= PH_CS;
                            if (cs_len == 16'd0) begin
                                msg_word_q  <= 64'd0;
                                msg_bytes_q <= 4'd0;
                                msg_last_q  <= 1'b1;
                                state       <= S_ABS_RD;
                            end else begin
                                state <= S_CS_WAIT;
                            end
                        end else if (empty_pad_q) begin
                            empty_pad_q <= 1'b0;
                            if (phase_q == PH_CS) begin
                                phase_q <= PH_MSG;
                                if (msg_len == 16'd0) begin
                                    msg_word_q  <= 64'd0;
                                    msg_bytes_q <= 4'd0;
                                    msg_last_q  <= 1'b1;
                                    state       <= S_ABS_RD;
                                end else begin
                                    state <= S_MSG_WAIT;
                                end
                            end else begin
                                state <= S_SQ_EMIT;
                            end
                        end else if (msg_last_q) begin
                            if (msg_bytes_q == 4'd8) begin
                                empty_pad_q <= 1'b1;
                                msg_word_q  <= 64'd0;
                                msg_bytes_q <= 4'd0;
                                state       <= S_ABS_RD;
                            end else if (phase_q == PH_CS) begin
                                phase_q <= PH_MSG;
                                if (msg_len == 16'd0) begin
                                    msg_word_q  <= 64'd0;
                                    msg_bytes_q <= 4'd0;
                                    msg_last_q  <= 1'b1;
                                    state       <= S_ABS_RD;
                                end else begin
                                    state <= S_MSG_WAIT;
                                end
                            end else begin
                                state <= S_SQ_EMIT;
                            end
                        end else begin
                            if (phase_q == PH_CS) begin
                                state <= S_CS_WAIT;
                            end else begin
                                state <= S_MSG_WAIT;
                            end
                        end
                    end
                end

                S_SQ_EMIT: begin
                    if (!out_full) begin
                        out_token <= {
                            emit_last,
                            `SDMC_TOK_OUT,
                            emit_bytes,
                            p0
                        };
                        out_push <= 1'b1;

                        if (emit_last) begin
                            state <= S_DONE;
                        end else begin
                            out_left_q <= out_left_q - 16'd8;
                            state      <= S_SQ_START;
                        end
                    end
                end

                S_SQ_START: begin
                    if (perm_ready) begin
                        perm_start <= 1'b1;
                        state      <= S_SQ_WAIT;
                    end
                end

                S_SQ_WAIT: begin
                    if (perm_done) begin
                        state <= S_SQ_EMIT;
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                S_ERR: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
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
