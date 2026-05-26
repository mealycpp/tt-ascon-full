`default_nettype none

module sdmc_crypto_helpers (
    input  wire [3:0]  nbytes,
    output reg  [63:0] mask,
    output reg  [63:0] pad
);

    always @* begin
        case (nbytes[2:0])
            3'd0: mask = 64'h0000_0000_0000_0000;
            3'd1: mask = 64'h0000_0000_0000_00FF;
            3'd2: mask = 64'h0000_0000_0000_FFFF;
            3'd3: mask = 64'h0000_0000_00FF_FFFF;
            3'd4: mask = 64'h0000_0000_FFFF_FFFF;
            3'd5: mask = 64'h0000_00FF_FFFF_FFFF;
            3'd6: mask = 64'h0000_FFFF_FFFF_FFFF;
            3'd7: mask = 64'h00FF_FFFF_FFFF_FFFF;
            default: mask = 64'h0000_0000_0000_0000;
        endcase

        case (nbytes[2:0])
            3'd0: pad = 64'h0000_0000_0000_0001;
            3'd1: pad = 64'h0000_0000_0000_0100;
            3'd2: pad = 64'h0000_0000_0001_0000;
            3'd3: pad = 64'h0000_0000_0100_0000;
            3'd4: pad = 64'h0000_0001_0000_0000;
            3'd5: pad = 64'h0000_0100_0000_0000;
            3'd6: pad = 64'h0001_0000_0000_0000;
            3'd7: pad = 64'h0100_0000_0000_0000;
            default: pad = 64'h0000_0000_0000_0001;
        endcase
    end

endmodule

`default_nettype wire
