`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_word_io;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    always #5 clk = ~clk;

    reg [7:0] p_in_byte = 8'd0;
    reg       p_in_valid = 1'b0;
    wire      p_in_ready;
    reg       p_flush = 1'b0;
    wire [63:0] p_out_word;
    wire [3:0]  p_out_count;
    wire        p_out_valid;
    reg         p_out_ready = 1'b0;

    sdmc_byte_to_word u_pack (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .in_byte(p_in_byte),
        .in_valid(p_in_valid),
        .in_ready(p_in_ready),
        .flush(p_flush),
        .out_word(p_out_word),
        .out_count(p_out_count),
        .out_valid(p_out_valid),
        .out_ready(p_out_ready)
    );

    reg [63:0] u_in_word = 64'd0;
    reg [3:0]  u_in_count = 4'd0;
    reg        u_in_valid = 1'b0;
    wire       u_in_ready;
    wire [7:0] u_out_byte;
    wire       u_out_valid;
    reg        u_out_ready = 1'b0;

    sdmc_word_to_byte u_unpack (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .in_word(u_in_word),
        .in_count(u_in_count),
        .in_valid(u_in_valid),
        .in_ready(u_in_ready),
        .out_byte(u_out_byte),
        .out_valid(u_out_valid),
        .out_ready(u_out_ready)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task send_byte;
        input [7:0] b;
        begin
            if (!p_in_ready) begin
                $display("FAIL packer not ready");
                $finish;
            end
            p_in_byte  = b;
            p_in_valid = 1'b1;
            tick();
            p_in_valid = 1'b0;
            p_in_byte  = 8'd0;
        end
    endtask

    task consume_packed;
        input [63:0] exp_word;
        input [3:0]  exp_count;
        begin
            if (!p_out_valid) begin
                $display("FAIL packer output not valid");
                $finish;
            end
            if (p_out_word !== exp_word || p_out_count !== exp_count) begin
                $display("FAIL pack got word=%h count=%0d expected=%h count=%0d",
                         p_out_word, p_out_count, exp_word, exp_count);
                $finish;
            end
            p_out_ready = 1'b1;
            tick();
            p_out_ready = 1'b0;
        end
    endtask

    task load_unpack;
        input [63:0] word;
        input [3:0]  count;
        begin
            if (!u_in_ready) begin
                $display("FAIL unpacker not ready");
                $finish;
            end
            u_in_word  = word;
            u_in_count = count;
            u_in_valid = 1'b1;
            tick();
            u_in_valid = 1'b0;
            u_in_word  = 64'd0;
            u_in_count = 4'd0;
        end
    endtask

    task expect_byte;
        input [7:0] exp;
        begin
            if (!u_out_valid) begin
                $display("FAIL unpack output not valid expected=%02x", exp);
                $finish;
            end
            if (u_out_byte !== exp) begin
                $display("FAIL unpack byte got=%02x expected=%02x", u_out_byte, exp);
                $finish;
            end
            u_out_ready = 1'b1;
            tick();
            u_out_ready = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_word_io.vcd");
        $dumpvars(0, tb_sdmc_word_io);

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
        consume_packed(64'h0706050403020100, 4'd8);

        send_byte(8'h08);
        send_byte(8'h09);
        p_flush = 1'b1;
        tick();
        p_flush = 1'b0;
        consume_packed(64'h0000000000000908, 4'd2);

        load_unpack(64'h0706050403020100, 4'd8);
        expect_byte(8'h00);
        expect_byte(8'h01);
        expect_byte(8'h02);
        expect_byte(8'h03);
        expect_byte(8'h04);
        expect_byte(8'h05);
        expect_byte(8'h06);
        expect_byte(8'h07);

        load_unpack(64'h0000000000000908, 4'd2);
        expect_byte(8'h08);
        expect_byte(8'h09);

        if (!u_in_ready) begin
            $display("FAIL unpacker did not return ready");
            $finish;
        end

        $display("PASS sdmc_word_io");
        $finish;
    end

endmodule

`default_nettype wire
