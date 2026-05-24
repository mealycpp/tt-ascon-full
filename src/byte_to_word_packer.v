/*
 * byte_to_word_packer.v — assemble 8 input bytes into one 64-bit word.
 *
 * Convention: byte0 -> word[7:0], byte1 -> word[15:8], ..., byte7 -> word[63:56].
 * This matches our Python bytes_to_word() and the controllers' "byte 0 = LSB".
 *
 * The packer does NOT know "last" semantics. It just emits a fully-formed
 * 64-bit word whenever 8 bytes have been accumulated. A partial word (less
 * than 8 bytes) is emitted on `flush` (host signals end-of-frame), with
 * `out_word_bytes` indicating how many real bytes are in the word.
 *
 * Input handshake (byte side):
 *   in_byte_valid && in_byte_ready  -> byte accepted
 *
 * Output handshake (word side):
 *   out_word_valid && out_word_ready -> word consumed
 *
 * out_word_bytes: number of real bytes in this word, 1..8.
 *                 Always 8 for non-flushed words; 1..7 for the final
 *                 partial word.
 *
 * Flush handshake (no pulse loss):
 *   Caller holds `flush` high until `flush_ready` is observed high in the
 *   same cycle. flush_ready==1 when:
 *     - byte_idx==0 (no partial work; flush is a no-op, immediately ack'd)
 *     - OR partial bytes exist AND the output register is free, so the
 *       partial word can be emitted this cycle.
 */
`default_nettype none

module byte_to_word_packer (
    input  wire        clk,
    input  wire        rst_n,

    // Byte input
    input  wire [7:0]  in_byte,
    input  wire        in_byte_valid,
    output wire        in_byte_ready,
    input  wire        flush,           // hold high until flush_ready=1
    output wire        flush_ready,     // 1 when flush will be consumed this cycle

    // 64-bit word output
    output reg  [63:0] out_word,
    output reg  [3:0]  out_word_bytes,
    output reg         out_word_valid,
    input  wire        out_word_ready
);

    reg [2:0] byte_idx;     // 0..7, position of NEXT byte
    reg [63:0] accumulator;

    // Accept a new byte only when the output isn't blocked
    // (i.e., we have a slot to fill, or the current word has been consumed).
    assign in_byte_ready = !out_word_valid;
    // flush_ready: caller can drop `flush` next cycle when this is high
    // - no partial bytes -> immediate ack, no-op
    // - partial bytes AND output free -> partial word will emit this cycle
    assign flush_ready = (byte_idx == 3'd0) || (!out_word_valid);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_idx       <= 3'd0;
            accumulator    <= 64'd0;
            out_word       <= 64'd0;
            out_word_bytes <= 4'd0;
            out_word_valid <= 1'b0;
        end else begin
            // Clear valid when downstream consumes
            if (out_word_valid && out_word_ready) begin
                out_word_valid <= 1'b0;
                out_word       <= 64'd0;
                out_word_bytes <= 4'd0;
                accumulator    <= 64'd0;
                byte_idx       <= 3'd0;
            end

            // Accept a byte
            if (in_byte_valid && in_byte_ready) begin
                // Place byte into accumulator at byte_idx
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
                    // 8th byte: emit full word
                    // Build the word using accumulator + this byte in the
                    // top position. We can't read accumulator combinationally
                    // with the just-written value, so build it explicitly.
                    out_word       <= {in_byte, accumulator[55:0]};
                    out_word_bytes <= 4'd8;
                    out_word_valid <= 1'b1;
                    byte_idx       <= 3'd0;
                end else begin
                    byte_idx <= byte_idx + 1'b1;
                end
            end

            // Flush handshake: emit partial word when caller asserts flush
            // and we have partial bytes and the output is free.
            if (flush && flush_ready && byte_idx != 3'd0) begin
                out_word       <= accumulator;
                out_word_bytes <= {1'b0, byte_idx};
                out_word_valid <= 1'b1;
                byte_idx       <= 3'd0;
                accumulator    <= 64'd0;
            end
        end
    end

endmodule
