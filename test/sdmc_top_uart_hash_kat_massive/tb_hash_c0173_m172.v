`timescale 1ns/1ps
`default_nettype none

module tb_hash_c0173_m172;

    localparam integer CLK_HALF = 5;
    localparam integer BAUD_DIV = 217;
    localparam integer BIT_CYCLES = BAUD_DIV;
    localparam integer MSG_LEN = 172;
    localparam integer MD_LEN = 32;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [7:0] msg [0:171];
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
        msg[61] = 8'h3d;
        msg[62] = 8'h3e;
        msg[63] = 8'h3f;
        msg[64] = 8'h40;
        msg[65] = 8'h41;
        msg[66] = 8'h42;
        msg[67] = 8'h43;
        msg[68] = 8'h44;
        msg[69] = 8'h45;
        msg[70] = 8'h46;
        msg[71] = 8'h47;
        msg[72] = 8'h48;
        msg[73] = 8'h49;
        msg[74] = 8'h4a;
        msg[75] = 8'h4b;
        msg[76] = 8'h4c;
        msg[77] = 8'h4d;
        msg[78] = 8'h4e;
        msg[79] = 8'h4f;
        msg[80] = 8'h50;
        msg[81] = 8'h51;
        msg[82] = 8'h52;
        msg[83] = 8'h53;
        msg[84] = 8'h54;
        msg[85] = 8'h55;
        msg[86] = 8'h56;
        msg[87] = 8'h57;
        msg[88] = 8'h58;
        msg[89] = 8'h59;
        msg[90] = 8'h5a;
        msg[91] = 8'h5b;
        msg[92] = 8'h5c;
        msg[93] = 8'h5d;
        msg[94] = 8'h5e;
        msg[95] = 8'h5f;
        msg[96] = 8'h60;
        msg[97] = 8'h61;
        msg[98] = 8'h62;
        msg[99] = 8'h63;
        msg[100] = 8'h64;
        msg[101] = 8'h65;
        msg[102] = 8'h66;
        msg[103] = 8'h67;
        msg[104] = 8'h68;
        msg[105] = 8'h69;
        msg[106] = 8'h6a;
        msg[107] = 8'h6b;
        msg[108] = 8'h6c;
        msg[109] = 8'h6d;
        msg[110] = 8'h6e;
        msg[111] = 8'h6f;
        msg[112] = 8'h70;
        msg[113] = 8'h71;
        msg[114] = 8'h72;
        msg[115] = 8'h73;
        msg[116] = 8'h74;
        msg[117] = 8'h75;
        msg[118] = 8'h76;
        msg[119] = 8'h77;
        msg[120] = 8'h78;
        msg[121] = 8'h79;
        msg[122] = 8'h7a;
        msg[123] = 8'h7b;
        msg[124] = 8'h7c;
        msg[125] = 8'h7d;
        msg[126] = 8'h7e;
        msg[127] = 8'h7f;
        msg[128] = 8'h80;
        msg[129] = 8'h81;
        msg[130] = 8'h82;
        msg[131] = 8'h83;
        msg[132] = 8'h84;
        msg[133] = 8'h85;
        msg[134] = 8'h86;
        msg[135] = 8'h87;
        msg[136] = 8'h88;
        msg[137] = 8'h89;
        msg[138] = 8'h8a;
        msg[139] = 8'h8b;
        msg[140] = 8'h8c;
        msg[141] = 8'h8d;
        msg[142] = 8'h8e;
        msg[143] = 8'h8f;
        msg[144] = 8'h90;
        msg[145] = 8'h91;
        msg[146] = 8'h92;
        msg[147] = 8'h93;
        msg[148] = 8'h94;
        msg[149] = 8'h95;
        msg[150] = 8'h96;
        msg[151] = 8'h97;
        msg[152] = 8'h98;
        msg[153] = 8'h99;
        msg[154] = 8'h9a;
        msg[155] = 8'h9b;
        msg[156] = 8'h9c;
        msg[157] = 8'h9d;
        msg[158] = 8'h9e;
        msg[159] = 8'h9f;
        msg[160] = 8'ha0;
        msg[161] = 8'ha1;
        msg[162] = 8'ha2;
        msg[163] = 8'ha3;
        msg[164] = 8'ha4;
        msg[165] = 8'ha5;
        msg[166] = 8'ha6;
        msg[167] = 8'ha7;
        msg[168] = 8'ha8;
        msg[169] = 8'ha9;
        msg[170] = 8'haa;
        msg[171] = 8'hab;
        exp_md[0] = 8'hb3;
        exp_md[1] = 8'h06;
        exp_md[2] = 8'hdc;
        exp_md[3] = 8'h81;
        exp_md[4] = 8'h81;
        exp_md[5] = 8'h05;
        exp_md[6] = 8'hcf;
        exp_md[7] = 8'h47;
        exp_md[8] = 8'h4a;
        exp_md[9] = 8'h28;
        exp_md[10] = 8'h5c;
        exp_md[11] = 8'h5b;
        exp_md[12] = 8'h29;
        exp_md[13] = 8'hbc;
        exp_md[14] = 8'h12;
        exp_md[15] = 8'h7c;
        exp_md[16] = 8'h3c;
        exp_md[17] = 8'he5;
        exp_md[18] = 8'h88;
        exp_md[19] = 8'hc1;
        exp_md[20] = 8'h2b;
        exp_md[21] = 8'hbc;
        exp_md[22] = 8'h99;
        exp_md[23] = 8'h2d;
        exp_md[24] = 8'h71;
        exp_md[25] = 8'h57;
        exp_md[26] = 8'ha9;
        exp_md[27] = 8'h06;
        exp_md[28] = 8'hc8;
        exp_md[29] = 8'h4e;
        exp_md[30] = 8'h60;
        exp_md[31] = 8'h2d;

        wait_cycles(20);
        rst_n = 1'b1;
        wait_cycles(100);

        fork
            uart_rx_monitor();
        join_none

        capture_md = 1'b1;

        $display("DBG HASH start name=hash_c0173_m172 Count=173 MSG_LEN=%0d t=%0t", MSG_LEN, $time);

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
            $display("FAIL HASH_TIMEOUT name=hash_c0173_m172 Count=173 MSG_LEN=%0d md_rx_count=%0d",
                     MSG_LEN, md_rx_count);
            errors = errors + 1;
        end

        for (i = 0; i < MD_LEN; i = i + 1) begin
            if (got_md[i] !== exp_md[i]) begin
                if (errors == 0) begin
                    $display("FAIL HASH_FIRST_MISMATCH name=hash_c0173_m172 Count=173 MSG_LEN=%0d idx=%0d got_byte=%02x exp_byte=%02x",
                             MSG_LEN, i, got_md[i], exp_md[i]);
                end
                errors = errors + 1;
            end
        end

        $write("GOT_MD name=hash_c0173_m172 Count=173 MSG_LEN=%0d got=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", got_md[i]);
        $display("");

        $write("EXP_MD name=hash_c0173_m172 Count=173 MSG_LEN=%0d exp=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", exp_md[i]);
        $display("");

        if (errors == 0)
            $display("PASS HASH_KAT name=hash_c0173_m172 Count=173 MSG_LEN=%0d MD_LEN=32", MSG_LEN);
        else
            $display("FAIL HASH_KAT name=hash_c0173_m172 Count=173 MSG_LEN=%0d errors=%0d", MSG_LEN, errors);

        $finish;
    end

endmodule

`default_nettype wire
