`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_stream_egress;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg [`SDMC_TOKEN_W-1:0] tok_dout = {`SDMC_TOKEN_W{1'b0}};
    reg tok_empty = 1'b1;
    wire tok_pop;

    wire [7:0] out_byte;
    wire [3:0] out_kind;
    wire out_last;
    wire out_valid;
    reg out_ready = 1'b0;

    sdmc_stream_egress dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .tok_dout(tok_dout),
        .tok_empty(tok_empty),
        .tok_pop(tok_pop),
        .out_byte(out_byte),
        .out_kind(out_kind),
        .out_last(out_last),
        .out_valid(out_valid),
        .out_ready(out_ready)
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

    task offer_token;
        input last;
        input [3:0] kind;
        input [3:0] bytes;
        input [63:0] data;
        begin
            tok_dout  = pack_token(last, kind, bytes, data);
            tok_empty = 1'b0;
            tick();

            if (!tok_pop) begin
                $display("FAIL token was not popped");
                $finish;
            end

            tok_empty = 1'b1;
            tok_dout  = {`SDMC_TOKEN_W{1'b0}};
            tick();
        end
    endtask

    task expect_byte;
        input [7:0] exp_byte;
        input [3:0] exp_kind;
        input exp_last;
        begin
            if (!out_valid) begin
                $display("FAIL expected output valid");
                $finish;
            end

            if (out_byte !== exp_byte || out_kind !== exp_kind || out_last !== exp_last) begin
                $display("FAIL output byte got byte=%h kind=%h last=%b exp byte=%h kind=%h last=%b",
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
        $dumpfile("tb_sdmc_stream_egress.vcd");
        $dumpvars(0, tb_sdmc_stream_egress);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        if (out_valid || tok_pop) begin
            $display("FAIL reset");
            $finish;
        end

        offer_token(1'b1, `SDMC_TOK_OUT, 4'd3, 64'h0000_0000_0063_6261);
        expect_byte(8'h61, `SDMC_TOK_OUT, 1'b0);
        expect_byte(8'h62, `SDMC_TOK_OUT, 1'b0);
        expect_byte(8'h63, `SDMC_TOK_OUT, 1'b1);

        if (out_valid) begin
            $display("FAIL still valid after 3 bytes");
            $finish;
        end

        offer_token(1'b0, `SDMC_TOK_TAG, 4'd8, 64'h7766_5544_3322_1100);
        expect_byte(8'h00, `SDMC_TOK_TAG, 1'b0);
        expect_byte(8'h11, `SDMC_TOK_TAG, 1'b0);
        expect_byte(8'h22, `SDMC_TOK_TAG, 1'b0);
        expect_byte(8'h33, `SDMC_TOK_TAG, 1'b0);
        expect_byte(8'h44, `SDMC_TOK_TAG, 1'b0);
        expect_byte(8'h55, `SDMC_TOK_TAG, 1'b0);
        expect_byte(8'h66, `SDMC_TOK_TAG, 1'b0);
        expect_byte(8'h77, `SDMC_TOK_TAG, 1'b0);

        if (out_valid) begin
            $display("FAIL still valid after 8 bytes");
            $finish;
        end

        offer_token(1'b1, `SDMC_TOK_STATUS, 4'd1, 64'h1);
        expect_byte(8'h01, `SDMC_TOK_STATUS, 1'b1);

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (out_valid || tok_pop) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_stream_egress");
        $finish;
    end

endmodule

`default_nettype wire
