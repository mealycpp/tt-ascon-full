`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_aead_uart_frontend_cmd;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    reg [7:0] rx0_byte = 8'd0;
    reg       rx0_valid = 1'b0;
    reg [7:0] rx1_byte = 8'd0;
    reg       rx1_valid = 1'b0;
    reg [7:0] rx2_byte = 8'd0;
    reg       rx2_valid = 1'b0;

    wire        aead_start;
    wire        aead_is_decrypt;
    wire [15:0] aead_ad_len;
    wire [15:0] aead_data_len;

    wire [72:0] aead_in_token;
    wire        aead_in_empty;
    reg         aead_in_pop = 1'b0;

    wire busy;
    wire error;
    wire [3:0] phase_dbg;

    sdmc_aead_uart_frontend dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .rx0_byte(rx0_byte),
        .rx0_valid(rx0_valid),
        .rx1_byte(rx1_byte),
        .rx1_valid(rx1_valid),
        .rx2_byte(rx2_byte),
        .rx2_valid(rx2_valid),

        .aead_start(aead_start),
        .aead_is_decrypt(aead_is_decrypt),
        .aead_ad_len(aead_ad_len),
        .aead_data_len(aead_data_len),

        .aead_in_token(aead_in_token),
        .aead_in_empty(aead_in_empty),
        .aead_in_pop(aead_in_pop),

        .busy(busy),
        .error(error),
        .phase_dbg(phase_dbg)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task send_cmd_byte;
        input [7:0] b;
        begin
            rx0_byte = b;
            rx0_valid = 1'b1;
            tick();
            rx0_valid = 1'b0;
            rx0_byte = 8'd0;
            tick();
        end
    endtask

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_aead_uart_frontend_cmd.vcd");
        $dumpvars(0, tb_sdmc_aead_uart_frontend_cmd);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (5) tick();

        // Command: AEAD_ENC, AD=0, DATA=3.
        send_cmd_byte(8'hA5);
        send_cmd_byte(8'd5);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'd3);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'd1);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'h00);
        send_cmd_byte(8'h5A);

        guard = 0;
        while (!aead_start && guard < 20) begin
            tick();
            guard = guard + 1;
        end

        if (!busy) begin
            $display("FAIL frontend did not enter busy phase=%0d error=%b", phase_dbg, error);
            $finish;
        end

        if (error) begin
            $display("FAIL frontend error after command");
            $finish;
        end

        if (aead_ad_len !== 16'd0 || aead_data_len !== 16'd3 || aead_is_decrypt !== 1'b0) begin
            $display("FAIL cfg mismatch ad=%0d data=%0d dec=%b", aead_ad_len, aead_data_len, aead_is_decrypt);
            $finish;
        end

        if (phase_dbg !== 4'd1) begin
            $display("FAIL expected PH_KEY phase=1 got %0d", phase_dbg);
            $finish;
        end

        $display("PASS sdmc_aead_uart_frontend_cmd");
        $finish;
    end

endmodule

`default_nettype wire
