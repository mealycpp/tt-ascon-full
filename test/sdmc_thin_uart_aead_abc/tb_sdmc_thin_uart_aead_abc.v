`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_thin_uart_aead_abc;

    localparam integer RX_BIT_CYC = 208;

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

    reg [7:0] expected [0:18];
    reg [7:0] got [0:18];
    integer rx_count = 0;
    integer k;

    initial begin
        expected[0]  = 8'ha9; expected[1]  = 8'h80; expected[2]  = 8'h9f;
        expected[3]  = 8'h51; expected[4]  = 8'h76; expected[5]  = 8'h28;
        expected[6]  = 8'ha4; expected[7]  = 8'h0f; expected[8]  = 8'h72;
        expected[9]  = 8'h90; expected[10] = 8'h02; expected[11] = 8'hc2;
        expected[12] = 8'h13; expected[13] = 8'h09; expected[14] = 8'hc2;
        expected[15] = 8'h96; expected[16] = 8'hb2; expected[17] = 8'h5c;
        expected[18] = 8'h17;
    end

    task automatic wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    task automatic uart_send_byte;
        input integer line;
        input [7:0] data;
        integer i;
        begin
            ui_in[line] = 1'b0;
            wait_cycles(RX_BIT_CYC);

            for (i = 0; i < 8; i = i + 1) begin
                ui_in[line] = data[i];
                wait_cycles(RX_BIT_CYC);
            end

            ui_in[line] = 1'b1;
            wait_cycles(RX_BIT_CYC);
            wait_cycles(RX_BIT_CYC);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_count <= 0;
        end else if (dut.tx_send) begin
            if (rx_count < 19) begin
                got[rx_count] <= dut.tx_byte;
                $display("TX_BYTE[%0d]=%02x t=%0t", rx_count, dut.tx_byte, $time);
                rx_count <= rx_count + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.rx0_valid) $display("RX0 byte=%02x cmd_state=%0d t=%0t", dut.rx0_byte, dut.u_front.cmd_state, $time);
            if (dut.rx1_valid) $display("RX1 byte=%02x phase=%0d t=%0t", dut.rx1_byte, dut.front_phase, $time);
            if (dut.rx2_valid) $display("RX2 byte=%02x phase=%0d t=%0t", dut.rx2_byte, dut.front_phase, $time);
            if (dut.aead_start) $display("AEAD_START ad_len=%0d data_len=%0d dec=%b phase=%0d t=%0t",
                dut.aead_ad_len, dut.aead_data_len, dut.aead_is_decrypt, dut.front_phase, $time);
        end
    end

    initial begin
        $dumpfile("tb_sdmc_thin_uart_aead_abc.vcd");
        $dumpvars(0, tb_sdmc_thin_uart_aead_abc);

        ui_in = 8'h07;
        rst_n = 1'b0;
        wait_cycles(50);
        rst_n = 1'b1;
        wait_cycles(100);

        // Command: AEAD_ENC, AD=0, DATA=3.
        uart_send_byte(0, 8'hA5);
        uart_send_byte(0, 8'd5);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'd3);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'd1);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h5A);

        // UART1 key.
        for (k = 0; k < 16; k = k + 1) uart_send_byte(1, k[7:0]);

        // UART1 nonce.
        for (k = 16; k < 32; k = k + 1) uart_send_byte(1, k[7:0]);

        // UART2 plaintext "abc".
        uart_send_byte(2, 8'h61);
        uart_send_byte(2, 8'h62);
        uart_send_byte(2, 8'h63);

        wait (rx_count >= 19);
        wait_cycles(10);

        $write("GOT=");
        for (k = 0; k < 19; k = k + 1) $write("%02x", got[k]);
        $write("\nEXP=");
        for (k = 0; k < 19; k = k + 1) $write("%02x", expected[k]);
        $write("\n");

        for (k = 0; k < 19; k = k + 1) begin
            if (got[k] !== expected[k]) begin
                $display("FAIL byte mismatch idx=%0d got=%02x exp=%02x phase=%0d busy=%b done=%b err=%b",
                    k, got[k], expected[k], dut.front_phase, dut.aead_busy, dut.aead_done, dut.aead_error);
                $finish;
            end
        end

        if (dut.aead_error || dut.front_error) begin
            $display("FAIL error asserted front=%b aead=%b", dut.front_error, dut.aead_error);
            $finish;
        end

        $display("PASS sdmc_thin_uart_aead_abc");
        $finish;
    end

    initial begin
        wait_cycles(3000000);
        $display("FAIL timeout rx_count=%0d phase=%0d front_busy=%b front_err=%b aead_busy=%b aead_done=%b aead_error=%b uo2=%b",
            rx_count, dut.front_phase, dut.front_busy, dut.front_error, dut.aead_busy, dut.aead_done, dut.aead_error, uo_out[2]);
        $finish;
    end

endmodule

`default_nettype wire
