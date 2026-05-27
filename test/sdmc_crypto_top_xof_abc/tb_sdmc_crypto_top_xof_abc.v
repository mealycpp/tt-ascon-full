`timescale 1ns/1ps
`default_nettype none

`include "sdmc_modes.vh"
`include "sdmc_stream_defs.vh"

module tb_sdmc_crypto_top_xof_abc;

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

    reg [255:0] digest;
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

    integer i;

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            digest <= 256'd0;
            out_idx <= 6'd0;
        end else if (out_valid && out_ready) begin
            if (out_kind !== `SDMC_TOK_OUT) begin
                $display("FAIL bad out_kind=%h", out_kind);
                $finish;
            end

            case (out_idx)
                6'd0:  digest[7:0]     <= out_byte;
                6'd1:  digest[15:8]    <= out_byte;
                6'd2:  digest[23:16]   <= out_byte;
                6'd3:  digest[31:24]   <= out_byte;
                6'd4:  digest[39:32]   <= out_byte;
                6'd5:  digest[47:40]   <= out_byte;
                6'd6:  digest[55:48]   <= out_byte;
                6'd7:  digest[63:56]   <= out_byte;
                6'd8:  digest[71:64]   <= out_byte;
                6'd9:  digest[79:72]   <= out_byte;
                6'd10: digest[87:80]   <= out_byte;
                6'd11: digest[95:88]   <= out_byte;
                6'd12: digest[103:96]  <= out_byte;
                6'd13: digest[111:104] <= out_byte;
                6'd14: digest[119:112] <= out_byte;
                6'd15: digest[127:120] <= out_byte;
                6'd16: digest[135:128] <= out_byte;
                6'd17: digest[143:136] <= out_byte;
                6'd18: digest[151:144] <= out_byte;
                6'd19: digest[159:152] <= out_byte;
                6'd20: digest[167:160] <= out_byte;
                6'd21: digest[175:168] <= out_byte;
                6'd22: digest[183:176] <= out_byte;
                6'd23: digest[191:184] <= out_byte;
                6'd24: digest[199:192] <= out_byte;
                6'd25: digest[207:200] <= out_byte;
                6'd26: digest[215:208] <= out_byte;
                6'd27: digest[223:216] <= out_byte;
                6'd28: digest[231:224] <= out_byte;
                6'd29: digest[239:232] <= out_byte;
                6'd30: digest[247:240] <= out_byte;
                6'd31: digest[255:248] <= out_byte;
                default: ;
            endcase

            if (out_idx == 6'd31 && !out_last) begin
                $display("FAIL final byte missing out_last");
                $finish;
            end

            out_idx <= out_idx + 6'd1;
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_sdmc_crypto_top_xof_abc.vcd");
        $dumpvars(0, tb_sdmc_crypto_top_xof_abc);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        // CFG_MODE = HASH
        cfg_write(4'd0, {60'd0, `SDMC_HOST_XOF});

        // CFG_LEN0: msg_len=3, cs_len=0, ad_len=0, out_len=32
        cfg_write(4'd1, {16'd32, 16'd0, 16'd0, 16'd3});

        // Feed MSG bytes: "abc"
        in_kind  = `SDMC_TOK_MSG;
        in_byte  = 8'h61;
        in_last  = 1'b0;
        in_valid = 1'b1;
        tick();

        in_byte  = 8'h62;
        in_last  = 1'b0;
        tick();

        in_byte  = 8'h63;
        in_last  = 1'b1;
        tick();

        in_valid = 1'b0;
        in_last  = 1'b0;
        in_kind  = 4'd0;
        in_byte  = 8'd0;
        repeat (3) tick();

        start = 1'b1;
        tick();
        start = 1'b0;

        guard = 0;
        while (!done) begin
            tick();
            guard = guard + 1;
            if (guard > 4000) begin
                $display("FAIL timeout waiting done");
                $finish;
            end
        end

        // Drain output FIFO/egress bytes.
        guard = 0;
        while (out_idx < 6'd32) begin
            tick();
            guard = guard + 1;
            if (guard > 1000) begin
                $display("FAIL timeout draining output out_idx=%0d", out_idx);
                $finish;
            end
        end

        tick();

        if (error) begin
            $display("FAIL error asserted");
            $finish;
        end

        if (digest !== 256'h0b2f0bb2a67a3cce193dc16efe09c00857927f1868aa5b503242723d619871b8) begin
            $display("FAIL digest mismatch got=%h", digest);
            $finish;
        end

        $display("PASS sdmc_crypto_top_xof_abc");
        $finish;
    end

endmodule

`default_nettype wire
