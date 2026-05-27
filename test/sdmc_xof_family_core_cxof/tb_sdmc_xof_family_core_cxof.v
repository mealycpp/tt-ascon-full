`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_xof_family_core_cxof;

    localparam TOKEN_W = 73;
    localparam TOK_MSG = 4'd1;
    localparam TOK_CS  = 4'd2;
    localparam TOK_OUT = 4'd7;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg start = 1'b0;
    reg [15:0] msg_len = 16'd0;
    reg [15:0] cs_len = 16'd0;

    reg [1:0] token_idx = 2'd0;
    reg [1:0] token_total = 2'd0;
    reg [TOKEN_W-1:0] token0 = {TOKEN_W{1'b0}};
    reg [TOKEN_W-1:0] token1 = {TOKEN_W{1'b0}};

    wire [TOKEN_W-1:0] in_token = (token_idx == 2'd0) ? token0 : token1;
    wire in_empty = (token_idx >= token_total);
    wire in_pop;

    wire [TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;

    reg [255:0] digest;
    reg [1:0] word_idx;

    sdmc_xof_family_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .use_hash    (1'b0),
        .use_cxof(1'b1),
        .chain_count(16'd1),
        .cs_len(cs_len),
        .out_len(16'd32),
        .msg_len(msg_len),
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
            token_idx <= 2'd0;
        end else begin
            if (in_pop) token_idx <= token_idx + 2'd1;

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

    task run_case;
        input [15:0] t_cs_len;
        input [15:0] t_msg_len;
        input [1:0]  t_total;
        input [TOKEN_W-1:0] t0;
        input [TOKEN_W-1:0] t1;
        input [255:0] expected;
        integer guard;
        begin
            clear = 1'b1;
            tick();
            clear = 1'b0;
            tick();

            digest = 256'd0;
            word_idx = 2'd0;
            token_idx = 2'd0;
            cs_len = t_cs_len;
            msg_len = t_msg_len;
            token_total = t_total;
            token0 = t0;
            token1 = t1;
            repeat (2) tick();

            start = 1'b1;
            tick();
            start = 1'b0;

            guard = 0;
            while (!done) begin
                tick();
                guard = guard + 1;
                if (guard > 2500) begin
                    $display("FAIL timeout");
                    $finish;
                end
            end

            tick();

            if (error) begin
                $display("FAIL error asserted");
                $finish;
            end

            if (token_idx !== token_total) begin
                $display("FAIL token count consumed=%0d total=%0d", token_idx, token_total);
                $finish;
            end

            if (digest !== expected) begin
                $display("FAIL digest mismatch");
                $display("got=%h", digest);
                $display("exp=%h", expected);
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_xof_family_core_cxof.vcd");
        $dumpvars(0, tb_sdmc_xof_family_core_cxof);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        // CXOF(cs="", msg="abc")
        run_case(
            16'd0,
            16'd3,
            2'd1,
            {1'b1, TOK_MSG, 4'd3, 64'h0000_0000_0063_6261},
            {TOKEN_W{1'b0}},
            256'h9248c920d7aac5e573fe426e400fcdc22b549db1ba716238d79b58f680d71357
        );

        // CXOF(cs="a", msg="abc")
        run_case(
            16'd1,
            16'd3,
            2'd2,
            {1'b1, TOK_CS,  4'd1, 64'h0000_0000_0000_0061},
            {1'b1, TOK_MSG, 4'd3, 64'h0000_0000_0063_6261},
            256'h028f5c21e71c80648b30aded599f114bf9c6d4fb52e2ebcbd88af925ba991a43
        );

        // CXOF(cs="hello", msg="world")
        run_case(
            16'd5,
            16'd5,
            2'd2,
            {1'b1, TOK_CS,  4'd5, 64'h0000_006f_6c6c_6568},
            {1'b1, TOK_MSG, 4'd5, 64'h0000_0064_6c72_6f77},
            256'h7cb07999e12ee90c2cdde3fa84a9b25b9624beda03c6c7bacc4f40406c2f656d
        );

        $display("PASS sdmc_xof_family_core_cxof");
        $finish;
    end

endmodule

`default_nettype wire
