`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_word_alu64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    reg        start = 1'b0;
    reg [3:0]  op = 4'd0;
    reg [63:0] a = 64'd0;
    reg [63:0] b = 64'd0;
    reg [3:0]  n = 4'd0;

    wire [63:0] y;
    wire        valid;

    always #5 clk = ~clk;

    sdmc_word_alu64 dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .op(op),
        .a(a),
        .b(b),
        .n(n),
        .y(y),
        .valid(valid)
    );

    localparam OP_ZERO     = 4'd0;
    localparam OP_PASS_A   = 4'd1;
    localparam OP_XOR      = 4'd2;
    localparam OP_MASK_N   = 4'd3;
    localparam OP_PAD_N    = 4'd4;
    localparam OP_LOAD_PAD = 4'd5;
    localparam OP_DEC_KEEP = 4'd6;
    localparam OP_XOR_KEEP = 4'd7;

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task run_op;
        input [3:0]  t_op;
        input [63:0] t_a;
        input [63:0] t_b;
        input [3:0]  t_n;
        input [63:0] exp;
        begin
            op = t_op;
            a = t_a;
            b = t_b;
            n = t_n;
            start = 1'b1;
            tick();
            start = 1'b0;

            if (!valid) begin
                $display("FAIL valid missing op=%0d", t_op);
                $finish;
            end

            if (y !== exp) begin
                $display("FAIL op=%0d y=%h exp=%h", t_op, y, exp);
                $finish;
            end

            tick();

            if (valid) begin
                $display("FAIL valid should pulse for one cycle");
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_word_alu64.vcd");
        $dumpvars(0, tb_sdmc_word_alu64);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        run_op(OP_ZERO,     64'hffff_ffff_ffff_ffff, 64'h1234, 4'd0, 64'h0000_0000_0000_0000);
        run_op(OP_PASS_A,   64'h0123_4567_89ab_cdef, 64'h0,    4'd0, 64'h0123_4567_89ab_cdef);
        run_op(OP_XOR,      64'hffff_0000_aaaa_5555, 64'h00ff_00ff_0f0f_f0f0, 4'd0, 64'hff00_00ff_a5a5_a5a5);

        run_op(OP_MASK_N,   64'h1122_3344_5566_7788, 64'h0, 4'd0, 64'h0000_0000_0000_0000);
        run_op(OP_MASK_N,   64'h1122_3344_5566_7788, 64'h0, 4'd3, 64'h0000_0000_0066_7788);
        run_op(OP_MASK_N,   64'h1122_3344_5566_7788, 64'h0, 4'd8, 64'h1122_3344_5566_7788);

        run_op(OP_PAD_N,    64'h0, 64'h0, 4'd0, 64'h0000_0000_0000_0001);
        run_op(OP_PAD_N,    64'h0, 64'h0, 4'd3, 64'h0000_0000_0100_0000);
        run_op(OP_PAD_N,    64'h0, 64'h0, 4'd7, 64'h0100_0000_0000_0000);
        run_op(OP_PAD_N,    64'h0, 64'h0, 4'd8, 64'h0000_0000_0000_0000);

        run_op(OP_LOAD_PAD, 64'h1122_3344_5566_7788, 64'h0, 4'd3, 64'h0000_0000_0166_7788);

        run_op(OP_DEC_KEEP, 64'h1122_3344_5566_7788, 64'h0, 4'd3, 64'h1122_3344_5500_0000);
        run_op(OP_DEC_KEEP, 64'h1122_3344_5566_7788, 64'h0, 4'd8, 64'h0000_0000_0000_0000);

        run_op(OP_XOR_KEEP, 64'h1122_3344_5500_0000, 64'h0000_0000_0066_7788, 4'd0, 64'h1122_3344_5566_7788);

        clear = 1'b1;
        tick();
        clear = 1'b0;

        if (valid || y !== 64'd0) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_word_alu64");
        $finish;
    end

endmodule

`default_nettype wire
