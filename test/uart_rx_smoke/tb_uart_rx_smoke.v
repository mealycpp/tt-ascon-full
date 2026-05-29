`timescale 1ns/1ps
`default_nettype none

module tb_uart_rx_smoke;

    localparam integer BIT_CYC = 208;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg rx = 1'b1;

    wire [7:0] byte_out;
    wire byte_valid;
    wire rx_active;

    uart_rx dut (
        .clk(clk),
        .rst_n(rst_n),
        .baud_div(16'd217),
        .rx(rx),
        .byte_out(byte_out),
        .byte_valid(byte_valid),
        .rx_active(rx_active)
    );

    always #5 clk = ~clk;

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    task send_byte;
        input [7:0] b;
        integer i;
        begin
            rx = 1'b0; wait_cycles(BIT_CYC);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                wait_cycles(BIT_CYC);
            end
            rx = 1'b1; wait_cycles(BIT_CYC);
            wait_cycles(BIT_CYC);
        end
    endtask

    initial begin
        $dumpfile("tb_uart_rx_smoke.vcd");
        $dumpvars(0, tb_uart_rx_smoke);

        rst_n = 1'b0;
        wait_cycles(50);
        rst_n = 1'b1;
        wait_cycles(50);

        send_byte(8'hA5);

        wait_cycles(5000);
        $display("FAIL no byte_valid");
        $finish;
    end

    always @(posedge clk) begin
        if (byte_valid) begin
            $display("RX=%02x", byte_out);
            if (byte_out == 8'hA5) begin
                $display("PASS uart_rx_smoke");
                $finish;
            end else begin
                $display("FAIL got wrong byte %02x", byte_out);
                $finish;
            end
        end
    end

endmodule

`default_nettype wire
