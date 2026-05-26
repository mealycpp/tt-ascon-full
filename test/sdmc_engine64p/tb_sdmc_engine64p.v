`timescale 1ns/1ps
`default_nettype none

`include "sdmc_modes.vh"

module tb_sdmc_engine64p;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg start = 1'b0;

    reg        cfg_wr_en = 1'b0;
    reg [3:0]  cfg_wr_addr = 4'd0;
    reg [63:0] cfg_wr_data = 64'd0;

    reg        host_wr_en = 1'b0;
    reg [3:0]  host_wr_addr = 4'd0;
    reg [63:0] host_wr_data = 64'd0;
    wire       host_ready;

    wire       busy;
    wire       done;

    wire [3:0]  host_mode;
    wire [3:0]  program_id;
    wire        use_cxof;
    wire        is_decrypt;
    wire [15:0] chain_count;
    wire [15:0] msg_len;
    wire [15:0] cs_len;
    wire [15:0] ad_len;
    wire [15:0] out_len;

    wire [63:0] result;
    wire [63:0] r0, r1, r2, r3, r4;
    wire [63:0] p0, p1, p2, p3, p4;

    reg          ref_start = 1'b0;
    reg  [319:0] ref_state_in = 320'd0;
    wire [319:0] ref_state_out;
    wire         ref_done;

    sdmc_engine64p dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .start(start),

        .cfg_wr_en(cfg_wr_en),
        .cfg_wr_addr(cfg_wr_addr),
        .cfg_wr_data(cfg_wr_data),

        .host_wr_en(host_wr_en),
        .host_wr_addr(host_wr_addr),
        .host_wr_data(host_wr_data),
        .host_ready(host_ready),

        .busy(busy),
        .done(done),

        .host_mode(host_mode),
        .program_id(program_id),
        .use_cxof(use_cxof),
        .is_decrypt(is_decrypt),
        .chain_count(chain_count),
        .msg_len(msg_len),
        .cs_len(cs_len),
        .ad_len(ad_len),
        .out_len(out_len),

        .result(result),

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
        .busy(),
        .done(ref_done)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task cfg_write;
        input [3:0] addr;
        input [63:0] data;
        begin
            if (!host_ready) begin
                $display("FAIL config host not ready");
                $finish;
            end
            cfg_wr_addr = addr;
            cfg_wr_data = data;
            cfg_wr_en   = 1'b1;
            tick();
            cfg_wr_en   = 1'b0;
            cfg_wr_addr = 4'd0;
            cfg_wr_data = 64'd0;
            tick();
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
            tick();
        end
    endtask

    task run_engine;
        integer guard;
        begin
            if (busy) begin
                $display("FAIL engine busy before start");
                $finish;
            end

            start = 1'b1;
            tick();
            start = 1'b0;

            guard = 0;
            while (!done) begin
                tick();
                guard = guard + 1;
                if (guard > 1200) begin
                    $display("FAIL timeout engine program_id=%0d", program_id);
                    $finish;
                end
            end

            tick();

            if (busy) begin
                $display("FAIL engine busy stuck");
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
        $dumpfile("tb_sdmc_engine64p.vcd");
        $dumpvars(0, tb_sdmc_engine64p);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        cfg_write(4'd0, {60'd0, `SDMC_HOST_DEBUG_PERM_SMOKE});

        if (program_id !== `SDMC_PROG_PERM_SMOKE) begin
            $display("FAIL debug perm config decode");
            $finish;
        end

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

        run_engine();

        if ({r4,r3,r2,r1,r0} !== ref_state_out) begin
            $display("FAIL engine permutation result");
            $display("got=%h", {r4,r3,r2,r1,r0});
            $display("exp=%h", ref_state_out);
            $finish;
        end

        cfg_write(4'd0, {60'd0, `SDMC_HOST_DEBUG_ALU_SMOKE});

        if (program_id !== `SDMC_PROG_ALU_SMOKE) begin
            $display("FAIL debug alu config decode");
            $finish;
        end

        host_write(4'd0, 64'hffff_0000_aaaa_5555);
        host_write(4'd1, 64'h00ff_00ff_0f0f_f0f0);

        run_engine();

        if (r3 !== 64'hff00_00ff_a5a5_a5a5) begin
            $display("FAIL engine ALU r3=%h", r3);
            $finish;
        end

        cfg_write(4'd0, {60'd0, `SDMC_HOST_CXOF_CHAIN});
        cfg_write(4'd2, 64'd3);
        cfg_write(4'd1, {16'd32, 16'd0, 16'd5, 16'd9});

        if (program_id !== `SDMC_PROG_XOF_CHAIN_FAMILY ||
            use_cxof !== 1'b1 ||
            chain_count !== 16'd3 ||
            msg_len !== 16'd9 ||
            cs_len !== 16'd5 ||
            out_len !== 16'd32) begin
            $display("FAIL config visible through engine");
            $finish;
        end

        cfg_write(4'd0, {60'd0, `SDMC_HOST_AEAD_DEC});

        if (program_id !== `SDMC_PROG_AEAD_FAMILY || is_decrypt !== 1'b1) begin
            $display("FAIL AEAD_DEC visible through engine");
            $finish;
        end

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (program_id !== `SDMC_PROG_HASH_FAMILY ||
            r0 !== 64'd0 || r1 !== 64'd0 || r2 !== 64'd0 || r3 !== 64'd0 || r4 !== 64'd0 ||
            p0 !== 64'd0 || p1 !== 64'd0 || p2 !== 64'd0 || p3 !== 64'd0 || p4 !== 64'd0) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_engine64p");
        $finish;
    end

endmodule

`default_nettype wire
