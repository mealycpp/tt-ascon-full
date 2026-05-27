`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_aead128_ad5;

    localparam TOKEN_W = `SDMC_TOKEN_W;

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
    wire [TOKEN_W-1:0] token4 = {1'b1, `SDMC_TOK_AD,    4'd5, 64'h0000003433323130};

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

    reg [127:0] tag;
    reg [1:0] tag_idx;

    sdmc_aead128_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .is_decrypt(1'b0),
        .ad_len(16'd5),
        .data_len(16'd0),
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

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            tag <= 128'd0;
            tag_idx <= 2'd0;
        end else if (out_push) begin
            if (tok_kind !== `SDMC_TOK_TAG || tok_bytes !== 4'd8) begin
                $display("FAIL bad tag token kind=%h bytes=%0d", tok_kind, tok_bytes);
                $finish;
            end
            if (tag_idx == 2'd0) begin
                tag[63:0] <= tok_data;
                if (tok_last) begin
                    $display("FAIL first tag token marked last");
                    $finish;
                end
            end else begin
                tag[127:64] <= tok_data;
                if (!tok_last) begin
                    $display("FAIL final tag token missing last");
                    $finish;
                end
            end
            tag_idx <= tag_idx + 2'd1;
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_aead128_ad5.vcd");
        $dumpvars(0, tb_sdmc_aead128_ad5);

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

        if (tag !== 128'h7e1522865b389ba9ee3aed8f7f16ccf7) begin
            $display("FAIL tag mismatch got=%h exp=%h", tag, 128'h7e1522865b389ba9ee3aed8f7f16ccf7);
            $finish;
        end

        $display("PASS sdmc_aead128_ad5");
        $finish;
    end

endmodule

`default_nettype wire
