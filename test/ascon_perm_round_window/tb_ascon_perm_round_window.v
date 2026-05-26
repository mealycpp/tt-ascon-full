`timescale 1ns/1ps
`default_nettype none

module tb_ascon_perm_round_window;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg start12 = 1'b0;
    reg start8  = 1'b0;

    reg [319:0] state_in = {
        64'hdddd_eeee_ffff_0001,
        64'h9999_aaaa_bbbb_cccc,
        64'h5555_6666_7777_8888,
        64'h1111_2222_3333_4444,
        64'h0123_4567_89ab_cdef
    };

    wire [319:0] p12_out;
    wire [319:0] p8_out;
    wire p12_done;
    wire p8_done;

    ascon_permutation u_p12 (
        .clk(clk), .rst_n(rst_n),
        .start(start12), .num_rounds(4'd12),
        .state_in(state_in), .state_out(p12_out),
        .busy(), .done(p12_done)
    );

    ascon_permutation u_p8 (
        .clk(clk), .rst_n(rst_n),
        .start(start8), .num_rounds(4'd8),
        .state_in(state_in), .state_out(p8_out),
        .busy(), .done(p8_done)
    );

    wire [319:0] r12_0, r12_1, r12_2, r12_3, r12_4, r12_5;
    wire [319:0] r12_6, r12_7, r12_8, r12_9, r12_10, r12_11;

    ascon_round p12_r0  (.state_in(state_in), .round_const(8'hf0), .state_out(r12_0));
    ascon_round p12_r1  (.state_in(r12_0),    .round_const(8'he1), .state_out(r12_1));
    ascon_round p12_r2  (.state_in(r12_1),    .round_const(8'hd2), .state_out(r12_2));
    ascon_round p12_r3  (.state_in(r12_2),    .round_const(8'hc3), .state_out(r12_3));
    ascon_round p12_r4  (.state_in(r12_3),    .round_const(8'hb4), .state_out(r12_4));
    ascon_round p12_r5  (.state_in(r12_4),    .round_const(8'ha5), .state_out(r12_5));
    ascon_round p12_r6  (.state_in(r12_5),    .round_const(8'h96), .state_out(r12_6));
    ascon_round p12_r7  (.state_in(r12_6),    .round_const(8'h87), .state_out(r12_7));
    ascon_round p12_r8  (.state_in(r12_7),    .round_const(8'h78), .state_out(r12_8));
    ascon_round p12_r9  (.state_in(r12_8),    .round_const(8'h69), .state_out(r12_9));
    ascon_round p12_r10 (.state_in(r12_9),    .round_const(8'h5a), .state_out(r12_10));
    ascon_round p12_r11 (.state_in(r12_10),   .round_const(8'h4b), .state_out(r12_11));

    wire [319:0] r8_0, r8_1, r8_2, r8_3, r8_4, r8_5, r8_6, r8_7;
    wire [319:0] wrong8_0, wrong8_1, wrong8_2, wrong8_3, wrong8_4, wrong8_5, wrong8_6, wrong8_7;

    ascon_round p8_r0 (.state_in(state_in), .round_const(8'hb4), .state_out(r8_0));
    ascon_round p8_r1 (.state_in(r8_0),    .round_const(8'ha5), .state_out(r8_1));
    ascon_round p8_r2 (.state_in(r8_1),    .round_const(8'h96), .state_out(r8_2));
    ascon_round p8_r3 (.state_in(r8_2),    .round_const(8'h87), .state_out(r8_3));
    ascon_round p8_r4 (.state_in(r8_3),    .round_const(8'h78), .state_out(r8_4));
    ascon_round p8_r5 (.state_in(r8_4),    .round_const(8'h69), .state_out(r8_5));
    ascon_round p8_r6 (.state_in(r8_5),    .round_const(8'h5a), .state_out(r8_6));
    ascon_round p8_r7 (.state_in(r8_6),    .round_const(8'h4b), .state_out(r8_7));

    ascon_round w8_r0 (.state_in(state_in), .round_const(8'hf0), .state_out(wrong8_0));
    ascon_round w8_r1 (.state_in(wrong8_0), .round_const(8'he1), .state_out(wrong8_1));
    ascon_round w8_r2 (.state_in(wrong8_1), .round_const(8'hd2), .state_out(wrong8_2));
    ascon_round w8_r3 (.state_in(wrong8_2), .round_const(8'hc3), .state_out(wrong8_3));
    ascon_round w8_r4 (.state_in(wrong8_3), .round_const(8'hb4), .state_out(wrong8_4));
    ascon_round w8_r5 (.state_in(wrong8_4), .round_const(8'ha5), .state_out(wrong8_5));
    ascon_round w8_r6 (.state_in(wrong8_5), .round_const(8'h96), .state_out(wrong8_6));
    ascon_round w8_r7 (.state_in(wrong8_6), .round_const(8'h87), .state_out(wrong8_7));

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    integer guard;
    reg seen12;
    reg seen8;

    initial begin
        $dumpfile("tb_ascon_perm_round_window.vcd");
        $dumpvars(0, tb_ascon_perm_round_window);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        start12 = 1'b1;
        start8  = 1'b1;
        tick();
        start12 = 1'b0;
        start8  = 1'b0;

        guard = 0;
        seen12 = 1'b0;
        seen8  = 1'b0;

        while (!(seen12 && seen8)) begin
            if (p12_done) seen12 = 1'b1;
            if (p8_done)  seen8  = 1'b1;

            tick();
            guard = guard + 1;
            if (guard > 40) begin
                $display("FAIL timeout waiting permutation done seen12=%b seen8=%b", seen12, seen8);
                $finish;
            end
        end

        if (p12_out !== r12_11) begin
            $display("FAIL p12 round window");
            $finish;
        end

        if (p8_out !== r8_7) begin
            $display("FAIL p8 round window");
            $display("got=%h", p8_out);
            $display("exp=%h", r8_7);
            $finish;
        end

        if (p8_out === wrong8_7) begin
            $display("FAIL p8 still starts at f0");
            $finish;
        end

        $display("PASS ascon_perm_round_window");
        $finish;
    end

endmodule

`default_nettype wire
