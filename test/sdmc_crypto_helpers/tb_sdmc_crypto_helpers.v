`timescale 1ns/1ps
`default_nettype none

module tb_sdmc_crypto_helpers;

    reg [3:0] nbytes;
    wire [63:0] mask;
    wire [63:0] pad;

    sdmc_crypto_helpers dut (
        .nbytes(nbytes),
        .mask(mask),
        .pad(pad)
    );

    task check;
        input [3:0] n;
        input [63:0] exp_mask;
        input [63:0] exp_pad;
        begin
            nbytes = n;
            #1;
            if (mask !== exp_mask || pad !== exp_pad) begin
                $display("FAIL n=%0d mask=%h pad=%h exp_mask=%h exp_pad=%h",
                         n, mask, pad, exp_mask, exp_pad);
                $finish;
            end
        end
    endtask

    initial begin
        check(4'd0, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0001);
        check(4'd1, 64'h0000_0000_0000_00FF, 64'h0000_0000_0000_0100);
        check(4'd2, 64'h0000_0000_0000_FFFF, 64'h0000_0000_0001_0000);
        check(4'd3, 64'h0000_0000_00FF_FFFF, 64'h0000_0000_0100_0000);
        check(4'd4, 64'h0000_0000_FFFF_FFFF, 64'h0000_0001_0000_0000);
        check(4'd5, 64'h0000_00FF_FFFF_FFFF, 64'h0000_0100_0000_0000);
        check(4'd6, 64'h0000_FFFF_FFFF_FFFF, 64'h0001_0000_0000_0000);
        check(4'd7, 64'h00FF_FFFF_FFFF_FFFF, 64'h0100_0000_0000_0000);
        check(4'd8, 64'h0000_0000_0000_0000, 64'h0000_0000_0000_0001);

        $display("PASS sdmc_crypto_helpers");
        $finish;
    end

endmodule

`default_nettype wire
