`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_token_fifo;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg push = 1'b0;
    reg pop  = 1'b0;
    reg [`SDMC_TOKEN_W-1:0] din = {`SDMC_TOKEN_W{1'b0}};

    wire full;
    wire empty;
    wire [`SDMC_TOKEN_W-1:0] dout;
    wire [2:0] count;

    sdmc_token_fifo #(.DEPTH(4), .AW(2)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .push(push),
        .din(din),
        .full(full),
        .pop(pop),
        .dout(dout),
        .empty(empty),
        .count(count)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task push_token;
        input last;
        input [3:0] kind;
        input [3:0] bytes;
        input [63:0] data;
        begin
            if (full) begin
                $display("FAIL push while full");
                $finish;
            end

            din  = `SDMC_PACK_TOKEN(last, kind, bytes, data);
            push = 1'b1;
            tick();
            push = 1'b0;
            din  = {`SDMC_TOKEN_W{1'b0}};
            tick();
        end
    endtask

    task expect_head;
        input last;
        input [3:0] kind;
        input [3:0] bytes;
        input [63:0] data;
        reg [`SDMC_TOKEN_W-1:0] exp;
        begin
            exp = `SDMC_PACK_TOKEN(last, kind, bytes, data);

            if (empty) begin
                $display("FAIL expect head but fifo empty");
                $finish;
            end

            if (dout !== exp) begin
                $display("FAIL head mismatch");
                $display("got=%h", dout);
                $display("exp=%h", exp);
                $finish;
            end
        end
    endtask

    task pop_token;
        begin
            if (empty) begin
                $display("FAIL pop while empty");
                $finish;
            end

            pop = 1'b1;
            tick();
            pop = 1'b0;
            tick();
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_token_fifo.vcd");
        $dumpvars(0, tb_sdmc_token_fifo);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        if (!empty || full || count !== 3'd0) begin
            $display("FAIL reset state");
            $finish;
        end

        push_token(1'b0, `SDMC_TOK_KEY,   4'd8, 64'h0011_2233_4455_6677);
        push_token(1'b0, `SDMC_TOK_NONCE, 4'd8, 64'h8899_aabb_ccdd_eeff);
        push_token(1'b0, `SDMC_TOK_AD,    4'd3, 64'h0000_0000_0063_6261);
        push_token(1'b1, `SDMC_TOK_MSG,   4'd5, 64'h0000_006f_6c6c_6568);

        if (!full || empty || count !== 3'd4) begin
            $display("FAIL full/count after pushes full=%b empty=%b count=%0d", full, empty, count);
            $finish;
        end

        expect_head(1'b0, `SDMC_TOK_KEY,   4'd8, 64'h0011_2233_4455_6677);
        pop_token();

        expect_head(1'b0, `SDMC_TOK_NONCE, 4'd8, 64'h8899_aabb_ccdd_eeff);
        pop_token();

        push_token(1'b0, `SDMC_TOK_TAG,    4'd8, 64'h1111_2222_3333_4444);

        expect_head(1'b0, `SDMC_TOK_AD,    4'd3, 64'h0000_0000_0063_6261);
        pop_token();

        expect_head(1'b1, `SDMC_TOK_MSG,   4'd5, 64'h0000_006f_6c6c_6568);
        pop_token();

        expect_head(1'b0, `SDMC_TOK_TAG,   4'd8, 64'h1111_2222_3333_4444);
        pop_token();

        if (!empty || full || count !== 3'd0) begin
            $display("FAIL empty/count after pops");
            $finish;
        end

        push_token(1'b1, `SDMC_TOK_OUT, 4'd8, 64'hfeed_face_cafe_beef);

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        if (!empty || full || count !== 3'd0 || dout !== {`SDMC_TOKEN_W{1'b0}}) begin
            $display("FAIL clear");
            $finish;
        end

        $display("PASS sdmc_token_fifo");
        $finish;
    end

endmodule

`default_nettype wire
