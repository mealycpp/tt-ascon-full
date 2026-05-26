`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_uop_exec64p;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    always #5 clk = ~clk;

    reg        host_wr_en = 1'b0;
    reg [3:0]  host_wr_addr = 4'd0;
    reg [63:0] host_wr_data = 64'd0;
    wire       host_ready;

    reg        cmd_valid = 1'b0;
    wire       cmd_ready;
    reg [1:0]  cmd_type = 2'd0;
    reg [3:0]  cmd_op = 4'd0;
    reg [3:0]  cmd_dst = 4'd0;
    reg [3:0]  cmd_src_a = 4'd0;
    reg [3:0]  cmd_src_b = 4'd0;
    reg [3:0]  cmd_n = 4'd0;
    reg        cmd_writeback = 1'b0;
    reg [2:0]  cmd_perm_lane = 3'd0;
    reg [3:0]  cmd_rounds = 4'd12;

    wire       busy;
    wire       done;
    wire [63:0] result;

    wire [63:0] r0;
    wire [63:0] r1;
    wire [63:0] r2;
    wire [63:0] r3;
    wire [63:0] r4;

    wire [63:0] p0;
    wire [63:0] p1;
    wire [63:0] p2;
    wire [63:0] p3;
    wire [63:0] p4;

    reg          ref_start = 1'b0;
    reg  [3:0]   ref_rounds = 4'd12;
    reg  [319:0] ref_state_in = 320'd0;
    wire [319:0] ref_state_out;
    wire         ref_busy;
    wire         ref_done;

    localparam CMD_ALU      = 2'd0;
    localparam CMD_PERM_WR  = 2'd1;
    localparam CMD_PERM_RUN = 2'd2;
    localparam CMD_PERM_RD  = 2'd3;

    localparam OP_XOR      = 4'd2;
    localparam OP_MASK_N   = 4'd3;
    localparam OP_DEC_KEEP = 4'd6;

    sdmc_uop_exec64p dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .host_wr_en(host_wr_en),
        .host_wr_addr(host_wr_addr),
        .host_wr_data(host_wr_data),
        .host_ready(host_ready),

        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_type(cmd_type),
        .cmd_op(cmd_op),
        .cmd_dst(cmd_dst),
        .cmd_src_a(cmd_src_a),
        .cmd_src_b(cmd_src_b),
        .cmd_n(cmd_n),
        .cmd_writeback(cmd_writeback),
        .cmd_perm_lane(cmd_perm_lane),
        .cmd_rounds(cmd_rounds),

        .busy(busy),
        .done(done),
        .result(result),

        .r0(r0),
        .r1(r1),
        .r2(r2),
        .r3(r3),
        .r4(r4),

        .p0(p0),
        .p1(p1),
        .p2(p2),
        .p3(p3),
        .p4(p4)
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
        input [1:0]  t_type;
        input [3:0]  t_op;
        input [3:0]  t_dst;
        input [3:0]  t_src_a;
        input [3:0]  t_src_b;
        input [3:0]  t_n;
        input        t_wb;
        input [2:0]  t_lane;
        input [3:0]  t_rounds;
        integer guard;
        begin
            guard = 0;
            while (!cmd_ready) begin
                tick();
                guard = guard + 1;
                if (guard > 80) begin
                    $display("FAIL timeout cmd_ready");
                    $finish;
                end
            end

            cmd_type      = t_type;
            cmd_op        = t_op;
            cmd_dst       = t_dst;
            cmd_src_a     = t_src_a;
            cmd_src_b     = t_src_b;
            cmd_n         = t_n;
            cmd_writeback = t_wb;
            cmd_perm_lane = t_lane;
            cmd_rounds    = t_rounds;
            cmd_valid     = 1'b1;
            tick();
            cmd_valid     = 1'b0;

            guard = 0;
            while (!done) begin
                tick();
                guard = guard + 1;
                if (guard > 200) begin
                    $display("FAIL timeout done type=%0d", t_type);
                    $finish;
                end
            end

            tick();

            if (busy || !cmd_ready) begin
                $display("FAIL executor not idle");
                $finish;
            end
        end
    endtask

    task run_ref;
        input [3:0] t_rounds;
        input [319:0] t_state;
        integer guard;
        begin
            ref_rounds   = t_rounds;
            ref_state_in = t_state;
            ref_start    = 1'b1;
            tick();
            ref_start = 1'b0;

            guard = 0;
            while (!ref_done) begin
                tick();
                guard = guard + 1;
                if (guard > 100) begin
                    $display("FAIL timeout ref_done");
                    $finish;
                end
            end

            tick();
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_uop_exec64p.vcd");
        $dumpvars(0, tb_sdmc_uop_exec64p);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        host_write(4'd1, 64'hffff_0000_aaaa_5555);
        host_write(4'd2, 64'h00ff_00ff_0f0f_f0f0);
        issue(CMD_ALU, OP_XOR, 4'd3, 4'd1, 4'd2, 4'd0, 1'b1, 3'd0, 4'd12);

        if (r3 !== 64'hff00_00ff_a5a5_a5a5) begin
            $display("FAIL ALU writeback r3=%h", r3);
            $finish;
        end

        host_write(4'd0, 64'h0123_4567_89ab_cdef);
        host_write(4'd1, 64'h1111_2222_3333_4444);
        host_write(4'd2, 64'h5555_6666_7777_8888);
        host_write(4'd3, 64'h9999_aaaa_bbbb_cccc);
        host_write(4'd4, 64'hdddd_eeee_ffff_0001);

        issue(CMD_PERM_WR, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 1'b0, 3'd0, 4'd12);
        issue(CMD_PERM_WR, 4'd0, 4'd0, 4'd1, 4'd0, 4'd0, 1'b0, 3'd1, 4'd12);
        issue(CMD_PERM_WR, 4'd0, 4'd0, 4'd2, 4'd0, 4'd0, 1'b0, 3'd2, 4'd12);
        issue(CMD_PERM_WR, 4'd0, 4'd0, 4'd3, 4'd0, 4'd0, 1'b0, 3'd3, 4'd12);
        issue(CMD_PERM_WR, 4'd0, 4'd0, 4'd4, 4'd0, 4'd0, 1'b0, 3'd4, 4'd12);

        if (p0 !== 64'h0123_4567_89ab_cdef ||
            p1 !== 64'h1111_2222_3333_4444 ||
            p2 !== 64'h5555_6666_7777_8888 ||
            p3 !== 64'h9999_aaaa_bbbb_cccc ||
            p4 !== 64'hdddd_eeee_ffff_0001) begin
            $display("FAIL perm lane load");
            $finish;
        end

        run_ref(
            4'd12,
            {64'hdddd_eeee_ffff_0001,
             64'h9999_aaaa_bbbb_cccc,
             64'h5555_6666_7777_8888,
             64'h1111_2222_3333_4444,
             64'h0123_4567_89ab_cdef}
        );

        issue(CMD_PERM_RUN, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 1'b0, 3'd0, 4'd12);

        if ({p4, p3, p2, p1, p0} !== ref_state_out) begin
            $display("FAIL perm result mismatch");
            $display("dut=%h", {p4, p3, p2, p1, p0});
            $display("ref=%h", ref_state_out);
            $finish;
        end

        issue(CMD_PERM_RD, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 1'b1, 3'd0, 4'd12);
        issue(CMD_PERM_RD, 4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 1'b1, 3'd1, 4'd12);
        issue(CMD_PERM_RD, 4'd0, 4'd2, 4'd0, 4'd0, 4'd0, 1'b1, 3'd2, 4'd12);
        issue(CMD_PERM_RD, 4'd0, 4'd3, 4'd0, 4'd0, 4'd0, 1'b1, 3'd3, 4'd12);
        issue(CMD_PERM_RD, 4'd0, 4'd4, 4'd0, 4'd0, 4'd0, 1'b1, 3'd4, 4'd12);

        if (r0 !== ref_state_out[63:0] ||
            r1 !== ref_state_out[127:64] ||
            r2 !== ref_state_out[191:128] ||
            r3 !== ref_state_out[255:192] ||
            r4 !== ref_state_out[319:256]) begin
            $display("FAIL perm readback into regfile");
            $finish;
        end

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (r0 !== 64'd0 || r1 !== 64'd0 || r2 !== 64'd0 || r3 !== 64'd0 || r4 !== 64'd0 ||
            p0 !== 64'd0 || p1 !== 64'd0 || p2 !== 64'd0 || p3 !== 64'd0 || p4 !== 64'd0) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_uop_exec64p");
        $finish;
    end

endmodule

`default_nettype wire
