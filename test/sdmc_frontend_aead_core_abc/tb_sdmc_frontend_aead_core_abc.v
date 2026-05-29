`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_sdmc_frontend_aead_core_abc;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;

    always #5 clk = ~clk;

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
    wire        aead_in_pop;
    wire        front_busy;
    wire        front_error;
    wire [3:0]  front_phase;

    wire [`SDMC_TOKEN_W-1:0] aead_out_token;
    wire        aead_out_push;
    reg         aead_out_full = 1'b0;
    wire        aead_busy;
    wire        aead_done;
    wire        aead_error;
    wire        aead_auth_ok;

    sdmc_aead_uart_frontend u_front (
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

        .busy(front_busy),
        .error(front_error),
        .phase_dbg(front_phase)
    );

    sdmc_aead128_core u_aead (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .start(aead_start),
        .is_decrypt(aead_is_decrypt),
        .ad_len(aead_ad_len),
        .data_len(aead_data_len),

        .in_token(aead_in_token),
        .in_empty(aead_in_empty),
        .in_pop(aead_in_pop),

        .out_token(aead_out_token),
        .out_push(aead_out_push),
        .out_full(aead_out_full),

        .busy(aead_busy),
        .done(aead_done),
        .error(aead_error),
        .auth_ok(aead_auth_ok)
    );

    reg [7:0] expected [0:18];
    reg [7:0] got [0:18];
    integer out_idx;
    integer byte_cursor;

    initial begin
        expected[0]  = 8'ha9; expected[1]  = 8'h80; expected[2]  = 8'h9f;
        expected[3]  = 8'h51; expected[4]  = 8'h76; expected[5]  = 8'h28;
        expected[6]  = 8'ha4; expected[7]  = 8'h0f; expected[8]  = 8'h72;
        expected[9]  = 8'h90; expected[10] = 8'h02; expected[11] = 8'hc2;
        expected[12] = 8'h13; expected[13] = 8'h09; expected[14] = 8'hc2;
        expected[15] = 8'h96; expected[16] = 8'hb2; expected[17] = 8'h5c;
        expected[18] = 8'h17;
    end

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task send0;
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

    task send1;
        input [7:0] b;
        begin
            rx1_byte = b;
            rx1_valid = 1'b1;
            tick();
            rx1_valid = 1'b0;
            rx1_byte = 8'd0;
            repeat (250) tick();
        end
    endtask

    task send2;
        input [7:0] b;
        begin
            rx2_byte = b;
            rx2_valid = 1'b1;
            tick();
            rx2_valid = 1'b0;
            rx2_byte = 8'd0;
            repeat (250) tick();
        end
    endtask

    task automatic capture_token_bytes;
        input [`SDMC_TOKEN_W-1:0] tok;
        integer j;
        reg [3:0] nbytes;
        reg [63:0] data;
        reg [7:0] b;
        begin
            nbytes = tok[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
            data   = tok[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

            for (j = 0; j < 8; j = j + 1) begin
                if ((j < nbytes) && (byte_cursor < 19)) begin
                    case (j[2:0])
                        3'd0: b = data[7:0];
                        3'd1: b = data[15:8];
                        3'd2: b = data[23:16];
                        3'd3: b = data[31:24];
                        3'd4: b = data[39:32];
                        3'd5: b = data[47:40];
                        3'd6: b = data[55:48];
                        3'd7: b = data[63:56];
                        default: b = 8'd0;
                    endcase

                    got[byte_cursor] = b;
                    $display("CAP_BYTE[%0d]=%02x", byte_cursor, b);
                    byte_cursor = byte_cursor + 1;
                end
            end

            out_idx = byte_cursor;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            out_idx <= 0;
            byte_cursor <= 0;
        end else if (aead_out_push && !aead_out_full) begin
            capture_token_bytes(aead_out_token);
        end
    end

    integer k;

    always @(posedge clk) begin
        if (rst_n) begin
            if (!aead_in_empty) begin
                $display("IN_TOKEN t=%0t phase=%0d last=%0d kind=%0d bytes=%0d data=%016x pop=%b",
                    $time,
                    front_phase,
                    aead_in_token[`SDMC_TOKEN_LAST_BIT],
                    aead_in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB],
                    aead_in_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB],
                    aead_in_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB],
                    aead_in_pop);
            end
            if (aead_out_push) begin
                $display("OUT_TOKEN t=%0t kind=%0d data=%016x out_idx=%0d",
                    $time,
                    aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB],
                    aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB],
                    out_idx);
            end
        end
    end


    integer guard;

    initial begin
        $dumpfile("tb_sdmc_frontend_aead_core_abc.vcd");
        $dumpvars(0, tb_sdmc_frontend_aead_core_abc);

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

        // Key.
        for (k = 0; k < 16; k = k + 1) send1(k[7:0]);

        // Nonce.
        for (k = 16; k < 32; k = k + 1) send1(k[7:0]);

        // Plaintext "abc".
        send2(8'h61);
        send2(8'h62);
        send2(8'h63);

        guard = 0;
        while (out_idx < 19) begin
            tick();
            guard = guard + 1;
            if (guard > 50000) begin
                $display("FAIL timeout out_idx=%0d phase=%0d front_busy=%b front_err=%b aead_busy=%b aead_done=%b aead_err=%b in_empty=%b in_pop=%b out_push=%b",
                    out_idx, front_phase, front_busy, front_error, aead_busy, aead_done, aead_error,
                    aead_in_empty, aead_in_pop, aead_out_push);
                $finish;
            end
        end

        $write("GOT=");
        for (k = 0; k < 19; k = k + 1) $write("%02x", got[k]);
        $write("\nEXP=");
        for (k = 0; k < 19; k = k + 1) $write("%02x", expected[k]);
        $write("\n");

        for (k = 0; k < 19; k = k + 1) begin
            if (got[k] !== expected[k]) begin
                $display("FAIL mismatch idx=%0d got=%02x exp=%02x", k, got[k], expected[k]);
                $finish;
            end
        end

        if (front_error || aead_error) begin
            $display("FAIL error front=%b aead=%b", front_error, aead_error);
            $finish;
        end

        $display("PASS sdmc_frontend_aead_core_abc");
        $finish;
    end

endmodule

`default_nettype wire
