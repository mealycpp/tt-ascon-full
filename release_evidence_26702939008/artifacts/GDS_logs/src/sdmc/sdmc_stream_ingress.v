`default_nettype none

`include "src/sdmc/sdmc_stream_defs.vh"

module sdmc_stream_ingress (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire [7:0]               in_byte,
    input  wire [3:0]               in_kind,
    input  wire                     in_last,
    input  wire                     in_valid,
    output wire                     in_ready,

    output reg                      tok_push,
    output reg  [`SDMC_TOKEN_W-1:0] tok_din,
    input  wire                     tok_full
);

    reg [63:0] word_buf;
    reg [3:0]  byte_count;
    reg [3:0]  kind_q;

    wire [3:0] next_count = byte_count + 4'd1;
    wire       flush_now  = in_valid && ((byte_count == 4'd7) || in_last);

    assign in_ready = (!flush_now) || (!tok_full);

    reg [63:0] word_next;

    always @* begin
        word_next = word_buf;
        case (byte_count[2:0])
            3'd0: word_next[7:0]   = in_byte;
            3'd1: word_next[15:8]  = in_byte;
            3'd2: word_next[23:16] = in_byte;
            3'd3: word_next[31:24] = in_byte;
            3'd4: word_next[39:32] = in_byte;
            3'd5: word_next[47:40] = in_byte;
            3'd6: word_next[55:48] = in_byte;
            3'd7: word_next[63:56] = in_byte;
            default: word_next     = word_buf;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_buf   <= 64'd0;
            byte_count <= 4'd0;
            kind_q     <= 4'd0;
            tok_push   <= 1'b0;
            tok_din    <= {`SDMC_TOKEN_W{1'b0}};
        end else if (clear) begin
            word_buf   <= 64'd0;
            byte_count <= 4'd0;
            kind_q     <= 4'd0;
            tok_push   <= 1'b0;
            tok_din    <= {`SDMC_TOKEN_W{1'b0}};
        end else begin
            tok_push <= 1'b0;
            tok_din  <= {`SDMC_TOKEN_W{1'b0}};

            if (in_valid && in_ready) begin
                if (byte_count == 4'd0) begin
                    kind_q <= in_kind;
                end

                if ((byte_count == 4'd7) || in_last) begin
                    tok_push <= 1'b1;
                    tok_din  <= {
                        in_last,
                        (byte_count == 4'd0) ? in_kind : kind_q,
                        next_count,
                        word_next
                    };

                    word_buf   <= 64'd0;
                    byte_count <= 4'd0;
                    kind_q     <= 4'd0;
                end else begin
                    word_buf   <= word_next;
                    byte_count <= next_count;
                end
            end
        end
    end

endmodule

`default_nettype wire
