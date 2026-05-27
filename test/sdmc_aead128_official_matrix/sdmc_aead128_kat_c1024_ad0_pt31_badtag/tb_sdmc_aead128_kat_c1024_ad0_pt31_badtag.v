`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_aead128_kat_c1024_ad0_pt31_badtag;

    localparam integer TOKEN_COUNT = 10;
    localparam integer OUT_BYTES = 31;
    localparam integer OUT_BITS = 248;
    localparam integer PT_BYTES = 31;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    reg start = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] token_idx = 8'd0;
    reg [`SDMC_TOKEN_W-1:0] token_mem [0:TOKEN_COUNT-1];

    wire in_empty = (token_idx >= TOKEN_COUNT);
    wire [`SDMC_TOKEN_W-1:0] in_token = in_empty ? {`SDMC_TOKEN_W{1'b0}} : token_mem[token_idx];
    wire in_pop;

    wire [`SDMC_TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;
    wire auth_ok;

    reg [OUT_BITS-1:0] got;
    reg [15:0] out_bytes_seen;

    sdmc_aead128_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .is_decrypt(1'b1),
        .ad_len(16'd0),
        .data_len(16'd31),
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

    integer j;
    wire [3:0] tok_kind = out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
    wire [3:0] tok_bytes = out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
    wire [63:0] tok_data = out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

    initial begin
        token_mem[0] = {1'b0, `SDMC_TOK_KEY, 4'd8, 64'h0706050403020100};
        token_mem[1] = {1'b1, `SDMC_TOK_KEY, 4'd8, 64'h0f0e0d0c0b0a0908};
        token_mem[2] = {1'b0, `SDMC_TOK_NONCE, 4'd8, 64'h1716151413121110};
        token_mem[3] = {1'b1, `SDMC_TOK_NONCE, 4'd8, 64'h1f1e1d1c1b1a1918};
        token_mem[4] = {1'b0, `SDMC_TOK_MSG, 4'd8, 64'heac56c24eedec3e8};
        token_mem[5] = {1'b0, `SDMC_TOK_MSG, 4'd8, 64'hbba297383172e8e3};
        token_mem[6] = {1'b0, `SDMC_TOK_MSG, 4'd8, 64'h0703e8153eaa8960};
        token_mem[7] = {1'b1, `SDMC_TOK_MSG, 4'd7, 64'h005466001f2d0f97};
        token_mem[8] = {1'b0, `SDMC_TOK_TAG, 4'd8, 64'h39226a999c5b9f60};
        token_mem[9] = {1'b1, `SDMC_TOK_TAG, 4'd8, 64'heac253dd02b7f562};
    end

    always @(negedge clk) begin
        if (!rst_n || clear) begin
            token_idx <= 8'd0;
        end else if (in_pop) begin
            token_idx <= token_idx + 8'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            got <= {OUT_BITS{1'b0}};
            out_bytes_seen <= 16'd0;
        end else if (out_push) begin
            if ((out_bytes_seen + tok_bytes) > OUT_BYTES) begin
                $display("FAIL too many output bytes seen=%0d tok_bytes=%0d out_bytes=%0d", out_bytes_seen, tok_bytes, OUT_BYTES);
                $finish;
            end

            if (out_bytes_seen < PT_BYTES) begin
                if (tok_kind !== `SDMC_TOK_OUT) begin
                    $display("FAIL expected OUT token kind=%h seen=%0d", tok_kind, out_bytes_seen);
                    $finish;
                end
            end else begin
                if (0 && tok_kind !== `SDMC_TOK_TAG) begin
                    $display("FAIL expected TAG token kind=%h seen=%0d", tok_kind, out_bytes_seen);
                    $finish;
                end
            end

            for (j = 0; j < 8; j = j + 1) begin
                if (j < tok_bytes) begin
                    got[(out_bytes_seen + j)*8 +: 8] <= tok_data[j*8 +: 8];
                end
            end

            out_bytes_seen <= out_bytes_seen + tok_bytes;
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_aead128_kat_c1024_ad0_pt31_badtag.vcd");
        $dumpvars(0, tb_sdmc_aead128_kat_c1024_ad0_pt31_badtag);

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
            if (guard > 50000) begin
                $display("FAIL timeout Count=1024 mode=dec_bad AD=0 PT=31");
                $finish;
            end
        end

        repeat (3) tick();

        if (error) begin
            $display("FAIL error asserted Count=1024 mode=dec_bad AD=0 PT=31");
            $finish;
        end

        if (token_idx !== TOKEN_COUNT) begin
            $display("FAIL tokens consumed=%0d expected=%0d Count=1024 mode=dec_bad", token_idx, TOKEN_COUNT);
            $finish;
        end

        if (out_bytes_seen !== OUT_BYTES) begin
            $display("FAIL output bytes=%0d expected=%0d Count=1024 mode=dec_bad", out_bytes_seen, OUT_BYTES);
            $finish;
        end

        if (got !== 248'h3e3d3c3b3a393837363534333231302f2e2d2c2b2a29282726252423222120) begin
            $display("FAIL output mismatch Count=1024 mode=dec_bad AD=0 PT=31");
            $display("got=%h", got);
            $display("exp=%h", 248'h3e3d3c3b3a393837363534333231302f2e2d2c2b2a29282726252423222120);
            $finish;
        end

        if (auth_ok !== 1'b0) begin
            $display("FAIL auth mismatch got=%b exp=0 Count=1024 mode=dec_bad", auth_ok);
            $finish;
        end

        $display("PASS sdmc_aead128_kat_c1024_ad0_pt31_badtag");
        $finish;
    end

endmodule

`default_nettype wire
