`default_nettype none

module sdmc_word_to_byte (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire [63:0] in_word,
    input  wire [3:0]  in_count,
    input  wire        in_valid,
    output wire        in_ready,

    output wire [7:0]  out_byte,
    output wire        out_valid,
    input  wire        out_ready
);

    reg [63:0] word_buf;
    reg [3:0]  remaining;
    reg [2:0]  index;
    reg        active;

    assign in_ready  = !active;
    assign out_valid = active;

    reg [7:0] out_byte_r;
    assign out_byte = out_byte_r;

    always @* begin
        case (index)
            3'd0: out_byte_r = word_buf[7:0];
            3'd1: out_byte_r = word_buf[15:8];
            3'd2: out_byte_r = word_buf[23:16];
            3'd3: out_byte_r = word_buf[31:24];
            3'd4: out_byte_r = word_buf[39:32];
            3'd5: out_byte_r = word_buf[47:40];
            3'd6: out_byte_r = word_buf[55:48];
            3'd7: out_byte_r = word_buf[63:56];
            default: out_byte_r = 8'd0;
        endcase
    end

    wire accept = in_valid && in_ready;
    wire emit   = out_valid && out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_buf  <= 64'd0;
            remaining <= 4'd0;
            index     <= 3'd0;
            active    <= 1'b0;
        end else if (clear) begin
            word_buf  <= 64'd0;
            remaining <= 4'd0;
            index     <= 3'd0;
            active    <= 1'b0;
        end else begin
            if (accept) begin
                word_buf <= in_word;
                index    <= 3'd0;
                if (in_count == 4'd0) begin
                    remaining <= 4'd0;
                    active    <= 1'b0;
                end else if (in_count > 4'd8) begin
                    remaining <= 4'd8;
                    active    <= 1'b1;
                end else begin
                    remaining <= in_count;
                    active    <= 1'b1;
                end
            end else if (emit) begin
                if (remaining == 4'd1) begin
                    remaining <= 4'd0;
                    index     <= 3'd0;
                    active    <= 1'b0;
                end else begin
                    remaining <= remaining - 4'd1;
                    index     <= index + 3'd1;
                end
            end
        end
    end

endmodule

`default_nettype wire
