`default_nettype none

module sdmc_byte_to_word (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire [7:0]  in_byte,
    input  wire        in_valid,
    output wire        in_ready,

    input  wire        flush,

    output reg  [63:0] out_word,
    output reg  [3:0]  out_count,
    output reg         out_valid,
    input  wire        out_ready
);

    reg [63:0] pack_buf;
    reg [3:0]  byte_count;

    assign in_ready = !out_valid;

    wire in_fire  = in_valid && in_ready;
    wire out_fire = out_valid && out_ready;

    reg [63:0] pack_next;

    always @* begin
        pack_next = pack_buf;
        case (byte_count)
            4'd0: pack_next[7:0]   = in_byte;
            4'd1: pack_next[15:8]  = in_byte;
            4'd2: pack_next[23:16] = in_byte;
            4'd3: pack_next[31:24] = in_byte;
            4'd4: pack_next[39:32] = in_byte;
            4'd5: pack_next[47:40] = in_byte;
            4'd6: pack_next[55:48] = in_byte;
            4'd7: pack_next[63:56] = in_byte;
            default: pack_next = pack_buf;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pack_buf   <= 64'd0;
            byte_count <= 4'd0;
            out_word   <= 64'd0;
            out_count  <= 4'd0;
            out_valid  <= 1'b0;
        end else if (clear) begin
            pack_buf   <= 64'd0;
            byte_count <= 4'd0;
            out_word   <= 64'd0;
            out_count  <= 4'd0;
            out_valid  <= 1'b0;
        end else begin
            if (out_fire) begin
                out_valid <= 1'b0;
                out_word  <= 64'd0;
                out_count <= 4'd0;
            end

            if (!out_valid) begin
                if (in_fire) begin
                    if (byte_count == 4'd7) begin
                        out_word   <= pack_next;
                        out_count  <= 4'd8;
                        out_valid  <= 1'b1;
                        pack_buf   <= 64'd0;
                        byte_count <= 4'd0;
                    end else begin
                        pack_buf   <= pack_next;
                        byte_count <= byte_count + 4'd1;
                    end
                end else if (flush && (byte_count != 4'd0)) begin
                    out_word   <= pack_buf;
                    out_count  <= byte_count;
                    out_valid  <= 1'b1;
                    pack_buf   <= 64'd0;
                    byte_count <= 4'd0;
                end
            end
        end
    end

endmodule

`default_nettype wire
