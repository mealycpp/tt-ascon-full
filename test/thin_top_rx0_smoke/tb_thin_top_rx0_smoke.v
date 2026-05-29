`timescale 1ns/1ps
`default_nettype none

module tb_thin_top_rx0_smoke;

    localparam integer BIT_CYC = 208;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ena = 1'b1;
    reg [7:0] ui_in = 8'h07;
    reg [7:0] uio_in = 8'h00;

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

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    task send_uart0;
        input [7:0] b;
        integer i;
        begin
            ui_in[0] = 1'b0;
            wait_cycles(BIT_CYC);

            for (i = 0; i < 8; i = i + 1) begin
                ui_in[0] = b[i];
                wait_cycles(BIT_CYC);
            end

            ui_in[0] = 1'b1;
            wait_cycles(BIT_CYC);
            wait_cycles(BIT_CYC);
        end
    endtask

    initial begin
        $dumpfile("tb_thin_top_rx0_smoke.vcd");
        $dumpvars(0, tb_thin_top_rx0_smoke);

        ui_in = 8'h07;
        rst_n = 1'b0;
        wait_cycles(50);
        rst_n = 1'b1;
        wait_cycles(50);

        send_uart0(8'hA5);

        wait_cycles(5000);

        $display("FAIL no rx0_valid ui0=%b rx_active=%b rx0_byte=%02x",
            ui_in[0], dut.rx0_active, dut.rx0_byte);
        $finish;
    end

    always @(posedge clk) begin
        if (dut.rx0_valid) begin
            $display("TOP_RX0=%02x", dut.rx0_byte);
            if (dut.rx0_byte == 8'hA5) begin
                $display("PASS thin_top_rx0_smoke");
                $finish;
            end else begin
                $display("FAIL wrong top rx0 byte=%02x", dut.rx0_byte);
                $finish;
            end
        end
    end

endmodule

`default_nettype wire
