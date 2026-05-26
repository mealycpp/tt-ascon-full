`default_nettype none

module sdmc_regfile64 #(
    parameter AW = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        wr_en,
    input  wire [AW-1:0] wr_addr,
    input  wire [63:0] wr_data,

    input  wire        rd_en,
    input  wire [AW-1:0] rd_addr_a,
    input  wire [AW-1:0] rd_addr_b,
    output reg  [63:0] rd_data_a,
    output reg  [63:0] rd_data_b,
    output reg         rd_valid,

    output wire [63:0] r0,
    output wire [63:0] r1,
    output wire [63:0] r2,
    output wire [63:0] r3,
    output wire [63:0] r4
);

    reg [63:0] regs [0:15];

    integer i;

    assign r0 = regs[0];
    assign r1 = regs[1];
    assign r2 = regs[2];
    assign r3 = regs[3];
    assign r4 = regs[4];

    function [63:0] read_reg;
        input [AW-1:0] addr;
        begin
            case (addr)
                4'd0:  read_reg = regs[0];
                4'd1:  read_reg = regs[1];
                4'd2:  read_reg = regs[2];
                4'd3:  read_reg = regs[3];
                4'd4:  read_reg = regs[4];
                4'd5:  read_reg = regs[5];
                4'd6:  read_reg = regs[6];
                4'd7:  read_reg = regs[7];
                4'd8:  read_reg = regs[8];
                4'd9:  read_reg = regs[9];
                4'd10: read_reg = regs[10];
                4'd11: read_reg = regs[11];
                4'd12: read_reg = regs[12];
                4'd13: read_reg = regs[13];
                4'd14: read_reg = regs[14];
                4'd15: read_reg = regs[15];
                default: read_reg = 64'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                regs[i] <= 64'd0;
            end
            rd_data_a <= 64'd0;
            rd_data_b <= 64'd0;
            rd_valid  <= 1'b0;
        end else if (clear) begin
            for (i = 0; i < 16; i = i + 1) begin
                regs[i] <= 64'd0;
            end
            rd_data_a <= 64'd0;
            rd_data_b <= 64'd0;
            rd_valid  <= 1'b0;
        end else begin
            rd_valid <= 1'b0;

            if (wr_en) begin
                regs[wr_addr] <= wr_data;
            end

            if (rd_en) begin
                rd_data_a <= (wr_en && (wr_addr == rd_addr_a)) ? wr_data : read_reg(rd_addr_a);
                rd_data_b <= (wr_en && (wr_addr == rd_addr_b)) ? wr_data : read_reg(rd_addr_b);
                rd_valid  <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
