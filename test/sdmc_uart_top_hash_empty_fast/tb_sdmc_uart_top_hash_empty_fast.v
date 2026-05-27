`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_uart_top_hash_empty_fast;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ena = 1'b1;

    reg [7:0] ui_in = 8'h07;
    reg [7:0] uio_in = 8'd0;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_mealycpp_ascon_sdmc_uart dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    always #5 clk = ~clk;

    reg [7:0] expected [0:31];
    reg [7:0] got [0:31];

    initial begin
        expected[0]  = 8'h0B; expected[1]  = 8'h3B; expected[2]  = 8'hE5; expected[3]  = 8'h85;
        expected[4]  = 8'h0F; expected[5]  = 8'h2F; expected[6]  = 8'h6B; expected[7]  = 8'h98;
        expected[8]  = 8'hCA; expected[9]  = 8'hF2; expected[10] = 8'h9F; expected[11] = 8'h8F;
        expected[12] = 8'hDE; expected[13] = 8'hA8; expected[14] = 8'h9B; expected[15] = 8'h64;
        expected[16] = 8'hA1; expected[17] = 8'hFA; expected[18] = 8'h70; expected[19] = 8'hAA;
        expected[20] = 8'h24; expected[21] = 8'h9B; expected[22] = 8'h8F; expected[23] = 8'h83;
        expected[24] = 8'h9B; expected[25] = 8'hD5; expected[26] = 8'h3B; expected[27] = 8'hAA;
        expected[28] = 8'h30; expected[29] = 8'h4D; expected[30] = 8'h92; expected[31] = 8'hB2;
    end

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task push_cmd;
        input [7:0] b;
        begin
            @(negedge clk);
            force dut.u_fifo0.wr_en = 1'b1;
            force dut.u_fifo0.wr_data = b;
            @(negedge clk);
            force dut.u_fifo0.wr_en = 1'b0;
            release dut.u_fifo0.wr_en;
            release dut.u_fifo0.wr_data;
            repeat (2) tick();
        end
    endtask

    integer k;
    integer guard;

    initial begin
        $dumpfile("tb_sdmc_uart_top_hash_empty_fast.vcd");
        $dumpvars(0, tb_sdmc_uart_top_hash_empty_fast);

        rst_n = 1'b0;
        repeat (10) tick();
        rst_n = 1'b1;
        repeat (10) tick();

        // Command frame: HASH256, data_len=0, out_len=32, chain_count=1.
        push_cmd(8'hA5);
        push_cmd(8'd1);
        push_cmd(8'h00);
        push_cmd(8'h00);
        push_cmd(8'h00);
        push_cmd(8'h00);
        push_cmd(8'h00);
        push_cmd(8'd32);
        push_cmd(8'h00);
        push_cmd(8'd1);
        push_cmd(8'h00);
        push_cmd(8'h00);
        push_cmd(8'h00);
        push_cmd(8'h5A);

        k = 0;
        guard = 0;
        while (k < 32) begin
            tick();
            guard = guard + 1;

            if (dut.sdmc_out_valid && dut.sdmc_out_ready) begin
                got[k] = dut.sdmc_out_byte;
                k = k + 1;
            end

            if (guard > 200000) begin
                $display("FAIL timeout k=%0d frame_valid=%b bridge_state=%0d sdmc_busy=%b sdmc_done=%b sdmc_error=%b host_mode=%0d program_id=%0d in_count=%0d out_count=%0d",
                    k,
                    dut.frame_valid,
                    dut.u_token_bridge.state,
                    dut.sdmc_busy,
                    dut.sdmc_done,
                    dut.sdmc_error,
                    dut.host_mode,
                    dut.program_id,
                    dut.in_count,
                    dut.out_count);
                $finish;
            end
        end

        $write("GOT=");
        for (k = 0; k < 32; k = k + 1) $write("%02x", got[k]);
        $write("\nEXP=");
        for (k = 0; k < 32; k = k + 1) $write("%02x", expected[k]);
        $write("\n");

        for (k = 0; k < 32; k = k + 1) begin
            if (got[k] !== expected[k]) begin
                $display("FAIL byte mismatch idx=%0d got=%02x exp=%02x", k, got[k], expected[k]);
                $finish;
            end
        end

        $display("PASS sdmc_uart_top_hash_empty_fast");
        $finish;
    end

endmodule

`default_nettype wire
