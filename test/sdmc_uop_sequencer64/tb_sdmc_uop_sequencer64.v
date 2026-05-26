`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_uop_sequencer64;

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
    wire [3:0] cmd_op;
    wire [3:0] cmd_dst;
    wire [3:0] cmd_src_a;
    wire [3:0] cmd_src_b;
    wire [3:0] cmd_n;
    wire       cmd_writeback;

    wire       exec_busy;
    wire       exec_done;
    wire [63:0] result;

    wire       seq_busy;
    wire       seq_done;

    wire [63:0] r0;
    wire [63:0] r1;
    wire [63:0] r2;
    wire [63:0] r3;
    wire [63:0] r4;

    sdmc_uop_sequencer64 u_seq (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(seq_start),
        .program_id(program_id),

        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_op(cmd_op),
        .cmd_dst(cmd_dst),
        .cmd_src_a(cmd_src_a),
        .cmd_src_b(cmd_src_b),
        .cmd_n(cmd_n),
        .cmd_writeback(cmd_writeback),

        .exec_done(exec_done),

        .busy(seq_busy),
        .done(seq_done)
    );

    sdmc_uop_exec64 u_exec (
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

        .busy(exec_busy),
        .done(exec_done),
        .result(result),

        .r0(r0),
        .r1(r1),
        .r2(r2),
        .r3(r3),
        .r4(r4)
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

    task run_program;
        input [1:0] pid;
        integer guard;
        begin
            program_id = pid;
            seq_start  = 1'b1;
            tick();
            seq_start = 1'b0;

            guard = 0;
            while (!seq_done) begin
                tick();
                guard = guard + 1;
                if (guard > 300) begin
                    $display("FAIL timeout waiting seq_done pid=%0d", pid);
                    $finish;
                end
            end

            tick();

            if (seq_busy || exec_busy) begin
                $display("FAIL not idle after program");
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_uop_sequencer64.vcd");
        $dumpvars(0, tb_sdmc_uop_sequencer64);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        host_write(4'd1, 64'h1122_3344_5566_7788);
        host_write(4'd2, 64'h0102_0304_0506_0708);

        run_program(2'd0);

        if (r3 !== 64'h1020_3040_5060_7080) begin
            $display("FAIL program0 r3=%h", r3);
            $finish;
        end

        if (r4 !== 64'h0000_0000_0060_7080) begin
            $display("FAIL program0 r4=%h", r4);
            $finish;
        end

        if (r0 !== 64'h1122_3344_5500_0000) begin
            $display("FAIL program0 r0=%h", r0);
            $finish;
        end

        host_write(4'd1, 64'h1122_3344_5566_7788);
        host_write(4'd2, 64'h0000_0000_0000_00ff);

        run_program(2'd1);

        if (r3 !== 64'h0000_0000_0166_7788) begin
            $display("FAIL program1 r3=%h", r3);
            $finish;
        end

        if (r4 !== 64'h0000_0000_0166_7777) begin
            $display("FAIL program1 r4=%h", r4);
            $finish;
        end

        if (r0 !== 64'h0000_0000_0166_7777) begin
            $display("FAIL program1 r0=%h", r0);
            $finish;
        end

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (r0 !== 64'd0 || r1 !== 64'd0 || r2 !== 64'd0 || r3 !== 64'd0 || r4 !== 64'd0) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_uop_sequencer64");
        $finish;
    end

endmodule

`default_nettype wire
