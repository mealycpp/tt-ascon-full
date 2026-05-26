`default_nettype none

`include "sdmc_stream_defs.vh"
`include "sdmc_crypto_defs.vh"

module sdmc_hash256_core (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire                     start,

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
    localparam S_PAD_RD     = 5'd8;
    localparam S_PAD_PATCH  = 5'd9;
    localparam S_PAD_START  = 5'd10;
    localparam S_PAD_WAIT   = 5'd11;
    localparam S_SQ_EMIT    = 5'd12;
    localparam S_SQ_START   = 5'd13;
    localparam S_SQ_WAIT    = 5'd14;
    localparam S_DONE       = 5'd15;

    reg [4:0] state;

    reg [1:0] squeeze_idx;
    reg [63:0] x0_q;

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

    wire _unused = &{perm_busy, p0, p1, p2, p3, p4, 1'b0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            squeeze_idx  <= 2'd0;
            x0_q         <= 64'd0;

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
            squeeze_idx  <= 2'd0;
            x0_q         <= 64'd0;

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
                        squeeze_idx <= 2'd0;
                        state       <= S_LOAD_X0;
                    end
                end

                S_LOAD_X0: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd0;
                        perm_wr_data <= `SDMC_HASH256_IV;
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
                        state <= S_PAD_RD;
                    end
                end

                // Empty message final block: x0 ^= PAD(0) = 1.
                S_PAD_RD: begin
                    if (perm_ready) begin
                        perm_rd_en   <= 1'b1;
                        perm_rd_lane <= 3'd0;
                        state        <= S_PAD_PATCH;
                    end
                end

                S_PAD_PATCH: begin
                    if (perm_rd_valid) begin
                        x0_q <= perm_rd_data ^ 64'h0000_0000_0000_0001;
                        state <= S_PAD_START;
                    end
                end

                S_PAD_START: begin
                    if (perm_ready) begin
                        perm_wr_en   <= 1'b1;
                        perm_wr_lane <= 3'd0;
                        perm_wr_data <= x0_q;
                        state        <= S_PAD_WAIT;
                    end
                end

                S_PAD_WAIT: begin
                    if (perm_ready) begin
                        perm_start <= 1'b1;
                        state      <= S_SQ_EMIT;
                    end
                end

                S_SQ_EMIT: begin
                    if (perm_done || squeeze_idx != 2'd0) begin
                        if (!out_full) begin
                            out_token <= {
                                (squeeze_idx == 2'd3),
                                `SDMC_TOK_OUT,
                                4'd8,
                                p0
                            };
                            out_push <= 1'b1;

                            if (squeeze_idx == 2'd3) begin
                                state <= S_DONE;
                            end else begin
                                state <= S_SQ_START;
                            end
                        end
                    end
                end

                S_SQ_START: begin
                    if (perm_ready) begin
                        squeeze_idx <= squeeze_idx + 2'd1;
                        perm_start  <= 1'b1;
                        state       <= S_SQ_WAIT;
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
