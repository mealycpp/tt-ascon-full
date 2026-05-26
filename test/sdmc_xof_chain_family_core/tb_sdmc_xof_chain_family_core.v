`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_xof_chain_family_core;

    localparam TOKEN_W = 73;
    localparam TOK_MSG = 4'd1;
    localparam TOK_OUT = 4'd7;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg start = 1'b0;

    reg token_available = 1'b1;
    wire [TOKEN_W-1:0] in_token;
    assign in_token = {1'b1, TOK_MSG, 4'd3, 64'h0000_0000_0063_6261};
    wire in_empty = !token_available;
    wire in_pop;

    wire [TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;

    reg [255:0] digest;
    reg [1:0] word_idx;

    sdmc_xof_chain_family_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .use_cxof(1'b0),
        .chain_count(16'd2),
        .msg_len(16'd3),
        .cs_len(16'd0),
        .out_len(16'd32),
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

    wire tok_last = out_token[72];
    wire [3:0] tok_kind = out_token[71:68];
    wire [3:0] tok_bytes = out_token[67:64];
    wire [63:0] tok_data = out_token[63:0];

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            digest <= 256'd0;
            word_idx <= 2'd0;
            token_available <= 1'b1;
        end else begin
            if (in_pop) token_available <= 1'b0;

            if (out_push) begin
                if (tok_kind !== TOK_OUT || tok_bytes !== 4'd8) begin
                    $display("FAIL bad output token kind=%h bytes=%0d", tok_kind, tok_bytes);
                    $finish;
                end

                case (word_idx)
                    2'd0: digest[63:0]    <= tok_data;
                    2'd1: digest[127:64]  <= tok_data;
                    2'd2: digest[191:128] <= tok_data;
                    2'd3: digest[255:192] <= tok_data;
                    default: ;
                endcase

                if (word_idx == 2'd3 && !tok_last) begin
                    $display("FAIL final token missing last");
                    $finish;
                end

                word_idx <= word_idx + 2'd1;
            end
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_xof_chain_family_core.vcd");
        $dumpvars(0, tb_sdmc_xof_chain_family_core);

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

        if (token_available) begin
            $display("FAIL external input token was not consumed");
            $finish;
        end

        if (digest !== 256'h6db2953356879e90358cd92ec9e04b81e113b4aba157ef4cd02b84f7c1214566) begin
            $display("FAIL digest mismatch");
            $display("got=%h", digest);
            $display("exp=%h", 256'h6db2953356879e90358cd92ec9e04b81e113b4aba157ef4cd02b84f7c1214566);
            $finish;
        end

        $display("PASS sdmc_xof_chain_family_core");
        $finish;
    end

endmodule

`default_nettype wire
