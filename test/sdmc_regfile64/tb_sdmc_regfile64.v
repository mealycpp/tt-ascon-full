`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_regfile64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    reg        wr_en = 1'b0;
    reg [3:0]  wr_addr = 4'd0;
    reg [63:0] wr_data = 64'd0;

    reg        rd_en = 1'b0;
    reg [3:0]  rd_addr_a = 4'd0;
    reg [3:0]  rd_addr_b = 4'd0;
    wire [63:0] rd_data_a;
    wire [63:0] rd_data_b;
    wire        rd_valid;

    wire [63:0] r0;
    wire [63:0] r1;
    wire [63:0] r2;
    wire [63:0] r3;
    wire [63:0] r4;

    always #5 clk = ~clk;

    sdmc_regfile64 dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_addr_a(rd_addr_a),
        .rd_addr_b(rd_addr_b),
        .rd_data_a(rd_data_a),
        .rd_data_b(rd_data_b),
        .rd_valid(rd_valid),
        .r0(r0),
        .r1(r1),
        .r2(r2),
        .r3(r3),
        .r4(r4)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task write_reg;
        input [3:0] addr;
        input [63:0] data;
        begin
            wr_addr = addr;
            wr_data = data;
            wr_en   = 1'b1;
            tick();
            wr_en   = 1'b0;
            wr_addr = 4'd0;
            wr_data = 64'd0;
        end
    endtask

    task read_pair;
        input [3:0] a_addr;
        input [3:0] b_addr;
        input [63:0] exp_a;
        input [63:0] exp_b;
        begin
            rd_addr_a = a_addr;
            rd_addr_b = b_addr;
            rd_en     = 1'b1;
            tick();
            rd_en     = 1'b0;

            if (!rd_valid) begin
                $display("FAIL rd_valid missing");
                $finish;
            end

            if (rd_data_a !== exp_a || rd_data_b !== exp_b) begin
                $display("FAIL read a=%h exp_a=%h b=%h exp_b=%h",
                         rd_data_a, exp_a, rd_data_b, exp_b);
                $finish;
            end

            tick();

            if (rd_valid) begin
                $display("FAIL rd_valid should pulse");
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_regfile64.vcd");
        $dumpvars(0, tb_sdmc_regfile64);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        write_reg(4'd0, 64'h0000_0000_0000_0001);
        write_reg(4'd1, 64'h1111_2222_3333_4444);
        write_reg(4'd2, 64'haaaa_bbbb_cccc_dddd);
        write_reg(4'd15, 64'hffff_eeee_dddd_cccc);

        read_pair(4'd0, 4'd1, 64'h0000_0000_0000_0001, 64'h1111_2222_3333_4444);
        read_pair(4'd2, 4'd15, 64'haaaa_bbbb_cccc_dddd, 64'hffff_eeee_dddd_cccc);

        if (r0 !== 64'h0000_0000_0000_0001 ||
            r1 !== 64'h1111_2222_3333_4444 ||
            r2 !== 64'haaaa_bbbb_cccc_dddd) begin
            $display("FAIL direct state taps");
            $finish;
        end

        // Same-cycle write/read forwarding.
        wr_en     = 1'b1;
        wr_addr   = 4'd3;
        wr_data   = 64'h1234_5678_9abc_def0;
        rd_en     = 1'b1;
        rd_addr_a = 4'd3;
        rd_addr_b = 4'd2;
        tick();
        wr_en = 1'b0;
        rd_en = 1'b0;

        if (!rd_valid ||
            rd_data_a !== 64'h1234_5678_9abc_def0 ||
            rd_data_b !== 64'haaaa_bbbb_cccc_dddd) begin
            $display("FAIL forwarding read");
            $finish;
        end

        tick();

        clear = 1'b1;
        tick();
        clear = 1'b0;

        read_pair(4'd0, 4'd15, 64'd0, 64'd0);

        $display("PASS sdmc_regfile64");
        $finish;
    end

endmodule

`default_nettype wire
