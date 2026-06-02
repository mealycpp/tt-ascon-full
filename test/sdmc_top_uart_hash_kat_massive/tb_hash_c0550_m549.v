`timescale 1ns/1ps
`default_nettype none

module tb_hash_c0550_m549;

    localparam integer CLK_HALF = 5;
    localparam integer BAUD_DIV = 217;
    localparam integer BIT_CYCLES = BAUD_DIV;
    localparam integer MSG_LEN = 549;
    localparam integer MD_LEN = 32;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [7:0] msg [0:548];
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
        msg[172] = 8'hac;
        msg[173] = 8'had;
        msg[174] = 8'hae;
        msg[175] = 8'haf;
        msg[176] = 8'hb0;
        msg[177] = 8'hb1;
        msg[178] = 8'hb2;
        msg[179] = 8'hb3;
        msg[180] = 8'hb4;
        msg[181] = 8'hb5;
        msg[182] = 8'hb6;
        msg[183] = 8'hb7;
        msg[184] = 8'hb8;
        msg[185] = 8'hb9;
        msg[186] = 8'hba;
        msg[187] = 8'hbb;
        msg[188] = 8'hbc;
        msg[189] = 8'hbd;
        msg[190] = 8'hbe;
        msg[191] = 8'hbf;
        msg[192] = 8'hc0;
        msg[193] = 8'hc1;
        msg[194] = 8'hc2;
        msg[195] = 8'hc3;
        msg[196] = 8'hc4;
        msg[197] = 8'hc5;
        msg[198] = 8'hc6;
        msg[199] = 8'hc7;
        msg[200] = 8'hc8;
        msg[201] = 8'hc9;
        msg[202] = 8'hca;
        msg[203] = 8'hcb;
        msg[204] = 8'hcc;
        msg[205] = 8'hcd;
        msg[206] = 8'hce;
        msg[207] = 8'hcf;
        msg[208] = 8'hd0;
        msg[209] = 8'hd1;
        msg[210] = 8'hd2;
        msg[211] = 8'hd3;
        msg[212] = 8'hd4;
        msg[213] = 8'hd5;
        msg[214] = 8'hd6;
        msg[215] = 8'hd7;
        msg[216] = 8'hd8;
        msg[217] = 8'hd9;
        msg[218] = 8'hda;
        msg[219] = 8'hdb;
        msg[220] = 8'hdc;
        msg[221] = 8'hdd;
        msg[222] = 8'hde;
        msg[223] = 8'hdf;
        msg[224] = 8'he0;
        msg[225] = 8'he1;
        msg[226] = 8'he2;
        msg[227] = 8'he3;
        msg[228] = 8'he4;
        msg[229] = 8'he5;
        msg[230] = 8'he6;
        msg[231] = 8'he7;
        msg[232] = 8'he8;
        msg[233] = 8'he9;
        msg[234] = 8'hea;
        msg[235] = 8'heb;
        msg[236] = 8'hec;
        msg[237] = 8'hed;
        msg[238] = 8'hee;
        msg[239] = 8'hef;
        msg[240] = 8'hf0;
        msg[241] = 8'hf1;
        msg[242] = 8'hf2;
        msg[243] = 8'hf3;
        msg[244] = 8'hf4;
        msg[245] = 8'hf5;
        msg[246] = 8'hf6;
        msg[247] = 8'hf7;
        msg[248] = 8'hf8;
        msg[249] = 8'hf9;
        msg[250] = 8'hfa;
        msg[251] = 8'hfb;
        msg[252] = 8'hfc;
        msg[253] = 8'hfd;
        msg[254] = 8'hfe;
        msg[255] = 8'hff;
        msg[256] = 8'h00;
        msg[257] = 8'h01;
        msg[258] = 8'h02;
        msg[259] = 8'h03;
        msg[260] = 8'h04;
        msg[261] = 8'h05;
        msg[262] = 8'h06;
        msg[263] = 8'h07;
        msg[264] = 8'h08;
        msg[265] = 8'h09;
        msg[266] = 8'h0a;
        msg[267] = 8'h0b;
        msg[268] = 8'h0c;
        msg[269] = 8'h0d;
        msg[270] = 8'h0e;
        msg[271] = 8'h0f;
        msg[272] = 8'h10;
        msg[273] = 8'h11;
        msg[274] = 8'h12;
        msg[275] = 8'h13;
        msg[276] = 8'h14;
        msg[277] = 8'h15;
        msg[278] = 8'h16;
        msg[279] = 8'h17;
        msg[280] = 8'h18;
        msg[281] = 8'h19;
        msg[282] = 8'h1a;
        msg[283] = 8'h1b;
        msg[284] = 8'h1c;
        msg[285] = 8'h1d;
        msg[286] = 8'h1e;
        msg[287] = 8'h1f;
        msg[288] = 8'h20;
        msg[289] = 8'h21;
        msg[290] = 8'h22;
        msg[291] = 8'h23;
        msg[292] = 8'h24;
        msg[293] = 8'h25;
        msg[294] = 8'h26;
        msg[295] = 8'h27;
        msg[296] = 8'h28;
        msg[297] = 8'h29;
        msg[298] = 8'h2a;
        msg[299] = 8'h2b;
        msg[300] = 8'h2c;
        msg[301] = 8'h2d;
        msg[302] = 8'h2e;
        msg[303] = 8'h2f;
        msg[304] = 8'h30;
        msg[305] = 8'h31;
        msg[306] = 8'h32;
        msg[307] = 8'h33;
        msg[308] = 8'h34;
        msg[309] = 8'h35;
        msg[310] = 8'h36;
        msg[311] = 8'h37;
        msg[312] = 8'h38;
        msg[313] = 8'h39;
        msg[314] = 8'h3a;
        msg[315] = 8'h3b;
        msg[316] = 8'h3c;
        msg[317] = 8'h3d;
        msg[318] = 8'h3e;
        msg[319] = 8'h3f;
        msg[320] = 8'h40;
        msg[321] = 8'h41;
        msg[322] = 8'h42;
        msg[323] = 8'h43;
        msg[324] = 8'h44;
        msg[325] = 8'h45;
        msg[326] = 8'h46;
        msg[327] = 8'h47;
        msg[328] = 8'h48;
        msg[329] = 8'h49;
        msg[330] = 8'h4a;
        msg[331] = 8'h4b;
        msg[332] = 8'h4c;
        msg[333] = 8'h4d;
        msg[334] = 8'h4e;
        msg[335] = 8'h4f;
        msg[336] = 8'h50;
        msg[337] = 8'h51;
        msg[338] = 8'h52;
        msg[339] = 8'h53;
        msg[340] = 8'h54;
        msg[341] = 8'h55;
        msg[342] = 8'h56;
        msg[343] = 8'h57;
        msg[344] = 8'h58;
        msg[345] = 8'h59;
        msg[346] = 8'h5a;
        msg[347] = 8'h5b;
        msg[348] = 8'h5c;
        msg[349] = 8'h5d;
        msg[350] = 8'h5e;
        msg[351] = 8'h5f;
        msg[352] = 8'h60;
        msg[353] = 8'h61;
        msg[354] = 8'h62;
        msg[355] = 8'h63;
        msg[356] = 8'h64;
        msg[357] = 8'h65;
        msg[358] = 8'h66;
        msg[359] = 8'h67;
        msg[360] = 8'h68;
        msg[361] = 8'h69;
        msg[362] = 8'h6a;
        msg[363] = 8'h6b;
        msg[364] = 8'h6c;
        msg[365] = 8'h6d;
        msg[366] = 8'h6e;
        msg[367] = 8'h6f;
        msg[368] = 8'h70;
        msg[369] = 8'h71;
        msg[370] = 8'h72;
        msg[371] = 8'h73;
        msg[372] = 8'h74;
        msg[373] = 8'h75;
        msg[374] = 8'h76;
        msg[375] = 8'h77;
        msg[376] = 8'h78;
        msg[377] = 8'h79;
        msg[378] = 8'h7a;
        msg[379] = 8'h7b;
        msg[380] = 8'h7c;
        msg[381] = 8'h7d;
        msg[382] = 8'h7e;
        msg[383] = 8'h7f;
        msg[384] = 8'h80;
        msg[385] = 8'h81;
        msg[386] = 8'h82;
        msg[387] = 8'h83;
        msg[388] = 8'h84;
        msg[389] = 8'h85;
        msg[390] = 8'h86;
        msg[391] = 8'h87;
        msg[392] = 8'h88;
        msg[393] = 8'h89;
        msg[394] = 8'h8a;
        msg[395] = 8'h8b;
        msg[396] = 8'h8c;
        msg[397] = 8'h8d;
        msg[398] = 8'h8e;
        msg[399] = 8'h8f;
        msg[400] = 8'h90;
        msg[401] = 8'h91;
        msg[402] = 8'h92;
        msg[403] = 8'h93;
        msg[404] = 8'h94;
        msg[405] = 8'h95;
        msg[406] = 8'h96;
        msg[407] = 8'h97;
        msg[408] = 8'h98;
        msg[409] = 8'h99;
        msg[410] = 8'h9a;
        msg[411] = 8'h9b;
        msg[412] = 8'h9c;
        msg[413] = 8'h9d;
        msg[414] = 8'h9e;
        msg[415] = 8'h9f;
        msg[416] = 8'ha0;
        msg[417] = 8'ha1;
        msg[418] = 8'ha2;
        msg[419] = 8'ha3;
        msg[420] = 8'ha4;
        msg[421] = 8'ha5;
        msg[422] = 8'ha6;
        msg[423] = 8'ha7;
        msg[424] = 8'ha8;
        msg[425] = 8'ha9;
        msg[426] = 8'haa;
        msg[427] = 8'hab;
        msg[428] = 8'hac;
        msg[429] = 8'had;
        msg[430] = 8'hae;
        msg[431] = 8'haf;
        msg[432] = 8'hb0;
        msg[433] = 8'hb1;
        msg[434] = 8'hb2;
        msg[435] = 8'hb3;
        msg[436] = 8'hb4;
        msg[437] = 8'hb5;
        msg[438] = 8'hb6;
        msg[439] = 8'hb7;
        msg[440] = 8'hb8;
        msg[441] = 8'hb9;
        msg[442] = 8'hba;
        msg[443] = 8'hbb;
        msg[444] = 8'hbc;
        msg[445] = 8'hbd;
        msg[446] = 8'hbe;
        msg[447] = 8'hbf;
        msg[448] = 8'hc0;
        msg[449] = 8'hc1;
        msg[450] = 8'hc2;
        msg[451] = 8'hc3;
        msg[452] = 8'hc4;
        msg[453] = 8'hc5;
        msg[454] = 8'hc6;
        msg[455] = 8'hc7;
        msg[456] = 8'hc8;
        msg[457] = 8'hc9;
        msg[458] = 8'hca;
        msg[459] = 8'hcb;
        msg[460] = 8'hcc;
        msg[461] = 8'hcd;
        msg[462] = 8'hce;
        msg[463] = 8'hcf;
        msg[464] = 8'hd0;
        msg[465] = 8'hd1;
        msg[466] = 8'hd2;
        msg[467] = 8'hd3;
        msg[468] = 8'hd4;
        msg[469] = 8'hd5;
        msg[470] = 8'hd6;
        msg[471] = 8'hd7;
        msg[472] = 8'hd8;
        msg[473] = 8'hd9;
        msg[474] = 8'hda;
        msg[475] = 8'hdb;
        msg[476] = 8'hdc;
        msg[477] = 8'hdd;
        msg[478] = 8'hde;
        msg[479] = 8'hdf;
        msg[480] = 8'he0;
        msg[481] = 8'he1;
        msg[482] = 8'he2;
        msg[483] = 8'he3;
        msg[484] = 8'he4;
        msg[485] = 8'he5;
        msg[486] = 8'he6;
        msg[487] = 8'he7;
        msg[488] = 8'he8;
        msg[489] = 8'he9;
        msg[490] = 8'hea;
        msg[491] = 8'heb;
        msg[492] = 8'hec;
        msg[493] = 8'hed;
        msg[494] = 8'hee;
        msg[495] = 8'hef;
        msg[496] = 8'hf0;
        msg[497] = 8'hf1;
        msg[498] = 8'hf2;
        msg[499] = 8'hf3;
        msg[500] = 8'hf4;
        msg[501] = 8'hf5;
        msg[502] = 8'hf6;
        msg[503] = 8'hf7;
        msg[504] = 8'hf8;
        msg[505] = 8'hf9;
        msg[506] = 8'hfa;
        msg[507] = 8'hfb;
        msg[508] = 8'hfc;
        msg[509] = 8'hfd;
        msg[510] = 8'hfe;
        msg[511] = 8'hff;
        msg[512] = 8'h00;
        msg[513] = 8'h01;
        msg[514] = 8'h02;
        msg[515] = 8'h03;
        msg[516] = 8'h04;
        msg[517] = 8'h05;
        msg[518] = 8'h06;
        msg[519] = 8'h07;
        msg[520] = 8'h08;
        msg[521] = 8'h09;
        msg[522] = 8'h0a;
        msg[523] = 8'h0b;
        msg[524] = 8'h0c;
        msg[525] = 8'h0d;
        msg[526] = 8'h0e;
        msg[527] = 8'h0f;
        msg[528] = 8'h10;
        msg[529] = 8'h11;
        msg[530] = 8'h12;
        msg[531] = 8'h13;
        msg[532] = 8'h14;
        msg[533] = 8'h15;
        msg[534] = 8'h16;
        msg[535] = 8'h17;
        msg[536] = 8'h18;
        msg[537] = 8'h19;
        msg[538] = 8'h1a;
        msg[539] = 8'h1b;
        msg[540] = 8'h1c;
        msg[541] = 8'h1d;
        msg[542] = 8'h1e;
        msg[543] = 8'h1f;
        msg[544] = 8'h20;
        msg[545] = 8'h21;
        msg[546] = 8'h22;
        msg[547] = 8'h23;
        msg[548] = 8'h24;
        exp_md[0] = 8'h1b;
        exp_md[1] = 8'hbe;
        exp_md[2] = 8'h63;
        exp_md[3] = 8'h6a;
        exp_md[4] = 8'h93;
        exp_md[5] = 8'heb;
        exp_md[6] = 8'had;
        exp_md[7] = 8'h11;
        exp_md[8] = 8'ha4;
        exp_md[9] = 8'h34;
        exp_md[10] = 8'hcc;
        exp_md[11] = 8'h20;
        exp_md[12] = 8'ha6;
        exp_md[13] = 8'h11;
        exp_md[14] = 8'ha1;
        exp_md[15] = 8'hd2;
        exp_md[16] = 8'h97;
        exp_md[17] = 8'h87;
        exp_md[18] = 8'h86;
        exp_md[19] = 8'h02;
        exp_md[20] = 8'ha1;
        exp_md[21] = 8'h35;
        exp_md[22] = 8'h56;
        exp_md[23] = 8'h5f;
        exp_md[24] = 8'h44;
        exp_md[25] = 8'ha4;
        exp_md[26] = 8'h7f;
        exp_md[27] = 8'hb9;
        exp_md[28] = 8'h41;
        exp_md[29] = 8'h7a;
        exp_md[30] = 8'h37;
        exp_md[31] = 8'h1b;

        wait_cycles(20);
        rst_n = 1'b1;
        wait_cycles(100);

        fork
            uart_rx_monitor();
        join_none

        capture_md = 1'b1;

        $display("DBG HASH start name=hash_c0550_m549 Count=550 MSG_LEN=%0d t=%0t", MSG_LEN, $time);

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
            $display("FAIL HASH_TIMEOUT name=hash_c0550_m549 Count=550 MSG_LEN=%0d md_rx_count=%0d",
                     MSG_LEN, md_rx_count);
            errors = errors + 1;
        end

        for (i = 0; i < MD_LEN; i = i + 1) begin
            if (got_md[i] !== exp_md[i]) begin
                if (errors == 0) begin
                    $display("FAIL HASH_FIRST_MISMATCH name=hash_c0550_m549 Count=550 MSG_LEN=%0d idx=%0d got_byte=%02x exp_byte=%02x",
                             MSG_LEN, i, got_md[i], exp_md[i]);
                end
                errors = errors + 1;
            end
        end

        $write("GOT_MD name=hash_c0550_m549 Count=550 MSG_LEN=%0d got=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", got_md[i]);
        $display("");

        $write("EXP_MD name=hash_c0550_m549 Count=550 MSG_LEN=%0d exp=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", exp_md[i]);
        $display("");

        if (errors == 0)
            $display("PASS HASH_KAT name=hash_c0550_m549 Count=550 MSG_LEN=%0d MD_LEN=32", MSG_LEN);
        else
            $display("FAIL HASH_KAT name=hash_c0550_m549 Count=550 MSG_LEN=%0d errors=%0d", MSG_LEN, errors);

        $finish;
    end

endmodule

`default_nettype wire
