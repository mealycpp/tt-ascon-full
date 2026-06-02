`timescale 1ns/1ps
`default_nettype none

module tb_hash_c0022_m21;

    localparam integer CLK_HALF = 5;
    localparam integer BAUD_DIV = 217;
    localparam integer BIT_CYCLES = BAUD_DIV;
    localparam integer MSG_LEN = 21;
    localparam integer MD_LEN = 32;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [7:0] msg [0:20];
    reg [7:0] exp_md [0:31];
    reg [7:0] got_md [0:31];

    integer i;
    integer errors;
    integer md_rx_count;
    integer timeout_count;
    reg capture_md;

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

    initial begin
        clk = 1'b0;
        forever #CLK_HALF clk = ~clk;
    end

    task automatic wait_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    task automatic uart_send_byte;
        input [7:0] b;
        integer bi;
        begin
            ui_in[0] = 1'b0;
            wait_cycles(BIT_CYCLES);
            for (bi = 0; bi < 8; bi = bi + 1) begin
                ui_in[0] = b[bi];
                wait_cycles(BIT_CYCLES);
            end
            ui_in[0] = 1'b1;
            wait_cycles(BIT_CYCLES);
        end
    endtask

    task automatic uart_recv_byte;
        output [7:0] b;
        integer bi;
        begin
            while (uo_out[0] !== 1'b0) @(posedge clk);
            wait_cycles(BIT_CYCLES + (BIT_CYCLES/2));
            for (bi = 0; bi < 8; bi = bi + 1) begin
                b[bi] = uo_out[0];
                wait_cycles(BIT_CYCLES);
            end
            wait_cycles(BIT_CYCLES/2);
        end
    endtask

    task automatic uart_rx_monitor;
        reg [7:0] b;
        begin
            forever begin
                uart_recv_byte(b);
                if (capture_md && md_rx_count < MD_LEN) begin
                    got_md[md_rx_count] = b;
                    md_rx_count = md_rx_count + 1;
                end
            end
        end
    endtask

    task automatic send_hash_cmd;
        begin
            uart_send_byte(8'hA5);
            uart_send_byte(8'd1);              // HASH256 mode
            uart_send_byte(8'h00);             // flags
            uart_send_byte(8'h00);             // ad/custom len lo
            uart_send_byte(8'h00);             // ad/custom len hi
            uart_send_byte(MSG_LEN[7:0]);      // msg len lo
            uart_send_byte(MSG_LEN[15:8]);     // msg len hi
            uart_send_byte(8'd32);             // out len lo
            uart_send_byte(8'h00);             // out len hi
            uart_send_byte(8'h01);             // chain count lo, ignored
            uart_send_byte(8'h00);             // chain count hi
            uart_send_byte(8'h00);             // reserved
            uart_send_byte(8'h00);             // reserved
            uart_send_byte(8'h5A);
        end
    endtask

    initial begin
        errors = 0;
        md_rx_count = 0;
        timeout_count = 0;
        capture_md = 1'b0;
        ui_in = 8'hff;
        uio_in = 8'h00;
        ena = 1'b1;
        rst_n = 1'b0;

        msg[0] = 8'h00;
        msg[1] = 8'h01;
        msg[2] = 8'h02;
        msg[3] = 8'h03;
        msg[4] = 8'h04;
        msg[5] = 8'h05;
        msg[6] = 8'h06;
        msg[7] = 8'h07;
        msg[8] = 8'h08;
        msg[9] = 8'h09;
        msg[10] = 8'h0a;
        msg[11] = 8'h0b;
        msg[12] = 8'h0c;
        msg[13] = 8'h0d;
        msg[14] = 8'h0e;
        msg[15] = 8'h0f;
        msg[16] = 8'h10;
        msg[17] = 8'h11;
        msg[18] = 8'h12;
        msg[19] = 8'h13;
        msg[20] = 8'h14;
        exp_md[0] = 8'h41;
        exp_md[1] = 8'hc8;
        exp_md[2] = 8'hf7;
        exp_md[3] = 8'h33;
        exp_md[4] = 8'hb9;
        exp_md[5] = 8'hd8;
        exp_md[6] = 8'h23;
        exp_md[7] = 8'hbe;
        exp_md[8] = 8'h30;
        exp_md[9] = 8'hb6;
        exp_md[10] = 8'h4e;
        exp_md[11] = 8'he7;
        exp_md[12] = 8'h17;
        exp_md[13] = 8'hc3;
        exp_md[14] = 8'h22;
        exp_md[15] = 8'hc5;
        exp_md[16] = 8'h76;
        exp_md[17] = 8'hd3;
        exp_md[18] = 8'h67;
        exp_md[19] = 8'h81;
        exp_md[20] = 8'hff;
        exp_md[21] = 8'hc5;
        exp_md[22] = 8'hf7;
        exp_md[23] = 8'hd6;
        exp_md[24] = 8'hc7;
        exp_md[25] = 8'h30;
        exp_md[26] = 8'hec;
        exp_md[27] = 8'ha5;
        exp_md[28] = 8'h49;
        exp_md[29] = 8'h78;
        exp_md[30] = 8'h97;
        exp_md[31] = 8'h25;

        wait_cycles(20);
        rst_n = 1'b1;
        wait_cycles(100);

        fork
            uart_rx_monitor();
        join_none

        capture_md = 1'b1;

        $display("DBG HASH start name=hash_c0022_m21 Count=22 MSG_LEN=%0d t=%0t", MSG_LEN, $time);

        send_hash_cmd();

        for (i = 0; i < MSG_LEN; i = i + 1) begin
            uart_send_byte(msg[i]);
        end

        while (md_rx_count < MD_LEN && timeout_count < 2000000) begin
            timeout_count = timeout_count + 1;
            @(posedge clk);
        end

        capture_md = 1'b0;

        if (md_rx_count != MD_LEN) begin
            $display("FAIL HASH_TIMEOUT name=hash_c0022_m21 Count=22 MSG_LEN=%0d md_rx_count=%0d",
                     MSG_LEN, md_rx_count);
            errors = errors + 1;
        end

        for (i = 0; i < MD_LEN; i = i + 1) begin
            if (got_md[i] !== exp_md[i]) begin
                if (errors == 0) begin
                    $display("FAIL HASH_FIRST_MISMATCH name=hash_c0022_m21 Count=22 MSG_LEN=%0d idx=%0d got_byte=%02x exp_byte=%02x",
                             MSG_LEN, i, got_md[i], exp_md[i]);
                end
                errors = errors + 1;
            end
        end

        $write("GOT_MD name=hash_c0022_m21 Count=22 MSG_LEN=%0d got=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", got_md[i]);
        $display("");

        $write("EXP_MD name=hash_c0022_m21 Count=22 MSG_LEN=%0d exp=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", exp_md[i]);
        $display("");

        if (errors == 0)
            $display("PASS HASH_KAT name=hash_c0022_m21 Count=22 MSG_LEN=%0d MD_LEN=32", MSG_LEN);
        else
            $display("FAIL HASH_KAT name=hash_c0022_m21 Count=22 MSG_LEN=%0d errors=%0d", MSG_LEN, errors);

        $finish;
    end

endmodule

`default_nettype wire
