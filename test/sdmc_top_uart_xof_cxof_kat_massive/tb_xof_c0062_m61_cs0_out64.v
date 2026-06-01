`timescale 1ns/1ps
`default_nettype none

module tb_xof_c0062_m61_cs0_out64;

    localparam integer CLK_HALF = 5;
    localparam integer BAUD_DIV = 217;
    localparam integer BIT_CYCLES = BAUD_DIV;

    localparam integer MODE = 2;
    localparam integer MSG_LEN = 61;
    localparam integer CS_LEN = 0;
    localparam integer OUT_LEN = 64;
    localparam integer CHAIN_COUNT = 1;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [7:0] msg [0:60];
    reg [7:0] cs  [0:0];
    reg [7:0] exp_md [0:63];
    reg [7:0] got_md [0:63];

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
                if (capture_md && md_rx_count < OUT_LEN) begin
                    got_md[md_rx_count] = b;
                    md_rx_count = md_rx_count + 1;
                end
            end
        end
    endtask

    task automatic send_cmd;
        begin
            uart_send_byte(8'hA5);
            uart_send_byte(MODE[7:0]);
            uart_send_byte(8'h00);
            uart_send_byte(8'h00);
            uart_send_byte(8'h00);
            uart_send_byte(MSG_LEN[7:0]);
            uart_send_byte(MSG_LEN[15:8]);
            uart_send_byte(OUT_LEN[7:0]);
            uart_send_byte(OUT_LEN[15:8]);
            uart_send_byte(CHAIN_COUNT[7:0]);
            uart_send_byte(CHAIN_COUNT[15:8]);
            uart_send_byte(CS_LEN[7:0]);
            uart_send_byte(CS_LEN[15:8]);
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
        msg[21] = 8'h15;
        msg[22] = 8'h16;
        msg[23] = 8'h17;
        msg[24] = 8'h18;
        msg[25] = 8'h19;
        msg[26] = 8'h1a;
        msg[27] = 8'h1b;
        msg[28] = 8'h1c;
        msg[29] = 8'h1d;
        msg[30] = 8'h1e;
        msg[31] = 8'h1f;
        msg[32] = 8'h20;
        msg[33] = 8'h21;
        msg[34] = 8'h22;
        msg[35] = 8'h23;
        msg[36] = 8'h24;
        msg[37] = 8'h25;
        msg[38] = 8'h26;
        msg[39] = 8'h27;
        msg[40] = 8'h28;
        msg[41] = 8'h29;
        msg[42] = 8'h2a;
        msg[43] = 8'h2b;
        msg[44] = 8'h2c;
        msg[45] = 8'h2d;
        msg[46] = 8'h2e;
        msg[47] = 8'h2f;
        msg[48] = 8'h30;
        msg[49] = 8'h31;
        msg[50] = 8'h32;
        msg[51] = 8'h33;
        msg[52] = 8'h34;
        msg[53] = 8'h35;
        msg[54] = 8'h36;
        msg[55] = 8'h37;
        msg[56] = 8'h38;
        msg[57] = 8'h39;
        msg[58] = 8'h3a;
        msg[59] = 8'h3b;
        msg[60] = 8'h3c;

        exp_md[0] = 8'he4;
        exp_md[1] = 8'hbc;
        exp_md[2] = 8'h86;
        exp_md[3] = 8'h40;
        exp_md[4] = 8'hda;
        exp_md[5] = 8'hbe;
        exp_md[6] = 8'h20;
        exp_md[7] = 8'hb7;
        exp_md[8] = 8'h16;
        exp_md[9] = 8'h40;
        exp_md[10] = 8'h36;
        exp_md[11] = 8'h33;
        exp_md[12] = 8'h41;
        exp_md[13] = 8'h75;
        exp_md[14] = 8'h13;
        exp_md[15] = 8'he6;
        exp_md[16] = 8'hee;
        exp_md[17] = 8'h94;
        exp_md[18] = 8'h62;
        exp_md[19] = 8'h2e;
        exp_md[20] = 8'h3d;
        exp_md[21] = 8'h2e;
        exp_md[22] = 8'h47;
        exp_md[23] = 8'hb0;
        exp_md[24] = 8'hcd;
        exp_md[25] = 8'ha4;
        exp_md[26] = 8'h38;
        exp_md[27] = 8'h52;
        exp_md[28] = 8'hb7;
        exp_md[29] = 8'h0a;
        exp_md[30] = 8'h2b;
        exp_md[31] = 8'h47;
        exp_md[32] = 8'h47;
        exp_md[33] = 8'h7c;
        exp_md[34] = 8'h51;
        exp_md[35] = 8'h72;
        exp_md[36] = 8'h01;
        exp_md[37] = 8'h31;
        exp_md[38] = 8'h37;
        exp_md[39] = 8'hd4;
        exp_md[40] = 8'h3f;
        exp_md[41] = 8'he0;
        exp_md[42] = 8'h82;
        exp_md[43] = 8'h1c;
        exp_md[44] = 8'he0;
        exp_md[45] = 8'hb0;
        exp_md[46] = 8'h8e;
        exp_md[47] = 8'hf3;
        exp_md[48] = 8'h8b;
        exp_md[49] = 8'hb1;
        exp_md[50] = 8'hee;
        exp_md[51] = 8'hc3;
        exp_md[52] = 8'h0e;
        exp_md[53] = 8'h01;
        exp_md[54] = 8'h0e;
        exp_md[55] = 8'h8a;
        exp_md[56] = 8'hbd;
        exp_md[57] = 8'hff;
        exp_md[58] = 8'haf;
        exp_md[59] = 8'ha2;
        exp_md[60] = 8'h67;
        exp_md[61] = 8'h62;
        exp_md[62] = 8'h1f;
        exp_md[63] = 8'h87;

        wait_cycles(20);
        rst_n = 1'b1;
        wait_cycles(100);

        fork
            uart_rx_monitor();
        join_none

        capture_md = 1'b1;

        $display("DBG XOF_TOP start name=xof_c0062_m61_cs0_out64 mode=%0d msg=%0d cs=%0d out=%0d",
                 MODE, MSG_LEN, CS_LEN, OUT_LEN);

        send_cmd();

        for (i = 0; i < CS_LEN; i = i + 1) begin
            uart_send_byte(cs[i]);
        end

        for (i = 0; i < MSG_LEN; i = i + 1) begin
            uart_send_byte(msg[i]);
        end

        while (md_rx_count < OUT_LEN && timeout_count < 8000000) begin
            timeout_count = timeout_count + 1;
            @(posedge clk);
        end

        capture_md = 1'b0;

        if (md_rx_count != OUT_LEN) begin
            $display("FAIL XOF_TOP_TIMEOUT name=xof_c0062_m61_cs0_out64 rx=%0d expected=%0d",
                     md_rx_count, OUT_LEN);
            errors = errors + 1;
        end

        for (i = 0; i < OUT_LEN; i = i + 1) begin
            if (got_md[i] !== exp_md[i]) begin
                if (errors == 0) begin
                    $display("FAIL XOF_TOP_FIRST_MISMATCH name=xof_c0062_m61_cs0_out64 idx=%0d got=%02x exp=%02x",
                             i, got_md[i], exp_md[i]);
                end
                errors = errors + 1;
            end
        end

        $write("GOT_XOF_TOP name=xof_c0062_m61_cs0_out64 got=");
        for (i = 0; i < OUT_LEN; i = i + 1) $write("%02x", got_md[i]);
        $display("");

        $write("EXP_XOF_TOP name=xof_c0062_m61_cs0_out64 exp=");
        for (i = 0; i < OUT_LEN; i = i + 1) $write("%02x", exp_md[i]);
        $display("");

        if (errors == 0)
            $display("PASS XOF_TOP name=xof_c0062_m61_cs0_out64 mode=%0d msg=%0d cs=%0d out=%0d",
                     MODE, MSG_LEN, CS_LEN, OUT_LEN);
        else
            $display("FAIL XOF_TOP name=xof_c0062_m61_cs0_out64 errors=%0d", errors);

        $finish;
    end

endmodule

`default_nettype wire
