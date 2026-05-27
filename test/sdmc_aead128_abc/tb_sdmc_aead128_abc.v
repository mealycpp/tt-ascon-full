`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_aead128_abc;

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
    reg [2:0] token_idx = 3'd0;

    wire [TOKEN_W-1:0] token0 = {1'b0, TOK_KEY,   4'd8, 64'h0706_0504_0302_0100};
    wire [TOKEN_W-1:0] token1 = {1'b1, TOK_KEY,   4'd8, 64'h0f0e_0d0c_0b0a_0908};
    wire [TOKEN_W-1:0] token2 = {1'b0, TOK_NONCE, 4'd8, 64'h1716_1514_1312_1110};
    wire [TOKEN_W-1:0] token3 = {1'b1, TOK_NONCE, 4'd8, 64'h1f1e_1d1c_1b1a_1918};
    wire [TOKEN_W-1:0] token4 = {1'b1, TOK_MSG,   4'd3, 64'h0000_0000_0063_6261};

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

    reg [151:0] enc_out;
    reg [1:0] out_idx;

    sdmc_aead128_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .is_decrypt(1'b0),
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
            enc_out <= 152'd0;
            out_idx <= 2'd0;
        end else if (out_push) begin
            case (out_idx)
                2'd0: begin
                    if (tok_kind !== TOK_OUT || tok_bytes !== 4'd3 || tok_last) begin
                        $display("FAIL bad ciphertext token kind=%h bytes=%0d last=%b", tok_kind, tok_bytes, tok_last);
                        $finish;
                    end
                    enc_out[23:0] <= tok_data[23:0];
                end
                2'd1: begin
                    if (tok_kind !== TOK_TAG || tok_bytes !== 4'd8 || tok_last) begin
                        $display("FAIL bad tag0 token kind=%h bytes=%0d last=%b", tok_kind, tok_bytes, tok_last);
                        $finish;
                    end
                    enc_out[87:24] <= tok_data;
                end
                2'd2: begin
                    if (tok_kind !== TOK_TAG || tok_bytes !== 4'd8 || !tok_last) begin
                        $display("FAIL bad tag1 token kind=%h bytes=%0d last=%b", tok_kind, tok_bytes, tok_last);
                        $finish;
                    end
                    enc_out[151:88] <= tok_data;
                end
                default: ;
            endcase
            out_idx <= out_idx + 2'd1;
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_aead128_abc.vcd");
        $dumpvars(0, tb_sdmc_aead128_abc);

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
            if (guard > 5000) begin
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

        if (out_idx !== 2'd3) begin
            $display("FAIL output tokens=%0d", out_idx);
            $finish;
        end

        if (enc_out !== 152'h175cb296c20913c20290720fa42876519f80a9) begin
            $display("FAIL enc_out mismatch");
            $display("got=%h", enc_out);
            $finish;
        end

        $display("PASS sdmc_aead128_abc");
        $finish;
    end

endmodule

`default_nettype wire
