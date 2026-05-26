`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_micro_smoke;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;

    always #5 clk = ~clk;

    wire busy;
    wire done;

    wire        issue_valid;
    wire [2:0]  issue_op;
    wire [2:0]  issue_lane;
    wire [63:0] issue_wdata;
    wire        issue_ready;

    wire [63:0] read_data;
    wire        read_valid;
    wire        perm_busy;
    wire        perm_done;

    wire [63:0] result_x0;

    wire [63:0] dbg_x0;
    wire [63:0] dbg_x1;
    wire [63:0] dbg_x2;
    wire [63:0] dbg_x3;
    wire [63:0] dbg_x4;

    localparam [63:0] EXPECT_X0 = 64'h6755_27c2_a0e8_de03;

    sdmc_micro_smoke u_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .issue_valid(issue_valid),
        .issue_op(issue_op),
        .issue_lane(issue_lane),
        .issue_wdata(issue_wdata),
        .issue_ready(issue_ready),
        .read_data(read_data),
        .read_valid(read_valid),
        .perm_done(perm_done),
        .result_x0(result_x0)
    );

    sdmc_ascon_core64 u_core (
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

    initial begin
        $dumpfile("tb_sdmc_micro_smoke.vcd");
        $dumpvars(0, tb_sdmc_micro_smoke);

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        wait (done);
        @(negedge clk);

        if (result_x0 !== EXPECT_X0) begin
            $display("FAIL result_x0 got=%h expected=%h", result_x0, EXPECT_X0);
            $finish;
        end

        $display("PASS sdmc_micro_smoke result_x0=%h", result_x0);
        $finish;
    end

endmodule

`default_nettype wire
