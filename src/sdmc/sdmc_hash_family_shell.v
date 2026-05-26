`default_nettype none

`include "sdmc_stream_defs.vh"

module sdmc_hash_family_shell (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire                     start,

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

    localparam S_IDLE = 3'd0;
    localparam S_WAIT = 3'd1;
    localparam S_EMIT = 3'd2;
    localparam S_DONE = 3'd3;
    localparam S_ERR  = 3'd4;

    reg [2:0] state;

    reg        tok_last_q;
    reg [3:0]  tok_kind_q;
    reg [3:0]  tok_bytes_q;
    reg [63:0] tok_data_q;

    wire        tok_last  = in_token[`SDMC_TOKEN_LAST_BIT];
    wire [3:0]  tok_kind  = in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
    wire [3:0]  tok_bytes = in_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
    wire [63:0] tok_data  = in_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            in_pop      <= 1'b0;
            out_token   <= {`SDMC_TOKEN_W{1'b0}};
            out_push    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
            tok_last_q  <= 1'b0;
            tok_kind_q  <= 4'd0;
            tok_bytes_q <= 4'd0;
            tok_data_q  <= 64'd0;
        end else if (clear) begin
            state       <= S_IDLE;
            in_pop      <= 1'b0;
            out_token   <= {`SDMC_TOKEN_W{1'b0}};
            out_push    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
            tok_last_q  <= 1'b0;
            tok_kind_q  <= 4'd0;
            tok_bytes_q <= 4'd0;
            tok_data_q  <= 64'd0;
        end else begin
            in_pop   <= 1'b0;
            out_push <= 1'b0;
            done     <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy  <= 1'b0;
                    error <= 1'b0;

                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (!in_empty) begin
                        if (tok_kind != `SDMC_TOK_MSG) begin
                            error <= 1'b1;
                            state <= S_ERR;
                        end else begin
                            in_pop      <= 1'b1;
                            tok_last_q  <= tok_last;
                            tok_kind_q  <= tok_kind;
                            tok_bytes_q <= tok_bytes;
                            tok_data_q  <= tok_data;
                            state       <= S_EMIT;
                        end
                    end
                end

                S_EMIT: begin
                    if (!out_full) begin
                        out_token <= {
                            tok_last_q,
                            `SDMC_TOK_OUT,
                            tok_bytes_q,
                            tok_data_q
                        };
                        out_push <= 1'b1;

                        if (tok_last_q) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_WAIT;
                        end
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
                    state <= S_IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
