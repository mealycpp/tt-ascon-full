`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_perm_unit64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    always #5 clk = ~clk;

    reg        host_wr_en = 1'b0;
    reg [2:0]  host_wr_lane = 3'd0;
    reg [63:0] host_wr_data = 64'd0;

    reg        host_rd_en = 1'b0;
    reg [2:0]  host_rd_lane = 3'd0;
    wire [63:0] host_rd_data;
    wire        host_rd_valid;

    reg        start = 1'b0;
    reg [3:0]  rounds = 4'd12;

    wire       host_ready;
    wire       busy;
    wire       done;

    wire [63:0] x0;
    wire [63:0] x1;
    wire [63:0] x2;
    wire [63:0] x3;
    wire [63:0] x4;

    reg          ref_start = 1'b0;
    reg  [3:0]   ref_rounds = 4'd12;
    reg  [319:0] ref_state_in = 320'd0;
    wire [319:0] ref_state_out;
    wire         ref_busy;
    wire         ref_done;

    sdmc_ascon_perm_unit64 dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .host_wr_en(host_wr_en),
        .host_wr_lane(host_wr_lane),
        .host_wr_data(host_wr_data),

        .host_rd_en(host_rd_en),
        .host_rd_lane(host_rd_lane),
        .host_rd_data(host_rd_data),
        .host_rd_valid(host_rd_valid),

        .start(start),
        .rounds(rounds),

        .host_ready(host_ready),
        .busy(busy),
        .done(done),

        .x0(x0),
        .x1(x1),
        .x2(x2),
        .x3(x3),
        .x4(x4)
    );

    ascon_permutation u_ref (
        .clk(clk),
        .rst_n(rst_n),
        .start(ref_start),
        .num_rounds(ref_rounds),
        .state_in(ref_state_in),
        .state_out(ref_state_out),
        .busy(ref_busy),
        .done(ref_done)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task write_lane;
        input [2:0] lane;
        input [63:0] data;
        begin
            if (!host_ready) begin
                $display("FAIL host not ready for write");
                $finish;
            end
            host_wr_lane = lane;
            host_wr_data = data;
            host_wr_en   = 1'b1;
            tick();
            host_wr_en   = 1'b0;
            host_wr_lane = 3'd0;
            host_wr_data = 64'd0;
        end
    endtask

    task read_lane_expect;
        input [2:0] lane;
        input [63:0] exp;
        begin
            host_rd_lane = lane;
            host_rd_en   = 1'b1;
            tick();
            host_rd_en   = 1'b0;
            host_rd_lane = 3'd0;

            if (!host_rd_valid) begin
                $display("FAIL read valid missing lane=%0d", lane);
                $finish;
            end

            if (host_rd_data !== exp) begin
                $display("FAIL read lane=%0d got=%h expected=%h", lane, host_rd_data, exp);
                $finish;
            end

            tick();
        end
    endtask

    task load_state;
        input [63:0] t_x0;
        input [63:0] t_x1;
        input [63:0] t_x2;
        input [63:0] t_x3;
        input [63:0] t_x4;
        begin
            write_lane(3'd0, t_x0);
            write_lane(3'd1, t_x1);
            write_lane(3'd2, t_x2);
            write_lane(3'd3, t_x3);
            write_lane(3'd4, t_x4);
        end
    endtask

    task run_and_compare;
        input [3:0] t_rounds;
        input [319:0] t_state;
        integer guard;
        reg seen_dut;
        reg seen_ref;
        reg [319:0] dut_state;
        begin
            rounds       = t_rounds;
            ref_rounds   = t_rounds;
            ref_state_in = t_state;

            start     = 1'b1;
            ref_start = 1'b1;
            tick();
            start     = 1'b0;
            ref_start = 1'b0;

            seen_dut = 1'b0;
            seen_ref = 1'b0;
            guard = 0;

            while (!(seen_dut && seen_ref)) begin
                if (done)     seen_dut = 1'b1;
                if (ref_done) seen_ref = 1'b1;
                tick();
                guard = guard + 1;
                if (guard > 100) begin
                    $display("FAIL timeout waiting permutation done");
                    $finish;
                end
            end

            dut_state = {x4, x3, x2, x1, x0};

            if (dut_state !== ref_state_out) begin
                $display("FAIL permutation mismatch");
                $display("dut=%h", dut_state);
                $display("ref=%h", ref_state_out);
                $finish;
            end

            if (busy || ref_busy) begin
                $display("FAIL busy stuck");
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_perm_unit64.vcd");
        $dumpvars(0, tb_sdmc_perm_unit64);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        load_state(
            64'h0123_4567_89ab_cdef,
            64'h1111_2222_3333_4444,
            64'h5555_6666_7777_8888,
            64'h9999_aaaa_bbbb_cccc,
            64'hdddd_eeee_ffff_0001
        );

        read_lane_expect(3'd0, 64'h0123_4567_89ab_cdef);
        read_lane_expect(3'd1, 64'h1111_2222_3333_4444);
        read_lane_expect(3'd2, 64'h5555_6666_7777_8888);
        read_lane_expect(3'd3, 64'h9999_aaaa_bbbb_cccc);
        read_lane_expect(3'd4, 64'hdddd_eeee_ffff_0001);

        run_and_compare(
            4'd12,
            {64'hdddd_eeee_ffff_0001,
             64'h9999_aaaa_bbbb_cccc,
             64'h5555_6666_7777_8888,
             64'h1111_2222_3333_4444,
             64'h0123_4567_89ab_cdef}
        );

        load_state(
            64'h0000_0800_00cc_0004,
            64'h0,
            64'h0,
            64'h0,
            64'h0
        );

        run_and_compare(
            4'd12,
            {64'h0,
             64'h0,
             64'h0,
             64'h0,
             64'h0000_0800_00cc_0004}
        );

        load_state(
            64'h0123_4567_89ab_cdef,
            64'h1111_2222_3333_4444,
            64'h5555_6666_7777_8888,
            64'h9999_aaaa_bbbb_cccc,
            64'hdddd_eeee_ffff_0001
        );

        run_and_compare(
            4'd8,
            {64'hdddd_eeee_ffff_0001,
             64'h9999_aaaa_bbbb_cccc,
             64'h5555_6666_7777_8888,
             64'h1111_2222_3333_4444,
             64'h0123_4567_89ab_cdef}
        );

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (x0 !== 64'd0 || x1 !== 64'd0 || x2 !== 64'd0 || x3 !== 64'd0 || x4 !== 64'd0) begin
            $display("FAIL clear state");
            $finish;
        end

        $display("PASS sdmc_perm_unit64");
        $finish;
    end

endmodule

`default_nettype wire
