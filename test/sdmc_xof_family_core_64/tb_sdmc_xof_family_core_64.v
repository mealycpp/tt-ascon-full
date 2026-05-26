`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_xof_family_core_64;

    localparam TOKEN_W    = 73;
    localparam TOK_MSG    = 4'd1;
    localparam TOK_OUT    = 4'd7;

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

    reg [511:0] digest;
    reg [2:0] word_idx;

    sdmc_xof_family_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .use_cxof(1'b0),
        .chain_count(16'd1),
        .cs_len(16'd0),
        .out_len(16'd64),
        .msg_len(16'd3),
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
            digest <= 512'd0;
            word_idx <= 3'd0;
            token_available <= 1'b1;
        end else begin
            if (in_pop) begin
                token_available <= 1'b0;
            end

            if (out_push) begin
                if (tok_kind !== TOK_OUT || tok_bytes !== 4'd8) begin
                    $display("FAIL bad output token kind=%h bytes=%0d", tok_kind, tok_bytes);
                    $finish;
                end

                case (word_idx)
                    3'd0: digest[63:0]    <= tok_data;
                    3'd1: digest[127:64]  <= tok_data;
                    3'd2: digest[191:128] <= tok_data;
                    3'd3: digest[255:192] <= tok_data;
                    3'd4: digest[319:256] <= tok_data;
                    3'd5: digest[383:320] <= tok_data;
                    3'd6: digest[447:384] <= tok_data;
                    3'd7: digest[511:448] <= tok_data;
                    default: ;
                endcase

                if (word_idx == 3'd7 && !tok_last) begin
                    $display("FAIL final token missing last");
                    $finish;
                end

                word_idx <= word_idx + 3'd1;
            end
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_xof_family_core_64.vcd");
        $dumpvars(0, tb_sdmc_xof_family_core_64);

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

        if (token_available) begin
            $display("FAIL input token was not consumed");
            $finish;
        end

        if (digest !== 512'h625474a7c5c667d4f5c92bc0ddcf3aba1127144b65abb4f5b2d7d7121aaab7230b2f0bb2a67a3cce193dc16efe09c00857927f1868aa5b503242723d619871b8) begin
            $display("FAIL digest mismatch");
            $display("got=%h", digest);
            $finish;
        end

        $display("PASS sdmc_xof_family_core_64");
        $finish;
    end

endmodule

`default_nettype wire
