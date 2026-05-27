`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_aead128_dec_abc;

    localparam TOKEN_W   = `SDMC_TOKEN_W;
    localparam TOK_KEY   = `SDMC_TOK_KEY;
    localparam TOK_NONCE = `SDMC_TOK_NONCE;
    localparam TOK_MSG   = `SDMC_TOK_MSG;
    localparam TOK_OUT   = `SDMC_TOK_OUT;
    localparam TOK_TAG   = `SDMC_TOK_TAG;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg start = 1'b0;
    reg bad_tag = 1'b0;
    reg [2:0] token_idx = 3'd0;

    wire [TOKEN_W-1:0] token0 = {1'b0, TOK_KEY,   4'd8, 64'h0706_0504_0302_0100};
    wire [TOKEN_W-1:0] token1 = {1'b1, TOK_KEY,   4'd8, 64'h0f0e_0d0c_0b0a_0908};
    wire [TOKEN_W-1:0] token2 = {1'b0, TOK_NONCE, 4'd8, 64'h1716_1514_1312_1110};
    wire [TOKEN_W-1:0] token3 = {1'b1, TOK_NONCE, 4'd8, 64'h1f1e_1d1c_1b1a_1918};
    wire [TOKEN_W-1:0] token4 = {1'b1, TOK_MSG,   4'd3, 64'h0000_0000_009f_80a9};
    wire [TOKEN_W-1:0] token5 = {1'b0, TOK_TAG,   4'd8, 64'h0290_720f_a428_7651};
    wire [TOKEN_W-1:0] token6_good = {1'b1, TOK_TAG, 4'd8, 64'h175c_b296_c209_13c2};
    wire [TOKEN_W-1:0] token6_bad  = {1'b1, TOK_TAG, 4'd8, 64'h005c_b296_c209_13c2};

    wire [TOKEN_W-1:0] in_token =
        (token_idx == 3'd0) ? token0 :
        (token_idx == 3'd1) ? token1 :
        (token_idx == 3'd2) ? token2 :
        (token_idx == 3'd3) ? token3 :
        (token_idx == 3'd4) ? token4 :
        (token_idx == 3'd5) ? token5 :
                              (bad_tag ? token6_bad : token6_good);

    wire in_empty = (token_idx >= 3'd7);
    wire in_pop;

    wire [TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;
    wire auth_ok;

    reg [63:0] pt_word;
    reg [1:0] out_idx;

    sdmc_aead128_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .is_decrypt(1'b1),
        .ad_len(16'd0),
        .data_len(16'd3),
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
        if (!rst_n || clear) begin
            token_idx <= 3'd0;
        end else if (in_pop) begin
            token_idx <= token_idx + 3'd1;
        end
    end

    wire tok_last = out_token[72];
    wire [3:0] tok_kind = out_token[71:68];
    wire [3:0] tok_bytes = out_token[67:64];
    wire [63:0] tok_data = out_token[63:0];

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            pt_word <= 64'd0;
            out_idx <= 2'd0;
        end else if (out_push) begin
            if (tok_kind !== TOK_OUT || tok_bytes !== 4'd3 || tok_last) begin
                $display("FAIL bad plaintext token kind=%h bytes=%0d last=%b", tok_kind, tok_bytes, tok_last);
                $finish;
            end
            pt_word <= tok_data;
            out_idx <= out_idx + 2'd1;
        end
    end

    task run_case;
        input t_bad_tag;
        input exp_auth;
        integer guard;
        begin
            clear = 1'b1;
            tick();
            clear = 1'b0;
            tick();

            bad_tag = t_bad_tag;
            pt_word = 64'd0;
            out_idx = 2'd0;
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

            if (error) begin
                $display("FAIL error asserted");
                $finish;
            end

            if (token_idx !== 3'd7) begin
                $display("FAIL tokens consumed=%0d", token_idx);
                $finish;
            end

            if (out_idx !== 2'd1) begin
                $display("FAIL plaintext outputs=%0d", out_idx);
                $finish;
            end

            if (pt_word[23:0] !== 24'h636261) begin
                $display("FAIL plaintext mismatch got=%h", pt_word);
                $finish;
            end

            if (auth_ok !== exp_auth) begin
                $display("FAIL auth mismatch got=%b exp=%b", auth_ok, exp_auth);
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_aead128_dec_abc.vcd");
        $dumpvars(0, tb_sdmc_aead128_dec_abc);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        run_case(1'b0, 1'b1);
        run_case(1'b1, 1'b0);

        $display("PASS sdmc_aead128_dec_abc");
        $finish;
    end

endmodule

`default_nettype wire
