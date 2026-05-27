`timescale 1ns/1ps
`default_nettype none

`include "sdmc_modes.vh"
`include "sdmc_stream_defs.vh"

module tb_sdmc_crypto_top_aead_abc;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg start = 1'b0;

    reg cfg_wr_en = 1'b0;
    reg [3:0] cfg_wr_addr = 4'd0;
    reg [63:0] cfg_wr_data = 64'd0;

    reg [7:0] in_byte = 8'd0;
    reg [3:0] in_kind = 4'd0;
    reg in_last = 1'b0;
    reg in_valid = 1'b0;
    wire in_ready;

    wire [7:0] out_byte;
    wire [3:0] out_kind;
    wire out_last;
    wire out_valid;
    reg out_ready = 1'b1;

    wire busy;
    wire done;
    wire error;
    wire auth_ok;
    wire [3:0] host_mode;
    wire [3:0] program_id;
    wire [15:0] in_count;
    wire [15:0] out_count;

    reg [151:0] enc_out;
    reg [5:0] out_idx;

    sdmc_crypto_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),

        .cfg_wr_en(cfg_wr_en),
        .cfg_wr_addr(cfg_wr_addr),
        .cfg_wr_data(cfg_wr_data),

        .in_byte(in_byte),
        .in_kind(in_kind),
        .in_last(in_last),
        .in_valid(in_valid),
        .in_ready(in_ready),

        .out_byte(out_byte),
        .out_kind(out_kind),
        .out_last(out_last),
        .out_valid(out_valid),
        .out_ready(out_ready),

        .busy(busy),
        .done(done),
        .error(error),
        .auth_ok(auth_ok),

        .host_mode(host_mode),
        .program_id(program_id),

        .in_count(in_count),
        .out_count(out_count)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task cfg_write;
        input [3:0] addr;
        input [63:0] data;
        begin
            cfg_wr_addr = addr;
            cfg_wr_data = data;
            cfg_wr_en = 1'b1;
            tick();
            cfg_wr_en = 1'b0;
            cfg_wr_addr = 4'd0;
            cfg_wr_data = 64'd0;
            tick();
        end
    endtask

    task drive_byte;
        input [3:0] kind;
        input [7:0] data;
        input last;
        begin
            while (!in_ready) tick();
            in_kind = kind;
            in_byte = data;
            in_last = last;
            in_valid = 1'b1;
            tick();
            in_valid = 1'b0;
            in_last = 1'b0;
            in_kind = 4'd0;
            in_byte = 8'd0;
            tick();
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            enc_out <= 152'd0;
            out_idx <= 6'd0;
        end else if (out_valid && out_ready) begin
            if (out_idx < 6'd19) begin
                enc_out[out_idx*8 +: 8] <= out_byte;
            end

            if (out_idx < 6'd3) begin
                if (out_kind !== `SDMC_TOK_OUT) begin
                    $display("FAIL bad ciphertext kind=%h at idx=%0d", out_kind, out_idx);
                    $finish;
                end
            end else begin
                if (out_kind !== `SDMC_TOK_TAG) begin
                    $display("FAIL bad tag kind=%h at idx=%0d", out_kind, out_idx);
                    $finish;
                end
            end

            if (out_idx == 6'd18 && !out_last) begin
                $display("FAIL final output missing out_last");
                $finish;
            end

            out_idx <= out_idx + 6'd1;
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_crypto_top_aead_abc.vcd");
        $dumpvars(0, tb_sdmc_crypto_top_aead_abc);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        // CFG_MODE = AEAD_ENC
        cfg_write(4'd0, {60'd0, `SDMC_HOST_AEAD_ENC});

        // CFG_LEN0: msg_len=3, cs_len=0, ad_len=0, out_len=0
        cfg_write(4'd1, {16'd0, 16'd0, 16'd0, 16'd3});

        // KEY = 000102030405060708090a0b0c0d0e0f
        drive_byte(`SDMC_TOK_KEY, 8'h00, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h01, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h02, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h03, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h04, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h05, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h06, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h07, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h08, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h09, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h0a, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h0b, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h0c, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h0d, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h0e, 1'b0);
        drive_byte(`SDMC_TOK_KEY, 8'h0f, 1'b1);

        // NONCE = 101112131415161718191a1b1c1d1e1f
        drive_byte(`SDMC_TOK_NONCE, 8'h10, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h11, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h12, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h13, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h14, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h15, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h16, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h17, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h18, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h19, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h1a, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h1b, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h1c, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h1d, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h1e, 1'b0);
        drive_byte(`SDMC_TOK_NONCE, 8'h1f, 1'b1);

        // PT = abc
        drive_byte(`SDMC_TOK_MSG, 8'h61, 1'b0);
        drive_byte(`SDMC_TOK_MSG, 8'h62, 1'b0);
        drive_byte(`SDMC_TOK_MSG, 8'h63, 1'b1);

        repeat (3) tick();

        start = 1'b1;
        tick();
        start = 1'b0;

        guard = 0;
        while (!done) begin
            tick();
            guard = guard + 1;
            if (guard > 6000) begin
                $display("FAIL timeout waiting done");
                $finish;
            end
        end

        tick();

        if (error) begin
            $display("FAIL error asserted after done");
            $display("DBG host_mode=%0d program_id=%0d in_count=%0d out_count=%0d out_idx=%0d auth_ok=%b",
                     host_mode, program_id, in_count, out_count, out_idx, auth_ok);
            $display("DBG aead_state=%0d aead_error=%b aead_done=%b aead_busy=%b core_in_empty=%b",
                     dut.u_aead.state, dut.aead_error, dut.aead_done, dut.aead_busy, dut.core_in_empty);
            $finish;
        end

        guard = 0;
        while (out_idx < 6'd19) begin
            tick();
            guard = guard + 1;
            if ((guard % 100) == 0) begin
                $display("DRAIN DBG guard=%0d out_idx=%0d out_count=%0d out_valid=%b out_kind=%h out_last=%b done=%b error=%b",
                         guard, out_idx, out_count, out_valid, out_kind, out_last, done, error);
            end
            if (guard > 1000) begin
                $display("FAIL timeout draining output out_idx=%0d", out_idx);
                $display("DBG host_mode=%0d program_id=%0d in_count=%0d out_count=%0d auth_ok=%b",
                         host_mode, program_id, in_count, out_count, auth_ok);
                $display("DBG aead_state=%0d aead_error=%b aead_done=%b aead_busy=%b core_out_full=%b",
                         dut.u_aead.state, dut.aead_error, dut.aead_done, dut.aead_busy, dut.core_out_full);
                $finish;
            end
        end

        tick();

        if (enc_out !== 152'h175cb296c20913c20290720fa42876519f80a9) begin
            $display("FAIL enc_out mismatch got=%h", enc_out);
            $finish;
        end

        $display("PASS sdmc_crypto_top_aead_abc");
        $finish;
    end

endmodule

`default_nettype wire
