`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_aead128_pt4;

    localparam TOKEN_W = `SDMC_TOKEN_W;
    localparam OUT_BYTES = 20;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg start = 1'b0;
    reg [2:0] token_idx = 3'd0;

    wire [TOKEN_W-1:0] token0 = {1'b0, `SDMC_TOK_KEY,   4'd8, 64'h0706_0504_0302_0100};
    wire [TOKEN_W-1:0] token1 = {1'b1, `SDMC_TOK_KEY,   4'd8, 64'h0f0e_0d0c_0b0a_0908};
    wire [TOKEN_W-1:0] token2 = {1'b0, `SDMC_TOK_NONCE, 4'd8, 64'h1716_1514_1312_1110};
    wire [TOKEN_W-1:0] token3 = {1'b1, `SDMC_TOK_NONCE, 4'd8, 64'h1f1e_1d1c_1b1a_1918};
    wire [TOKEN_W-1:0] token4 = {1'b1, `SDMC_TOK_MSG,   4'd4, 64'h0000000023222120};

    wire [TOKEN_W-1:0] in_token =
        (token_idx == 3'd0) ? token0 :
        (token_idx == 3'd1) ? token1 :
        (token_idx == 3'd2) ? token2 :
        (token_idx == 3'd3) ? token3 : token4;

    wire in_empty = (token_idx >= 3'd5);
    wire in_pop;

    wire [TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;
    wire auth_ok;

    reg [159:0] enc_out;
    reg [5:0] out_idx;

    sdmc_aead128_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .is_decrypt(1'b0),
        .ad_len(16'd0),
        .data_len(16'd4),
        .in_token(in_token),
        .in_empty(in_empty),
        .in_pop(in_pop),
        .out_token(out_token),
        .out_push(out_push),
        .out_full(out_full),
        .busy(busy),
        .done(done),
        .error(error),
        .auth_ok(auth_ok)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    always @(negedge clk) begin
        if (!rst_n || clear) token_idx <= 3'd0;
        else if (in_pop) token_idx <= token_idx + 3'd1;
    end

    wire tok_last = out_token[72];
    wire [3:0] tok_kind = out_token[71:68];
    wire [3:0] tok_bytes = out_token[67:64];
    wire [63:0] tok_data = out_token[63:0];

    integer j;

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            enc_out <= 160'd0;
            out_idx <= 6'd0;
        end else if (out_push) begin
            if (out_idx == 6'd0) begin
                if (tok_kind !== `SDMC_TOK_OUT || tok_bytes !== 4'd4) begin
                    $display("FAIL bad CT token kind=%h bytes=%0d", tok_kind, tok_bytes);
                    $finish;
                end
                for (j = 0; j < 4; j = j + 1) begin
                    enc_out[j*8 +: 8] <= tok_data[j*8 +: 8];
                end
            end else if (out_idx == 6'd1) begin
                if (tok_kind !== `SDMC_TOK_TAG || tok_bytes !== 4'd8) begin
                    $display("FAIL bad TAG0 token kind=%h bytes=%0d", tok_kind, tok_bytes);
                    $finish;
                end
                enc_out[32 +: 64] <= tok_data;
            end else if (out_idx == 6'd2) begin
                if (tok_kind !== `SDMC_TOK_TAG || tok_bytes !== 4'd8 || !tok_last) begin
                    $display("FAIL bad TAG1 token kind=%h bytes=%0d last=%b", tok_kind, tok_bytes, tok_last);
                    $finish;
                end
                enc_out[96 +: 64] <= tok_data;
            end
            out_idx <= out_idx + 6'd1;
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_aead128_pt4.vcd");
        $dumpvars(0, tb_sdmc_aead128_pt4);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        start = 1'b1;
        tick();
        start = 1'b0;

        guard = 0;
        while (!done) begin
            tick();
            guard = guard + 1;
            if (guard > 6000) begin
                $display("FAIL timeout");
                $finish;
            end
        end

        tick();

        if (error) begin
            $display("FAIL error asserted");
            $finish;
        end

        if (token_idx !== 3'd5) begin
            $display("FAIL tokens consumed=%0d", token_idx);
            $finish;
        end

        if (out_idx !== 6'd3) begin
            $display("FAIL out tokens=%0d", out_idx);
            $finish;
        end

        if (enc_out !== 160'h04cd9607abd966de4cb6099b6aa9c003eedec3e8) begin
            $display("FAIL enc_out mismatch got=%h exp=%h", enc_out, 160'h04cd9607abd966de4cb6099b6aa9c003eedec3e8);
            $finish;
        end

        $display("PASS sdmc_aead128_pt4");
        $finish;
    end

endmodule

`default_nettype wire
