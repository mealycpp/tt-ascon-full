`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_core64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    reg        issue_valid;
    reg [2:0]  issue_op;
    reg [2:0]  issue_lane;
    reg [63:0] issue_wdata;

    wire        issue_ready;
    wire [63:0] read_data;
    wire        read_valid;
    wire        perm_busy;
    wire        perm_done;

    wire [63:0] dbg_x0;
    wire [63:0] dbg_x1;
    wire [63:0] dbg_x2;
    wire [63:0] dbg_x3;
    wire [63:0] dbg_x4;

    localparam OP_NOP    = 3'd0;
    localparam OP_CLEAR  = 3'd1;
    localparam OP_LOAD   = 3'd2;
    localparam OP_XOR    = 3'd3;
    localparam OP_READ   = 3'd4;
    localparam OP_PERM12 = 3'd5;

    sdmc_ascon_core64 dut (
        .clk(clk),
        .rst_n(rst_n),
        .issue_valid(issue_valid),
        .issue_op(issue_op),
        .issue_lane(issue_lane),
        .issue_wdata(issue_wdata),
        .issue_ready(issue_ready),
        .read_data(read_data),
        .read_valid(read_valid),
        .perm_busy(perm_busy),
        .perm_done(perm_done),
        .dbg_x0(dbg_x0),
        .dbg_x1(dbg_x1),
        .dbg_x2(dbg_x2),
        .dbg_x3(dbg_x3),
        .dbg_x4(dbg_x4)
    );

    task issue;
        input [2:0] op;
        input [2:0] lane;
        input [63:0] data;
        begin
            while (!issue_ready) @(negedge clk);
            @(negedge clk);
            issue_valid = 1'b1;
            issue_op    = op;
            issue_lane  = lane;
            issue_wdata = data;
            @(negedge clk);
            issue_valid = 1'b0;
            issue_op    = OP_NOP;
            issue_lane  = 3'd0;
            issue_wdata = 64'd0;
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_core64.vcd");
        $dumpvars(0, tb_sdmc_core64);

        issue_valid = 1'b0;
        issue_op    = OP_NOP;
        issue_lane  = 3'd0;
        issue_wdata = 64'd0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        issue(OP_CLEAR, 3'd0, 64'd0);
        issue(OP_LOAD,  3'd0, 64'h1111_2222_3333_4444);
        issue(OP_XOR,   3'd0, 64'h0000_0000_0000_00ff);
        issue(OP_READ,  3'd0, 64'd0);

        #1;
        if (!read_valid || read_data != 64'h1111_2222_3333_44bb) begin
            $display("FAIL read x0 got=%h valid=%b", read_data, read_valid);
            $finish;
        end

        issue(OP_PERM12, 3'd0, 64'd0);
        wait (perm_done);
        @(negedge clk);

        issue(OP_READ, 3'd0, 64'd0);
        #1;
        if (!read_valid) begin
            $display("FAIL read after perm");
            $finish;
        end

        $display("PASS sdmc_core64");
        $finish;
    end

endmodule

`default_nettype wire
