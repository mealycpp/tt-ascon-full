`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_cxof_chain_z0_empty_c16_out64;

    localparam integer TOKEN_COUNT = 0;
    localparam integer OUT_BYTES = 64;
    localparam integer OUT_BITS = 512;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    reg start = 1'b0;
    always #5 clk = ~clk;

    reg [15:0] token_idx = 16'd0;
    reg [`SDMC_TOKEN_W-1:0] token_mem [0:0];

    wire in_empty = (token_idx >= TOKEN_COUNT);
    wire [`SDMC_TOKEN_W-1:0] in_token = in_empty ? {`SDMC_TOKEN_W{1'b0}} : token_mem[token_idx];
    wire in_pop;

    wire [`SDMC_TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;

    reg [OUT_BITS-1:0] got;
    reg [15:0] out_bytes_seen;

    sdmc_xof_chain_family_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .use_cxof(1'b1),
        .chain_count(16'd16),
        .msg_len(16'd0),
        .cs_len(16'd0),
        .out_len(16'd64),
        .in_token(in_token),
        .in_empty(in_empty),
        .in_pop(in_pop),
        .out_token(out_token),
        .out_push(out_push),
        .out_full(out_full),
        .busy(busy),
        .done(done),
        .error(error)
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
    wire tok_last = out_token[`SDMC_TOKEN_LAST_BIT];

    initial begin

    end

    always @(negedge clk) begin
        if (!rst_n || clear) begin
            token_idx <= 16'd0;
        end else if (in_pop) begin
            token_idx <= token_idx + 16'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            got <= {OUT_BITS{1'b0}};
            out_bytes_seen <= 16'd0;
        end else if (out_push) begin
            if (tok_kind !== `SDMC_TOK_OUT) begin
                $display("FAIL bad output kind=%h", tok_kind);
                $finish;
            end

            if ((out_bytes_seen + tok_bytes) > OUT_BYTES) begin
                $display("FAIL too many output bytes seen=%0d tok_bytes=%0d", out_bytes_seen, tok_bytes);
                $finish;
            end

            for (j = 0; j < 8; j = j + 1) begin
                if (j < tok_bytes) begin
                    got[(out_bytes_seen + j)*8 +: 8] <= tok_data[j*8 +: 8];
                end
            end

            out_bytes_seen <= out_bytes_seen + tok_bytes;

            if ((out_bytes_seen + tok_bytes) == OUT_BYTES && !tok_last) begin
                $display("FAIL final output token missing last");
                $finish;
            end
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_cxof_chain_z0_empty_c16_out64.vcd");
        $dumpvars(0, tb_sdmc_cxof_chain_z0_empty_c16_out64);

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
            if (guard > 200000) begin
                $display("FAIL timeout sdmc_cxof_chain_z0_empty_c16_out64");
                $finish;
            end
        end

        repeat (3) tick();

        if (error) begin
            $display("FAIL error asserted sdmc_cxof_chain_z0_empty_c16_out64");
            $finish;
        end

        if (token_idx !== TOKEN_COUNT) begin
            $display("FAIL token consumed=%0d expected=%0d", token_idx, TOKEN_COUNT);
            $finish;
        end

        if (out_bytes_seen !== OUT_BYTES) begin
            $display("FAIL out_bytes_seen=%0d expected=%0d", out_bytes_seen, OUT_BYTES);
            $finish;
        end

        if (got !== 512'hd6289175b6784bedd435ce251c9aa4abad69222b9fd66b497040b18890b950c31674b8053878b026e36be0aaf8fbe837dab6fa657acff0a083c6d84929c84e33) begin
            $display("FAIL digest mismatch sdmc_cxof_chain_z0_empty_c16_out64");
            $display("got=%h", got);
            $display("exp=%h", 512'hd6289175b6784bedd435ce251c9aa4abad69222b9fd66b497040b18890b950c31674b8053878b026e36be0aaf8fbe837dab6fa657acff0a083c6d84929c84e33);
            $finish;
        end

        $display("PASS sdmc_cxof_chain_z0_empty_c16_out64");
        $finish;
    end

endmodule

`default_nettype wire
