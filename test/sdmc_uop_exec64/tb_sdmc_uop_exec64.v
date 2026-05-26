`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_uop_exec64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    reg        host_wr_en = 1'b0;
    reg [3:0]  host_wr_addr = 4'd0;
    reg [63:0] host_wr_data = 64'd0;
    wire       host_ready;

    reg        cmd_valid = 1'b0;
    wire       cmd_ready;
    reg [3:0]  cmd_op = 4'd0;
    reg [3:0]  cmd_dst = 4'd0;
    reg [3:0]  cmd_src_a = 4'd0;
    reg [3:0]  cmd_src_b = 4'd0;
    reg [3:0]  cmd_n = 4'd0;
    reg        cmd_writeback = 1'b0;

    wire       busy;
    wire       done;
    wire [63:0] result;

    wire [63:0] r0;
    wire [63:0] r1;
    wire [63:0] r2;
    wire [63:0] r3;
    wire [63:0] r4;

    always #5 clk = ~clk;

    sdmc_uop_exec64 dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .host_wr_en(host_wr_en),
        .host_wr_addr(host_wr_addr),
        .host_wr_data(host_wr_data),
        .host_ready(host_ready),

        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_op(cmd_op),
        .cmd_dst(cmd_dst),
        .cmd_src_a(cmd_src_a),
        .cmd_src_b(cmd_src_b),
        .cmd_n(cmd_n),
        .cmd_writeback(cmd_writeback),

        .busy(busy),
        .done(done),
        .result(result),

        .r0(r0),
        .r1(r1),
        .r2(r2),
        .r3(r3),
        .r4(r4)
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

    task host_write;
        input [3:0] addr;
        input [63:0] data;
        begin
            if (!host_ready) begin
                $display("FAIL host not ready");
                $finish;
            end
            host_wr_addr = addr;
            host_wr_data = data;
            host_wr_en   = 1'b1;
            tick();
            host_wr_en   = 1'b0;
            host_wr_addr = 4'd0;
            host_wr_data = 64'd0;
        end
    endtask

    task issue;
        input [3:0]  op;
        input [3:0]  dst;
        input [3:0]  src_a;
        input [3:0]  src_b;
        input [3:0]  n;
        input        wb;
        input [63:0] exp_result;
        integer guard;
        begin
            guard = 0;
            while (!cmd_ready) begin
                tick();
                guard = guard + 1;
                if (guard > 50) begin
                    $display("FAIL timeout waiting cmd_ready");
                    $finish;
                end
            end

            cmd_op        = op;
            cmd_dst       = dst;
            cmd_src_a     = src_a;
            cmd_src_b     = src_b;
            cmd_n         = n;
            cmd_writeback = wb;
            cmd_valid     = 1'b1;
            tick();
            cmd_valid     = 1'b0;

            guard = 0;
            while (!done) begin
                tick();
                guard = guard + 1;
                if (guard > 100) begin
                    $display("FAIL timeout waiting done");
                    $finish;
                end
            end

            if (result !== exp_result) begin
                $display("FAIL result got=%h expected=%h", result, exp_result);
                $finish;
            end

            tick();

            if (!cmd_ready || busy) begin
                $display("FAIL executor did not return idle");
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_uop_exec64.vcd");
        $dumpvars(0, tb_sdmc_uop_exec64);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        host_write(4'd1, 64'hffff_0000_aaaa_5555);
        host_write(4'd2, 64'h00ff_00ff_0f0f_f0f0);

        issue(OP_XOR, 4'd3, 4'd1, 4'd2, 4'd0, 1'b1, 64'hff00_00ff_a5a5_a5a5);

        if (r3 !== 64'hff00_00ff_a5a5_a5a5) begin
            $display("FAIL writeback r3=%h", r3);
            $finish;
        end

        issue(OP_MASK_N, 4'd4, 4'd1, 4'd0, 4'd3, 1'b1, 64'h0000_0000_00aa_5555);

        if (r4 !== 64'h0000_0000_00aa_5555) begin
            $display("FAIL writeback r4=%h", r4);
            $finish;
        end

        host_write(4'd1, 64'h1122_3344_5566_7788);

        issue(OP_DEC_KEEP, 4'd0, 4'd1, 4'd0, 4'd3, 1'b1, 64'h1122_3344_5500_0000);

        if (r0 !== 64'h1122_3344_5500_0000) begin
            $display("FAIL dec_keep r0=%h", r0);
            $finish;
        end

        issue(OP_LOAD_PAD, 4'd0, 4'd1, 4'd0, 4'd3, 1'b0, 64'h0000_0000_0166_7788);

        if (r0 !== 64'h1122_3344_5500_0000) begin
            $display("FAIL no-writeback changed r0=%h", r0);
            $finish;
        end

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (r0 !== 64'd0 || r1 !== 64'd0 || r2 !== 64'd0 || r3 !== 64'd0 || r4 !== 64'd0) begin
            $display("FAIL clear registers");
            $finish;
        end

        $display("PASS sdmc_uop_exec64");
        $finish;
    end

endmodule

`default_nettype wire
