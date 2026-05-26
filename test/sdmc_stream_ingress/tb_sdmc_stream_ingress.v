`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_stream_ingress;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] in_byte = 8'd0;
    reg [3:0] in_kind = 4'd0;
    reg       in_last = 1'b0;
    reg       in_valid = 1'b0;
    wire      in_ready;

    wire      tok_push;
    wire [`SDMC_TOKEN_W-1:0] tok_din;
    reg       tok_full = 1'b0;

    sdmc_stream_ingress dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .in_byte(in_byte),
        .in_kind(in_kind),
        .in_last(in_last),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .tok_push(tok_push),
        .tok_din(tok_din),
        .tok_full(tok_full)
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

    task drive_byte_check;
        input [7:0] b;
        input [3:0] k;
        input last;
        input exp_push;
        input [`SDMC_TOKEN_W-1:0] exp_token;
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

            if (tok_push !== exp_push) begin
                $display("FAIL tok_push got=%b exp=%b", tok_push, exp_push);
                $finish;
            end

            if (exp_push && tok_din !== exp_token) begin
                $display("FAIL token mismatch");
                $display("got=%h", tok_din);
                $display("exp=%h", exp_token);
                $finish;
            end

            in_valid = 1'b0;
            in_last  = 1'b0;
            in_byte  = 8'd0;
            in_kind  = 4'd0;
            tick();
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_stream_ingress.vcd");
        $dumpvars(0, tb_sdmc_stream_ingress);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        if (!in_ready || tok_push) begin
            $display("FAIL reset");
            $finish;
        end

        drive_byte_check(8'h61, `SDMC_TOK_MSG, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h62, `SDMC_TOK_MSG, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h63, `SDMC_TOK_MSG, 1'b1, 1'b1,
                         pack_token(1'b1, `SDMC_TOK_MSG, 4'd3, 64'h0000_0000_0063_6261));

        drive_byte_check(8'h00, `SDMC_TOK_KEY, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h11, `SDMC_TOK_KEY, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h22, `SDMC_TOK_KEY, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h33, `SDMC_TOK_KEY, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h44, `SDMC_TOK_KEY, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h55, `SDMC_TOK_KEY, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h66, `SDMC_TOK_KEY, 1'b0, 1'b0, {`SDMC_TOKEN_W{1'b0}});
        drive_byte_check(8'h77, `SDMC_TOK_KEY, 1'b0, 1'b1,
                         pack_token(1'b0, `SDMC_TOK_KEY, 4'd8, 64'h7766_5544_3322_1100));

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (!in_ready || tok_push) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_stream_ingress");
        $finish;
    end

endmodule

`default_nettype wire
