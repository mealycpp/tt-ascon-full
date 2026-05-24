/*
 * word_to_byte_unpacker.v — split a 64-bit word into 1..8 output bytes.
 *
 * Convention matches packer: word[7:0] -> byte0, word[63:56] -> byte7.
 *
 * Input handshake (word side):
 *   in_word_valid && in_word_ready  -> word accepted
 *
 * Output handshake (byte side):
 *   out_byte_valid && out_byte_ready -> byte consumed
 *
 * in_word_bytes: number of real bytes in this word, 1..8.
 *                For non-final words always 8; for the final word 1..8.
 */
`default_nettype none

module word_to_byte_unpacker (
    input  wire        clk,
    input  wire        rst_n,

    // Word input
    input  wire [63:0] in_word,
    input  wire [3:0]  in_word_bytes,   // 1..8
    input  wire        in_word_valid,
    output wire        in_word_ready,

    // Byte output
    output reg  [7:0]  out_byte,
    output reg         out_byte_valid,
    input  wire        out_byte_ready
);

    reg [63:0] buffer;
    reg [3:0]  bytes_left;     // remaining bytes to emit
    reg [2:0]  emit_idx;       // next byte position to read from buffer

    assign in_word_ready = (bytes_left == 4'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer         <= 64'd0;
            bytes_left     <= 4'd0;
            emit_idx       <= 3'd0;
            out_byte       <= 8'd0;
            out_byte_valid <= 1'b0;
        end else begin
            // Clear valid when downstream takes a byte
            if (out_byte_valid && out_byte_ready) begin
                out_byte_valid <= 1'b0;
            end

            // Latch new word when idle
            if (in_word_valid && in_word_ready) begin
                buffer     <= in_word;
                bytes_left <= in_word_bytes;
                emit_idx   <= 3'd0;
            end

            // Emit a byte when we have bytes left and output isn't blocked
            if (bytes_left > 4'd0 && (!out_byte_valid || (out_byte_valid && out_byte_ready))) begin
                case (emit_idx)
                    3'd0: out_byte <= buffer[7:0];
                    3'd1: out_byte <= buffer[15:8];
                    3'd2: out_byte <= buffer[23:16];
                    3'd3: out_byte <= buffer[31:24];
                    3'd4: out_byte <= buffer[39:32];
                    3'd5: out_byte <= buffer[47:40];
                    3'd6: out_byte <= buffer[55:48];
                    3'd7: out_byte <= buffer[63:56];
                endcase
                out_byte_valid <= 1'b1;
                emit_idx       <= emit_idx + 1'b1;
                bytes_left     <= bytes_left - 1'b1;
            end
        end
    end

endmodule
