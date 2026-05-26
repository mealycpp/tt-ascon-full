`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_fifo;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    always #5 clk = ~clk;

    reg         push;
    reg [63:0]  din;
    wire        full;

    reg         pop;
    wire [63:0] dout;
    wire        empty;
    wire [2:0]  count;

    sdmc_fifo #(
        .WIDTH(64),
        .DEPTH(4),
        .AW(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .push(push),
        .din(din),
        .full(full),
        .pop(pop),
        .dout(dout),
        .empty(empty),
        .count(count)
    );

    task cycle;
        begin
            @(negedge clk);
        end
    endtask

    task do_push;
        input [63:0] word;
        begin
            push = 1'b1;
            din  = word;
            pop  = 1'b0;
            cycle();
            push = 1'b0;
            din  = 64'd0;
        end
    endtask

    task do_pop_check;
        input [63:0] exp;
        begin
            if (empty) begin
                $display("FAIL pop while empty expected=%h", exp);
                $finish;
            end
            if (dout !== exp) begin
                $display("FAIL dout before pop got=%h expected=%h", dout, exp);
                $finish;
            end
            pop  = 1'b1;
            push = 1'b0;
            cycle();
            pop = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_fifo.vcd");
        $dumpvars(0, tb_sdmc_fifo);

        push = 1'b0;
        pop  = 1'b0;
        din  = 64'd0;

        repeat (5) cycle();
        rst_n = 1'b1;
        repeat (2) cycle();

        if (!empty || full || count != 3'd0) begin
            $display("FAIL reset state empty=%b full=%b count=%0d", empty, full, count);
            $finish;
        end

        do_push(64'h1111);
        do_push(64'h2222);
        do_push(64'h3333);
        do_push(64'h4444);

        if (!full || empty || count != 3'd4) begin
            $display("FAIL full state empty=%b full=%b count=%0d", empty, full, count);
            $finish;
        end

        do_pop_check(64'h1111);
        do_pop_check(64'h2222);

        if (count != 3'd2) begin
            $display("FAIL count after two pops count=%0d", count);
            $finish;
        end

        // Simultaneous push/pop. Output should still show old head before pop.
        if (dout !== 64'h3333) begin
            $display("FAIL before simultaneous pop got=%h", dout);
            $finish;
        end

        push = 1'b1;
        pop  = 1'b1;
        din  = 64'h5555;
        cycle();
        push = 1'b0;
        pop  = 1'b0;
        din  = 64'd0;

        if (count != 3'd2) begin
            $display("FAIL count after simultaneous push/pop count=%0d", count);
            $finish;
        end

        do_pop_check(64'h4444);
        do_pop_check(64'h5555);

        if (!empty || count != 3'd0) begin
            $display("FAIL final empty state empty=%b count=%0d", empty, count);
            $finish;
        end

        do_push(64'haaaa);
        clear = 1'b1;
        cycle();
        clear = 1'b0;

        if (!empty || count != 3'd0) begin
            $display("FAIL clear state empty=%b count=%0d", empty, count);
            $finish;
        end

        $display("PASS sdmc_fifo");
        $finish;
    end

endmodule

`default_nettype wire
