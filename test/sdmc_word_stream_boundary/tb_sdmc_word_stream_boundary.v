`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_word_stream_boundary;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    always #5 clk = ~clk;

    reg [7:0] byte_in = 8'd0;
    reg       byte_in_valid = 1'b0;
    wire      byte_in_ready;
    reg       byte_in_flush = 1'b0;

    wire [7:0] byte_out;
    wire       byte_out_valid;
    reg        byte_out_ready = 1'b0;

    wire       word_fifo_full;
    wire       word_fifo_empty;
    wire [2:0] word_fifo_count;

    sdmc_word_stream_boundary #(
        .FIFO_DEPTH(4),
        .FIFO_AW(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .byte_in(byte_in),
        .byte_in_valid(byte_in_valid),
        .byte_in_ready(byte_in_ready),
        .byte_in_flush(byte_in_flush),
        .byte_out(byte_out),
        .byte_out_valid(byte_out_valid),
        .byte_out_ready(byte_out_ready),
        .word_fifo_full(word_fifo_full),
        .word_fifo_empty(word_fifo_empty),
        .word_fifo_count(word_fifo_count)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task send_byte;
        input [7:0] b;
        integer guard;
        begin
            guard = 0;
            while (!byte_in_ready) begin
                tick();
                guard = guard + 1;
                if (guard > 100) begin
                    $display("FAIL timeout waiting for byte_in_ready");
                    $finish;
                end
            end
            byte_in = b;
            byte_in_valid = 1'b1;
            tick();
            byte_in_valid = 1'b0;
            byte_in = 8'd0;
        end
    endtask

    task flush_input;
        begin
            byte_in_flush = 1'b1;
            tick();
            byte_in_flush = 1'b0;
        end
    endtask

    task expect_byte;
        input [7:0] exp;
        integer guard;
        begin
            guard = 0;
            byte_out_ready = 1'b1;
            while (!byte_out_valid) begin
                tick();
                guard = guard + 1;
                if (guard > 200) begin
                    $display("FAIL timeout waiting for byte_out_valid expected=%02x", exp);
                    $finish;
                end
            end
            if (byte_out !== exp) begin
                $display("FAIL byte_out got=%02x expected=%02x", byte_out, exp);
                $finish;
            end
            tick();
            byte_out_ready = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_word_stream_boundary.vcd");
        $dumpvars(0, tb_sdmc_word_stream_boundary);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h03);
        send_byte(8'h04);
        send_byte(8'h05);
        send_byte(8'h06);
        send_byte(8'h07);

        expect_byte(8'h00);
        expect_byte(8'h01);
        expect_byte(8'h02);
        expect_byte(8'h03);
        expect_byte(8'h04);
        expect_byte(8'h05);
        expect_byte(8'h06);
        expect_byte(8'h07);

        send_byte(8'h08);
        send_byte(8'h09);
        flush_input();

        expect_byte(8'h08);
        expect_byte(8'h09);

        // Backpressure check: hold output stalled while a full word enters.
        byte_out_ready = 1'b0;
        send_byte(8'ha0);
        send_byte(8'ha1);
        send_byte(8'ha2);
        send_byte(8'ha3);
        send_byte(8'ha4);
        send_byte(8'ha5);
        send_byte(8'ha6);
        send_byte(8'ha7);

        repeat (5) tick();

        if (!byte_out_valid) begin
            $display("FAIL stalled output did not hold valid byte");
            $finish;
        end
        if (byte_out !== 8'ha0) begin
            $display("FAIL stalled output got=%02x expected=a0", byte_out);
            $finish;
        end

        expect_byte(8'ha0);
        expect_byte(8'ha1);
        expect_byte(8'ha2);
        expect_byte(8'ha3);
        expect_byte(8'ha4);
        expect_byte(8'ha5);
        expect_byte(8'ha6);
        expect_byte(8'ha7);

        $display("PASS sdmc_word_stream_boundary");
        $finish;
    end

endmodule

`default_nettype wire
