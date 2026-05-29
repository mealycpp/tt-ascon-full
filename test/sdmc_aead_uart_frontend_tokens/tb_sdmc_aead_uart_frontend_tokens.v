`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_aead_uart_frontend_tokens;

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

    wire [`SDMC_TOKEN_W-1:0] aead_in_token;
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

    task send0;
        input [7:0] b;
        begin
            rx0_byte = b; rx0_valid = 1'b1; tick();
            rx0_valid = 1'b0; rx0_byte = 8'd0; tick();
        end
    endtask

    task send1;
        input [7:0] b;
        begin
            rx1_byte = b; rx1_valid = 1'b1; tick();
            rx1_valid = 1'b0; rx1_byte = 8'd0; tick();
        end
    endtask

    task send2;
        input [7:0] b;
        begin
            rx2_byte = b; rx2_valid = 1'b1; tick();
            rx2_valid = 1'b0; rx2_byte = 8'd0; tick();
        end
    endtask

    task pop_expect;
        input [3:0] exp_kind;
        input [3:0] exp_bytes;
        input [63:0] exp_data;
        input exp_last;
        integer guard;
        reg got_last;
        reg [3:0] got_kind;
        reg [3:0] got_bytes;
        reg [63:0] got_data;
        begin
            guard = 0;
            while (aead_in_empty) begin
                tick();
                guard = guard + 1;
                if (guard > 1000) begin
                    $display("FAIL timeout waiting token exp_kind=%0d phase=%0d busy=%b err=%b",
                        exp_kind, phase_dbg, busy, error);
                    $finish;
                end
            end

            got_last  = aead_in_token[`SDMC_TOKEN_LAST_BIT];
            got_kind  = aead_in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
            got_bytes = aead_in_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
            got_data  = aead_in_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

            $display("TOK last=%0d kind=%0d bytes=%0d data=%016x",
                got_last, got_kind, got_bytes, got_data);

            if (got_last !== exp_last || got_kind !== exp_kind ||
                got_bytes !== exp_bytes || got_data !== exp_data) begin
                $display("FAIL token mismatch");
                $display("EXP last=%0d kind=%0d bytes=%0d data=%016x",
                    exp_last, exp_kind, exp_bytes, exp_data);
                $finish;
            end

            aead_in_pop = 1'b1;
            tick();
            aead_in_pop = 1'b0;
            tick();
        end
    endtask

    integer k;

    initial begin
        $dumpfile("tb_sdmc_aead_uart_frontend_tokens.vcd");
        $dumpvars(0, tb_sdmc_aead_uart_frontend_tokens);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (5) tick();

        // Command: AEAD_ENC, AD=0, DATA=3.
        send0(8'hA5);
        send0(8'd5);
        send0(8'h00);
        send0(8'h00);
        send0(8'h00);
        send0(8'd3);
        send0(8'h00);
        send0(8'h00);
        send0(8'h00);
        send0(8'd1);
        send0(8'h00);
        send0(8'h00);
        send0(8'h00);
        send0(8'h5A);

        if (!busy || error || aead_ad_len !== 16'd0 || aead_data_len !== 16'd3) begin
            $display("FAIL command state busy=%b err=%b ad=%0d data=%0d phase=%0d",
                busy, error, aead_ad_len, aead_data_len, phase_dbg);
            $finish;
        end

        // Feed and check KEY0 = 0706050403020100 in token little-endian packing.
        for (k = 0; k < 8; k = k + 1) send1(k[7:0]);
        pop_expect(`SDMC_TOK_KEY, 4'd8, 64'h0706050403020100, 1'b0);

        // KEY1 = 0f0e0d0c0b0a0908, last key phase.
        for (k = 8; k < 16; k = k + 1) send1(k[7:0]);
        pop_expect(`SDMC_TOK_KEY, 4'd8, 64'h0f0e0d0c0b0a0908, 1'b1);

        // NONCE0 = 1716151413121110.
        for (k = 16; k < 24; k = k + 1) send1(k[7:0]);
        pop_expect(`SDMC_TOK_NONCE, 4'd8, 64'h1716151413121110, 1'b0);

        // NONCE1 = 1f1e1d1c1b1a1918, last nonce phase.
        for (k = 24; k < 32; k = k + 1) send1(k[7:0]);
        pop_expect(`SDMC_TOK_NONCE, 4'd8, 64'h1f1e1d1c1b1a1918, 1'b1);

        // MSG = abc, 3 bytes, last.
        send2(8'h61);
        send2(8'h62);
        send2(8'h63);
        pop_expect(`SDMC_TOK_MSG, 4'd3, 64'h0000000000636261, 1'b1);

        $display("PASS sdmc_aead_uart_frontend_tokens");
        $finish;
    end

endmodule

`default_nettype wire
