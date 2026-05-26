`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_stream_shell;

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
    reg  core_in_pop = 1'b0;

    reg [`SDMC_TOKEN_W-1:0] core_out_token = {`SDMC_TOKEN_W{1'b0}};
    reg core_out_push = 1'b0;
    wire core_out_full;

    wire [7:0] out_byte;
    wire [3:0] out_kind;
    wire out_last;
    wire out_valid;
    reg  out_ready = 1'b0;

    wire [2:0] in_count;
    wire [2:0] out_count;

    sdmc_stream_shell #(.FIFO_DEPTH(4), .FIFO_AW(2)) dut (
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

    function [`SDMC_TOKEN_W-1:0] pack_token;
        input last;
        input [3:0] kind;
        input [3:0] bytes;
        input [63:0] data;
        begin
            pack_token = {last, kind, bytes, data};
        end
    endfunction

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

    task wait_input_token;
        integer guard;
        begin
            guard = 0;
            while (core_in_empty) begin
                tick();
                guard = guard + 1;
                if (guard > 20) begin
                    $display("FAIL timeout waiting input token");
                    $finish;
                end
            end
        end
    endtask

    task pop_input_token;
        input [`SDMC_TOKEN_W-1:0] exp;
        begin
            wait_input_token();

            if (core_in_token !== exp) begin
                $display("FAIL core input token mismatch");
                $display("got=%h", core_in_token);
                $display("exp=%h", exp);
                $finish;
            end

            core_in_pop = 1'b1;
            tick();
            core_in_pop = 1'b0;
            tick();
        end
    endtask

    task push_output_token;
        input [`SDMC_TOKEN_W-1:0] tok;
        begin
            if (core_out_full) begin
                $display("FAIL output FIFO full");
                $finish;
            end

            core_out_token = tok;
            core_out_push  = 1'b1;
            tick();

            core_out_push  = 1'b0;
            core_out_token = {`SDMC_TOKEN_W{1'b0}};
            tick();
        end
    endtask

    task expect_output_byte;
        input [7:0] exp_byte;
        input [3:0] exp_kind;
        input exp_last;
        integer guard;
        begin
            guard = 0;
            while (!out_valid) begin
                tick();
                guard = guard + 1;
                if (guard > 30) begin
                    $display("FAIL timeout waiting output byte");
                    $finish;
                end
            end

            if (out_byte !== exp_byte || out_kind !== exp_kind || out_last !== exp_last) begin
                $display("FAIL output mismatch got byte=%h kind=%h last=%b exp byte=%h kind=%h last=%b",
                         out_byte, out_kind, out_last, exp_byte, exp_kind, exp_last);
                $finish;
            end

            out_ready = 1'b1;
            tick();
            out_ready = 1'b0;
            tick();
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_stream_shell.vcd");
        $dumpvars(0, tb_sdmc_stream_shell);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        if (!in_ready || !core_in_empty || core_out_full || out_valid) begin
            $display("FAIL reset");
            $finish;
        end

        // Byte ingress should produce one MSG token for "abc".
        send_byte(8'h61, `SDMC_TOK_MSG, 1'b0);
        send_byte(8'h62, `SDMC_TOK_MSG, 1'b0);
        send_byte(8'h63, `SDMC_TOK_MSG, 1'b1);

        pop_input_token(pack_token(1'b1, `SDMC_TOK_MSG, 4'd3, 64'h0000_0000_0063_6261));

        if (!core_in_empty || in_count !== 3'd0) begin
            $display("FAIL input FIFO not empty after pop");
            $finish;
        end

        // Core output token should become bytes "XYZ".
        push_output_token(pack_token(1'b1, `SDMC_TOK_OUT, 4'd3, 64'h0000_0000_005a_5958));

        expect_output_byte(8'h58, `SDMC_TOK_OUT, 1'b0);
        expect_output_byte(8'h59, `SDMC_TOK_OUT, 1'b0);
        expect_output_byte(8'h5a, `SDMC_TOK_OUT, 1'b1);

        if (out_valid || out_count !== 3'd0) begin
            $display("FAIL output FIFO not drained");
            $finish;
        end

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (!in_ready || !core_in_empty || core_out_full || out_valid ||
            in_count !== 3'd0 || out_count !== 3'd0) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_stream_shell");
        $finish;
    end

endmodule

`default_nettype wire
