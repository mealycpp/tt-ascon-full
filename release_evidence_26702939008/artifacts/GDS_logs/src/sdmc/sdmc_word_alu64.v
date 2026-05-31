`default_nettype none

module sdmc_word_alu64 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        start,
    input  wire [3:0]  op,
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [3:0]  n,

    output reg  [63:0] y,
    output reg         valid
);

    localparam OP_ZERO     = 4'd0;
    localparam OP_PASS_A   = 4'd1;
    localparam OP_XOR      = 4'd2;
    localparam OP_MASK_N   = 4'd3;
    localparam OP_PAD_N    = 4'd4;
    localparam OP_LOAD_PAD = 4'd5;
    localparam OP_DEC_KEEP = 4'd6;
    localparam OP_XOR_KEEP = 4'd7;

    function [63:0] mask_n;
        input [3:0] cnt;
        begin
            case (cnt)
                4'd0: mask_n = 64'h0000_0000_0000_0000;
                4'd1: mask_n = 64'h0000_0000_0000_00ff;
                4'd2: mask_n = 64'h0000_0000_0000_ffff;
                4'd3: mask_n = 64'h0000_0000_00ff_ffff;
                4'd4: mask_n = 64'h0000_0000_ffff_ffff;
                4'd5: mask_n = 64'h0000_00ff_ffff_ffff;
                4'd6: mask_n = 64'h0000_ffff_ffff_ffff;
                4'd7: mask_n = 64'h00ff_ffff_ffff_ffff;
                default: mask_n = 64'hffff_ffff_ffff_ffff;
            endcase
        end
    endfunction

    function [63:0] pad_n;
        input [3:0] cnt;
        begin
            case (cnt)
                4'd0: pad_n = 64'h0000_0000_0000_0001;
                4'd1: pad_n = 64'h0000_0000_0000_0100;
                4'd2: pad_n = 64'h0000_0000_0001_0000;
                4'd3: pad_n = 64'h0000_0000_0100_0000;
                4'd4: pad_n = 64'h0000_0001_0000_0000;
                4'd5: pad_n = 64'h0000_0100_0000_0000;
                4'd6: pad_n = 64'h0001_0000_0000_0000;
                4'd7: pad_n = 64'h0100_0000_0000_0000;
                default: pad_n = 64'h0000_0000_0000_0000;
            endcase
        end
    endfunction

    wire [63:0] mask_w = mask_n(n);
    wire [63:0] pad_w  = pad_n(n);

    reg [63:0] result_w;

    always @* begin
        case (op)
            OP_ZERO:     result_w = 64'd0;
            OP_PASS_A:   result_w = a;
            OP_XOR:      result_w = a ^ b;
            OP_MASK_N:   result_w = a & mask_w;
            OP_PAD_N:    result_w = pad_w;
            OP_LOAD_PAD: result_w = (a & mask_w) ^ pad_w;
            OP_DEC_KEEP: result_w = (n == 4'd8) ? 64'd0 : (a & ~mask_w);
            OP_XOR_KEEP: result_w = a ^ b;
            default:     result_w = 64'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= 64'd0;
            valid <= 1'b0;
        end else if (clear) begin
            y     <= 64'd0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (start) begin
                y     <= result_w;
                valid <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
