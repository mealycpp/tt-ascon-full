`default_nettype none

`include "src/sdmc/sdmc_stream_defs.vh"

module sdmc_stream_egress (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire [`SDMC_TOKEN_W-1:0] tok_dout,
    input  wire                     tok_empty,
    output reg                      tok_pop,

    output wire [7:0]               out_byte,
    output wire [3:0]               out_kind,
    output wire                     out_last,
    output wire                     out_valid,
    input  wire                     out_ready
);

    reg        active;
    reg        last_q;
    reg [3:0]  kind_q;
    reg [3:0]  bytes_q;
    reg [63:0] data_q;
    reg [3:0]  index_q;

    wire token_last = tok_dout[`SDMC_TOKEN_LAST_BIT];
    wire [3:0] token_kind = tok_dout[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
    wire [3:0] token_bytes = tok_dout[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
    wire [63:0] token_data = tok_dout[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

    assign out_valid = active;
    assign out_kind  = kind_q;
    assign out_last  = active && last_q && ((index_q + 4'd1) == bytes_q);

    reg [7:0] out_byte_r;
    assign out_byte = out_byte_r;

    always @* begin
        case (index_q[2:0])
            3'd0: out_byte_r = data_q[7:0];
            3'd1: out_byte_r = data_q[15:8];
            3'd2: out_byte_r = data_q[23:16];
            3'd3: out_byte_r = data_q[31:24];
            3'd4: out_byte_r = data_q[39:32];
            3'd5: out_byte_r = data_q[47:40];
            3'd6: out_byte_r = data_q[55:48];
            3'd7: out_byte_r = data_q[63:56];
            default: out_byte_r = 8'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active  <= 1'b0;
            last_q  <= 1'b0;
            kind_q  <= 4'd0;
            bytes_q <= 4'd0;
            data_q  <= 64'd0;
            index_q <= 4'd0;
            tok_pop <= 1'b0;
        end else if (clear) begin
            active  <= 1'b0;
            last_q  <= 1'b0;
            kind_q  <= 4'd0;
            bytes_q <= 4'd0;
            data_q  <= 64'd0;
            index_q <= 4'd0;
            tok_pop <= 1'b0;
        end else begin
            tok_pop <= 1'b0;

            if (!active) begin
                if (!tok_empty) begin
                    tok_pop <= 1'b1;

                    if (token_bytes != 4'd0) begin
                        active  <= 1'b1;
                        last_q  <= token_last;
                        kind_q  <= token_kind;
                        bytes_q <= token_bytes;
                        data_q  <= token_data;
                        index_q <= 4'd0;
                    end
                end
            end else if (out_ready) begin
                if ((index_q + 4'd1) == bytes_q) begin
                    active  <= 1'b0;
                    last_q  <= 1'b0;
                    kind_q  <= 4'd0;
                    bytes_q <= 4'd0;
                    data_q  <= 64'd0;
                    index_q <= 4'd0;
                end else begin
                    index_q <= index_q + 4'd1;
                end
            end
        end
    end

endmodule

`default_nettype wire
