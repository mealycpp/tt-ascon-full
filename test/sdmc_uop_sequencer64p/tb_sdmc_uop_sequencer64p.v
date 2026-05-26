`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_uop_sequencer64p;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg        host_wr_en = 1'b0;
    reg [3:0]  host_wr_addr = 4'd0;
    reg [63:0] host_wr_data = 64'd0;
    wire       host_ready;

    reg        seq_start = 1'b0;
    reg [1:0]  program_id = 2'd0;

    wire       cmd_valid;
    wire       cmd_ready;
    wire [1:0] cmd_type;
    wire [3:0] cmd_op;
    wire [3:0] cmd_dst;
    wire [3:0] cmd_src_a;
    wire [3:0] cmd_src_b;
    wire [3:0] cmd_n;
    wire       cmd_writeback;
    wire [2:0] cmd_perm_lane;
    wire [3:0] cmd_rounds;

    wire       exec_busy;
    wire       exec_done;
    wire [63:0] result;

    wire       seq_busy;
    wire       seq_done;

    wire [63:0] r0, r1, r2, r3, r4;
    wire [63:0] p0, p1, p2, p3, p4;

    reg          ref_start = 1'b0;
    reg  [319:0] ref_state_in = 320'd0;
    wire [319:0] ref_state_out;
    wire         ref_busy;
    wire         ref_done;

    sdmc_uop_sequencer64p u_seq (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .start(seq_start), .program_id(program_id),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_type(cmd_type), .cmd_op(cmd_op),
        .cmd_dst(cmd_dst), .cmd_src_a(cmd_src_a), .cmd_src_b(cmd_src_b),
        .cmd_n(cmd_n), .cmd_writeback(cmd_writeback),
        .cmd_perm_lane(cmd_perm_lane), .cmd_rounds(cmd_rounds),
        .exec_done(exec_done),
        .busy(seq_busy), .done(seq_done)
    );

    sdmc_uop_exec64p u_exec (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .host_wr_en(host_wr_en), .host_wr_addr(host_wr_addr),
        .host_wr_data(host_wr_data), .host_ready(host_ready),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_type(cmd_type), .cmd_op(cmd_op),
        .cmd_dst(cmd_dst), .cmd_src_a(cmd_src_a), .cmd_src_b(cmd_src_b),
        .cmd_n(cmd_n), .cmd_writeback(cmd_writeback),
        .cmd_perm_lane(cmd_perm_lane), .cmd_rounds(cmd_rounds),
        .busy(exec_busy), .done(exec_done), .result(result),
        .r0(r0), .r1(r1), .r2(r2), .r3(r3), .r4(r4),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4)
    );

    ascon_permutation u_ref (
        .clk(clk),
        .rst_n(rst_n),
        .start(ref_start),
        .num_rounds(4'd12),
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

    task run_seq;
        input [1:0] pid;
        integer guard;
        begin
            program_id = pid;
            seq_start = 1'b1;
            tick();
            seq_start = 1'b0;

            guard = 0;
            while (!seq_done) begin
                tick();
                guard = guard + 1;
                if (guard > 800) begin
                    $display("FAIL timeout seq_done pid=%0d", pid);
                    $finish;
                end
            end
            tick();

            if (seq_busy || exec_busy) begin
                $display("FAIL busy stuck after sequence");
                $finish;
            end
        end
    endtask

    task run_ref;
        input [319:0] st;
        integer guard;
        begin
            ref_state_in = st;
            ref_start = 1'b1;
            tick();
            ref_start = 1'b0;

            guard = 0;
            while (!ref_done) begin
                tick();
                guard = guard + 1;
                if (guard > 120) begin
                    $display("FAIL timeout ref");
                    $finish;
                end
            end
            tick();
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_uop_sequencer64p.vcd");
        $dumpvars(0, tb_sdmc_uop_sequencer64p);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        host_write(4'd0, 64'h0123_4567_89ab_cdef);
        host_write(4'd1, 64'h1111_2222_3333_4444);
        host_write(4'd2, 64'h5555_6666_7777_8888);
        host_write(4'd3, 64'h9999_aaaa_bbbb_cccc);
        host_write(4'd4, 64'hdddd_eeee_ffff_0001);

        run_ref({64'hdddd_eeee_ffff_0001,
                 64'h9999_aaaa_bbbb_cccc,
                 64'h5555_6666_7777_8888,
                 64'h1111_2222_3333_4444,
                 64'h0123_4567_89ab_cdef});

        run_seq(2'd0);

        if ({r4,r3,r2,r1,r0} !== ref_state_out) begin
            $display("FAIL sequenced permutation result");
            $display("got=%h", {r4,r3,r2,r1,r0});
            $display("exp=%h", ref_state_out);
            $finish;
        end

        host_write(4'd0, 64'hffff_0000_aaaa_5555);
        host_write(4'd1, 64'h00ff_00ff_0f0f_f0f0);

        run_seq(2'd1);

        if (r3 !== 64'hff00_00ff_a5a5_a5a5) begin
            $display("FAIL sequenced ALU r3=%h", r3);
            $finish;
        end

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (r0 !== 64'd0 || p0 !== 64'd0) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_uop_sequencer64p");
        $finish;
    end

endmodule

`default_nettype wire
