/*
 * byte_to_word_packer.v — assemble UART bytes into 64-bit words.
 *
 * Area/fanout surgery:
 *   - Only control registers are reset.
 *   - Data registers are not reset; they are overwritten before use.
 *   - flush_ready is handshake-safe and accepts no-op flushes.
 */
`default_nettype none

module byte_to_word_packer (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  in_byte,
    input  wire        in_byte_valid,
    output wire        in_byte_ready,

    input  wire        flush,
    output wire        flush_ready,

    output reg  [63:0] out_word,
    output reg  [3:0]  out_word_bytes,
    output reg         out_word_valid,
    input  wire        out_word_ready
);

    reg [2:0]  byte_idx;
    reg [63:0] accumulator;

    assign flush_ready  = !out_word_valid;
    assign in_byte_ready = !out_word_valid && !flush;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_idx       <= 3'd0;
            out_word_bytes <= 4'd0;
            out_word_valid <= 1'b0;
        end else begin
            if (out_word_valid && out_word_ready) begin
                out_word_valid <= 1'b0;
                out_word_bytes <= 4'd0;
                byte_idx       <= 3'd0;
                accumulator    <= 64'd0;
            end

            if (flush && flush_ready) begin
                if (byte_idx != 3'd0) begin
                    out_word       <= accumulator;
                    out_word_bytes <= {1'b0, byte_idx};
                    out_word_valid <= 1'b1;
                end
                byte_idx <= 3'd0;
            end else if (in_byte_valid && in_byte_ready) begin
                case (byte_idx)
                    3'd0: accumulator[7:0]   <= in_byte;
                    3'd1: accumulator[15:8]  <= in_byte;
                    3'd2: accumulator[23:16] <= in_byte;
                    3'd3: accumulator[31:24] <= in_byte;
                    3'd4: accumulator[39:32] <= in_byte;
                    3'd5: accumulator[47:40] <= in_byte;
                    3'd6: accumulator[55:48] <= in_byte;
                    3'd7: accumulator[63:56] <= in_byte;
                endcase

                if (byte_idx == 3'd7) begin
                    out_word       <= {in_byte, accumulator[55:0]};
                    out_word_bytes <= 4'd8;
                    out_word_valid <= 1'b1;
                    byte_idx       <= 3'd0;
                end else begin
                    byte_idx <= byte_idx + 1'b1;
                end
            end
        end
    end

endmodule
