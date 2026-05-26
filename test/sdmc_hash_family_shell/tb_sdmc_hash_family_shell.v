`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_hash_family_shell;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] in_byte = 8'd0;
    reg [3:0] in_kind = 4'd0;
    reg       in_last = 1'b0;
    reg       in_valid = 1'b0;
    wire      in_ready;

    wire [`SDMC_TOKEN_W-1:0] core_in_token;
    wire core_in_empty;
    wire core_in_pop;

    wire [`SDMC_TOKEN_W-1:0] core_out_token;
    wire core_out_push;
    wire core_out_full;

    wire [7:0] out_byte;
    wire [3:0] out_kind;
    wire out_last;
    wire out_valid;
    reg  out_ready = 1'b0;

    wire [2:0] in_count;
    wire [2:0] out_count;

    reg start = 1'b0;
    wire busy;
    wire done;
    wire error;

    sdmc_stream_shell #(.FIFO_DEPTH(4), .FIFO_AW(2)) u_stream (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .in_byte(in_byte),
        .in_kind(in_kind),
        .in_last(in_last),
        .in_valid(in_valid),
        .in_ready(in_ready),

        .core_in_token(core_in_token),
        .core_in_empty(core_in_empty),
        .core_in_pop(core_in_pop),

        .core_out_token(core_out_token),
        .core_out_push(core_out_push),
        .core_out_full(core_out_full),

        .out_byte(out_byte),
        .out_kind(out_kind),
        .out_last(out_last),
        .out_valid(out_valid),
        .out_ready(out_ready),

        .in_count(in_count),
        .out_count(out_count)
    );

    sdmc_hash_family_shell u_hash (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .start(start),

        .in_token(core_in_token),
        .in_empty(core_in_empty),
        .in_pop(core_in_pop),

        .out_token(core_out_token),
        .out_push(core_out_push),
        .out_full(core_out_full),

        .busy(busy),
        .done(done),
        .error(error)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task send_byte;
        input [7:0] b;
        input [3:0] k;
        input last;
        begin
            if (!in_ready) begin
                $display("FAIL input not ready");
                $finish;
            end

            in_byte  = b;
            in_kind  = k;
            in_last  = last;
            in_valid = 1'b1;
            tick();

            in_valid = 1'b0;
            in_last  = 1'b0;
            in_byte  = 8'd0;
            in_kind  = 4'd0;
            tick();
        end
    endtask

    task expect_output_byte;
        input [7:0] exp_byte;
        input exp_last;
        integer guard;
        begin
            guard = 0;
            while (!out_valid) begin
                tick();
                guard = guard + 1;
                if (guard > 50) begin
                    $display("FAIL timeout waiting output byte");
                    $finish;
                end
            end

            if (out_byte !== exp_byte || out_kind !== `SDMC_TOK_OUT || out_last !== exp_last) begin
                $display("FAIL output byte got byte=%h kind=%h last=%b exp byte=%h kind=%h last=%b",
                         out_byte, out_kind, out_last, exp_byte, `SDMC_TOK_OUT, exp_last);
                $finish;
            end

            out_ready = 1'b1;
            tick();
            out_ready = 1'b0;
            tick();
        end
    endtask

    task wait_done;
        integer guard;
        begin
            guard = 0;
            while (!done) begin
                tick();
                guard = guard + 1;
                if (guard > 200) begin
                    $display("FAIL timeout waiting hash shell done");
                    $finish;
                end
            end
            tick();
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_hash_family_shell.vcd");
        $dumpvars(0, tb_sdmc_hash_family_shell);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        send_byte(8'h61, `SDMC_TOK_MSG, 1'b0);
        send_byte(8'h62, `SDMC_TOK_MSG, 1'b0);
        send_byte(8'h63, `SDMC_TOK_MSG, 1'b1);

        if (core_in_empty || in_count !== 3'd1) begin
            $display("FAIL input token was not created");
            $finish;
        end

        start = 1'b1;
        tick();
        start = 1'b0;

        wait_done();

        if (error) begin
            $display("FAIL hash shell error");
            $finish;
        end

        expect_output_byte(8'h61, 1'b0);
        expect_output_byte(8'h62, 1'b0);
        expect_output_byte(8'h63, 1'b1);

        if (busy || !core_in_empty || in_count !== 3'd0 || out_count !== 3'd0) begin
            $display("FAIL final state busy=%b core_in_empty=%b in_count=%0d out_count=%0d",
                     busy, core_in_empty, in_count, out_count);
            $finish;
        end

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (busy || done || error || out_valid) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_hash_family_shell");
        $finish;
    end

endmodule

`default_nettype wire
